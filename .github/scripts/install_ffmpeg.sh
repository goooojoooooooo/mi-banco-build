#!/usr/bin/env bash
# Instala ffmpeg estático (eugeneware/ffmpeg-static) con versión fija y verificación SHA-256 en macOS.
# Imprime por stdout la ruta del binario verificado.
set -euo pipefail

VERSION="b6.1.1"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64)
    ASSET="ffmpeg-darwin-arm64.gz"
    GZ_SHA256="8923876afa8db5585022d7860ec7e589af192f441c56793971276d450ed3bbfa"
    BIN_SHA256="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"
    ;;
  x86_64)
    ASSET="ffmpeg-darwin-x64.gz"
    GZ_SHA256="929b375c1182d956c51f7ac25e0b2b0411fb01f6f407aa15c9758efeb4242106"
    BIN_SHA256="ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894"
    ;;
  *)
    echo "Arquitectura no soportada para ffmpeg: $ARCH" >&2
    exit 1
    ;;
esac

URL="https://github.com/eugeneware/ffmpeg-static/releases/download/${VERSION}/${ASSET}"
WORKDIR="${RUNNER_TEMP:-/tmp}/ffmpeg-${VERSION}-${ARCH}"
GZ="${WORKDIR}/${ASSET}"
BIN="${WORKDIR}/ffmpeg"

if [ ! -x "$BIN" ]; then
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  curl -fsSL --proto '=https' --tlsv1.2 "$URL" -o "$GZ"
  printf '%s  %s\n' "$GZ_SHA256" "$GZ" | shasum -a 256 -c - >&2
  gunzip -c "$GZ" > "$BIN"
  rm -f "$GZ"
  printf '%s  %s\n' "$BIN_SHA256" "$BIN" | shasum -a 256 -c - >&2
  chmod +x "$BIN"
  if command -v codesign >/dev/null 2>&1; then
    codesign -v "$BIN" >/dev/null 2>&1 || codesign --force --sign - "$BIN" >&2
  fi
fi

printf '%s\n' "$BIN"
