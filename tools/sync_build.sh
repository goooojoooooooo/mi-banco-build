#!/usr/bin/env bash
# Copies the app's code (no docs, no design files) from this private repo's HEAD
# into the public build repo next to it and pushes, so GitHub Actions can build for free.
# Usage: bash tools/sync_build.sh   (run from anywhere inside the private repo, with a clean tree)
set -euo pipefail
SRC="$(git rev-parse --show-toplevel)"
DST="$SRC/../mi-banco-build"
SHA="$(git -C "$SRC" rev-parse --short HEAD)"
[ -d "$DST/.git" ] || { echo "No existe $DST"; exit 1; }
# Tracked files only, so nothing private that is merely on disk can leak.
git -C "$DST" rm -rq --ignore-unmatch . >/dev/null
git -C "$SRC" archive HEAD App Core NotificationExt Widgets Shared project.yml .github .gitignore tools \
  | tar -x -C "$DST" --exclude='tools/__pycache__'
git -C "$DST" add -A
if git -C "$DST" diff --cached --quiet; then echo "Sin cambios ($SHA)"; exit 0; fi
git -C "$DST" commit -qm "sync $SHA"
git -C "$DST" push -q origin main
echo "Publicado $SHA en el repositorio de compilación"
