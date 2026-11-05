#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_root="$repo_root/_build/linux-toolchain"
moon_install_root="$archive_root/moon"
pin_file="$repo_root/scripts/linux-toolchain.json"

if [[ "$(uname -ms)" != "Linux x86_64" ]]; then
  printf 'This pinned CI toolchain requires Linux x86_64.\n' >&2
  exit 1
fi

mkdir -p "$archive_root" "$moon_install_root/lib"

download_checked() {
  local component="$1"
  local archive_file="$2"
  local url
  local digest
  url="$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8"))[process.argv[2]].url)' "$pin_file" "$component")"
  digest="$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8"))[process.argv[2]].sha256)' "$pin_file" "$component")"
  if [[ ! -f "$archive_file" ]]; then
    curl --fail --location --retry 2 --connect-timeout 10 --max-time 180 \
      --output "$archive_file" "$url"
  fi
  printf '%s  %s\n' "$digest" "$archive_file" | sha256sum --check --status
}

download_checked binary "$archive_root/moonbit-linux-x86_64.tar.gz"
download_checked core "$archive_root/core.tar.gz"
tar -xzf "$archive_root/moonbit-linux-x86_64.tar.gz" -C "$moon_install_root"
tar -xzf "$archive_root/core.tar.gz" -C "$moon_install_root/lib"
# Official archives ship binaries without execute bits; mirror the upstream installer.
chmod +x "$moon_install_root"/bin/* "$moon_install_root/bin/internal/tcc"

export MOON_HOME="$moon_install_root"
export PATH="$MOON_HOME/bin:$PATH"
moon -C "$MOON_HOME/lib/core" bundle --warn-list -a --all
moon -C "$MOON_HOME/lib/core" bundle --warn-list -a --target wasm-gc --quiet
moon version --all

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$MOON_HOME/bin" >> "$GITHUB_PATH"
  printf 'MOON_HOME=%s\n' "$MOON_HOME" >> "$GITHUB_ENV"
fi
