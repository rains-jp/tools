#!/usr/bin/env bash
set -euo pipefail

URL="${SCRIPT_URL:-https://raw.githubusercontent.com/rains-jp/tools/main/alma-linux-initial-setup.sh}"
SHA="${SCRIPT_SHA256-1991dde97ab3addc6615f82adc703097c0c6eaf881511ff6386c5db1dfbb9e83}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  dnf install -y curl ca-certificates
fi

if command -v curl >/dev/null 2>&1; then
  curl -fsSL --retry 5 --connect-timeout 15 -o "$TMP" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP" "$URL"
else
  echo "ERROR: curl or wget is required." >&2
  exit 1
fi

if [[ -n "$SHA" ]]; then
  printf '%s  %s\n' "$SHA" "$TMP" | sha256sum -c - >/dev/null
fi

exec bash "$TMP" "$@"
