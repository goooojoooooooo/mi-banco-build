#!/usr/bin/env bash
# Copies the app's code (no docs, no design files) from this private repo's HEAD
# into the public build repo next to it and pushes, so GitHub Actions can build for free.
# Usage: bash tools/sync_build.sh   (run from anywhere inside the private repo, with a clean tree)
set -euo pipefail
SRC="$(git rev-parse --show-toplevel)"
# A second stream of work uses its own clone and branch: BUILD_DIR=... BUILD_BRANCH=... bash tools/sync_build.sh
DST="${BUILD_DIR:-$SRC/../mi-banco-build}"
BRANCH="${BUILD_BRANCH:-main}"
SHA="$(git -C "$SRC" rev-parse --short HEAD)"
[ -d "$DST/.git" ] || { echo "No existe $DST"; exit 1; }
[ "$(git -C "$DST" rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || { echo "$DST no está en la rama $BRANCH"; exit 1; }
# Tracked files only, so nothing private that is merely on disk can leak.
git -C "$DST" rm -rq --ignore-unmatch . >/dev/null
# Only code folders, and only those that exist in HEAD (UITests and Redirect arrive later).
PATHS=()
for p in App Core NotificationExt Widgets Shared UITests Redirect project.yml .github .gitignore tools; do
  if git -C "$SRC" cat-file -e "HEAD:$p" 2>/dev/null; then PATHS+=("$p"); fi
done
git -C "$SRC" archive HEAD "${PATHS[@]}" \
  | tar -x -C "$DST" --exclude='tools/__pycache__'
git -C "$DST" add -A
if git -C "$DST" diff --cached --quiet; then echo "Sin cambios ($SHA)"; exit 0; fi
git -C "$DST" commit -qm "sync $SHA"
git -C "$DST" push -q origin "$BRANCH"
echo "Publicado $SHA en el repositorio de compilación"
