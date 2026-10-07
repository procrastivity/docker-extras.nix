#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash jq nix curl
# shellcheck shell=bash
set -euo pipefail

latest_release_url=https://api.github.com/repos/procrastivity/docker-extras/releases/latest
release_base_url=https://github.com/procrastivity/docker-extras/releases/download
version_file=VERSION.json

systems=(
  "aarch64-darwin:docker-extras-darwin-arm64.tar.gz"
  "aarch64-linux:docker-extras-linux-arm64.tar.gz"
  "x86_64-linux:docker-extras-linux-amd64.tar.gz"
)

die() { echo "$*" >&2; exit 1; }
out() { [[ -n ${GITHUB_OUTPUT:-} ]] && echo "$1=$2" >> "$GITHUB_OUTPUT" || true; }

latest_tag() {
  local -a auth=()
  [[ -n ${GITHUB_TOKEN:-} ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

  local response tag
  response=$(curl -fsSL "${auth[@]}" "$latest_release_url") \
    || die "Failed to query $latest_release_url"
  tag=$(jq -r '.tag_name // empty' <<< "$response") \
    || die "Failed to parse JSON from $latest_release_url: $response"
  [[ -n "$tag" ]] \
    || die "$latest_release_url returned no .tag_name: $response"
  # releases/latest already excludes prereleases/drafts; belt-and-braces: reject
  # any tag carrying a prerelease suffix (e.g. v1.2.3-rc.1).
  [[ "$tag" != *-* ]] \
    || die "GitHub announced non-stable release tag: $tag"
  [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*$ ]] \
    || die "Unexpected release tag shape: $tag"
  printf '%s\n' "$tag"
}

cleanup() {
  rm -rf "$backup_dir"
}

restore_and_cleanup() {
  local status=$?
  if (( status != 0 )); then
    if [[ -f "$backup_dir/$version_file" ]]; then
      cp "$backup_dir/$version_file" "$version_file" 2>/dev/null || true
    else
      rm -f "$version_file"
    fi
  fi
  cleanup
  exit "$status"
}

# A missing VERSION.json is the bootstrap case: pin whatever is latest.
current_rev=""
[[ -f "$version_file" ]] && current_rev=$(jq -r '.rev' "$version_file")
latest_rev=$(latest_tag)
[[ -n "$latest_rev" ]] || die "Failed to determine latest upstream tag"

target_rev=$current_rev
version_changed=false
if [[ "$latest_rev" != "$current_rev" ]]; then
  target_rev=$latest_rev
  version_changed=true
fi

backup_dir=$(mktemp -d)
[[ -f "$version_file" ]] && cp "$version_file" "$backup_dir/$version_file"
trap restore_and_cleanup EXIT

if [[ "$version_changed" == "true" ]]; then
  echo "Updating $version_file: ${current_rev:-<none>} -> $target_rev"

  # The release publishes SHA256SUMS next to its archives. Every prefetched
  # hash must match it, so the pin is what the release published, not merely
  # whatever the download returned.
  sums=$(curl -fsSL "$release_base_url/$target_rev/SHA256SUMS") \
    || die "Failed to download SHA256SUMS for $target_rev"

  new_json=$(jq -n --arg rev "$target_rev" '{rev: $rev, systems: {}}')

  for entry in "${systems[@]}"; do
    system="${entry%%:*}"
    asset="${entry##*:}"
    url="$release_base_url/$target_rev/$asset"

    published=$(awk -v f="$asset" '$2 == f { print $1; exit }' <<< "$sums")
    [[ "$published" =~ ^[0-9a-f]{64}$ ]] \
      || die "SHA256SUMS for $target_rev has no valid entry for $asset"
    expected=$(nix hash convert --hash-algo sha256 --to sri "$published")

    echo "Prefetching $system: $url"
    prefetch_json=$(nix store prefetch-file --json "$url")
    hash=$(jq -r .hash <<< "$prefetch_json")
    [[ "$hash" == "$expected" ]] \
      || die "$asset hash $hash does not match SHA256SUMS ($expected)"

    new_json=$(jq \
      --arg system "$system" \
      --arg url "$url" \
      --arg hash "$hash" \
      '.systems[$system] = {url: $url, hash: $hash}' \
      <<< "$new_json")
  done

  tmp=$(mktemp)
  jq . <<< "$new_json" > "$tmp"
  mv "$tmp" "$version_file"
  # A flake sees only files git knows about. On the bootstrap run the file is
  # new, so mark it intent-to-add; this stages no content.
  git ls-files --error-unmatch "$version_file" >/dev/null 2>&1 \
    || git add --intent-to-add "$version_file"

  echo "Verifying host build with updated $version_file..."
  nix build .#docker-extras --no-link >/dev/null
else
  echo "$version_file already points to $current_rev"
fi

out version "$target_rev"
out version_changed "$version_changed"

trap - EXIT
cleanup
