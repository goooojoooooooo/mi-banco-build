#!/usr/bin/env bash
# Comprueba la pagina de vuelta del banco (Redirect/): nada externo, nada que guarde o envie, y la CSP con los hashes exactos.
# Uso: bash tools/check_redirect.sh   (desde cualquier carpeta del repositorio)
set -euo pipefail
cd "$(dirname "$0")/.."

PAGE="Redirect/cb/index.html"
[ -f "$PAGE" ] || { echo "$PAGE no existe"; exit 1; }
[ -f "Redirect/404.html" ] || { echo "Redirect/404.html no existe"; exit 1; }

fail() { echo "FALLO: $1"; exit 1; }

# Nada que cargue, guarde o envie nada.
if grep -rnE 'src=|href="http|<link|<iframe|<img|fetch\(|XMLHttpRequest|sendBeacon|localStorage|console\.|document\.cookie' Redirect; then
  fail "contenido prohibido en Redirect/ (lineas de arriba)"
fi

grep -q '<meta name="referrer" content="no-referrer">' "$PAGE" || fail "falta la meta referrer no-referrer"
grep -q '<meta name="robots" content="noindex">' "$PAGE" || fail "falta la meta robots noindex en $PAGE"
grep -q '<meta name="robots" content="noindex">' Redirect/404.html || fail "falta la meta robots noindex en 404.html"

# Un unico <script> y un unico <style>, cada etiqueta sola en su linea (la de cierre en la columna 0).
[ "$(grep -c '^<script>$' "$PAGE")" = "1" ] && [ "$(grep -c '^</script>$' "$PAGE")" = "1" ] || fail "debe haber un unico <script> inline"
[ "$(grep -c '^<style>$' "$PAGE")" = "1" ] && [ "$(grep -c '^</style>$' "$PAGE")" = "1" ] || fail "debe haber un unico <style> inline"

# Cuerpo exacto entre etiquetas: salto de linea inicial + cada linea con su salto.
body() {
  awk -v tag="$1" '
    $0 == "</" tag ">" { inside = 0 }
    inside { print }
    $0 == "<" tag ">" { inside = 1; printf "\n" }
  ' "$PAGE"
}
S="$(body script | openssl dgst -sha256 -binary | base64)"
T="$(body style | openssl dgst -sha256 -binary | base64)"
EXPECTED="<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'sha256-$S'; style-src 'sha256-$T'; base-uri 'none'; form-action 'none'\">"
grep -qxF "$EXPECTED" "$PAGE" || fail "la CSP no coincide con los hashes del script y el estilo (script $S, estilo $T)"

echo "Redirect OK"
