#!/usr/bin/env bash
# Instala XcodeGen desde su release oficial con versión fija y comprobación SHA-256, y genera el proyecto Xcode.
set -euo pipefail

VERSION="2.49.0"
SHA256="ae5598b33a19ad1e23e775d6648f97375c3529c970905f489358a21055b65e53"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"

WORKDIR="${RUNNER_TEMP:-/tmp}/xcodegen-${VERSION}"
ZIP="${WORKDIR}/xcodegen.zip"
BIN="${WORKDIR}/xcodegen/bin/xcodegen"

if [ ! -x "$BIN" ]; then
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  curl -fsSL --proto '=https' --tlsv1.2 "$URL" -o "$ZIP"
  printf '%s  %s\n' "$SHA256" "$ZIP" | shasum -a 256 -c -
  unzip -q "$ZIP" -d "$WORKDIR"
  rm -f "$ZIP"
  chmod +x "$BIN"
fi

"$BIN" --version
exec "$BIN" "$@"
