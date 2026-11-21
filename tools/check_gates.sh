#!/usr/bin/env bash
# Comprobaciones automaticas del codigo (se ejecuta desde la raiz del repo, en Linux).
# Uso: bash tools/check_gates.sh [--self-test]
set -euo pipefail

FALLOS=0
AVISOS=0

APP_DIRS=(App Core/Sources NotificationExt Widgets Shared)
HIGIENE_RUTAS=(App Core NotificationExt Widgets Shared UITests project.yml tools .github)

fallo() { # mensaje, lineas...
  local msg="$1"; shift
  echo "FALLO: $msg"
  printf '  %s\n' "$@"
  FALLOS=$((FALLOS + 1))
}

aviso() { # mensaje, lineas...
  local msg="$1"; shift
  echo "AVISO: $msg"
  printf '  %s\n' "$@"
  AVISOS=$((AVISOS + 1))
}

# Rutas existentes de una lista (relativas a $PWD).
existentes() {
  local d
  for d in "$@"; do if [ -e "$d" ]; then printf '%s\n' "$d"; fi; done
  return 0
}

# a) Registros prohibidos en codigo de la app.
check_registros() {
  local dirs=() d res
  while IFS= read -r d; do dirs+=("$d"); done < <(existentes "${APP_DIRS[@]}")
  [ ${#dirs[@]} -gt 0 ] || return 0
  res=$(grep -rnIE --include='*.swift' \
    '(^|[^A-Za-z0-9_.])(print|debugPrint|dump|NSLog|os_log|Logger)\(' "${dirs[@]}" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)
  if [ -n "$res" ]; then
    mapfile -t l <<<"$res"
    fallo "Registros prohibidos (print/debugPrint/dump/NSLog/os_log/Logger) en codigo de la app; no se puede registrar nada" "${l[@]}"
  fi
}

# b) Fines de linea: ningun fichero versionado con CRLF en el indice.
check_crlf() {
  local res
  local todos tolerados fallos_l
  # safe.directory: en el contenedor de CI el repo pertenece a otro usuario.
  local eol
  eol=$(git -c safe.directory="$PWD" ls-files --eol) || { fallo "No se pudo ejecutar git ls-files --eol" "(¿no es un repositorio git?)"; return 0; }
  todos=$(grep -E '^i/crlf' <<<"$eol" | cut -f2 || true)
  # TODO(gates): CRLF heredado en un informe de docs (caso real, no tocado aqui):
  # normalizar a LF y quitar esta excepcion.
  tolerados=$(grep -xF 'docs/traspaso/informes/integracion2a-arreglos2-informe.md' <<<"$todos" || true)
  fallos_l=$(grep -vxF 'docs/traspaso/informes/integracion2a-arreglos2-informe.md' <<<"$todos" || true)
  if [ -n "$tolerados" ]; then
    mapfile -t l <<<"$tolerados"
    aviso "CRLF heredado tolerado temporalmente (TODO(gates): pasar a LF)" "${l[@]}"
  fi
  if [ -n "$fallos_l" ]; then
    mapfile -t l <<<"$fallos_l"
    fallo "Ficheros versionados con fin de linea CRLF en el indice (deben ser LF)" "${l[@]}"
  fi
}

# c) Portapapeles: UIPasteboard solo en App/MoveMoney/Pasteboard.swift.
check_portapapeles() {
  [ -d App ] || return 0
  local res
  if [ -f App/MoveMoney/Pasteboard.swift ]; then
    res=$(grep -rnI --include='*.swift' 'UIPasteboard' App \
      | grep -v '^App/MoveMoney/Pasteboard\.swift:' || true)
  else
    res=$(grep -rnI --include='*.swift' 'UIPasteboard' App || true)
  fi
  if [ -n "$res" ]; then
    mapfile -t l <<<"$res"
    fallo "UIPasteboard solo puede usarse en App/MoveMoney/Pasteboard.swift" "${l[@]}"
  fi
}

# d) CI: sin runners macos-15-intel.
check_intel() {
  [ -d .github/workflows ] || return 0
  local res
  res=$(grep -nE 'runs-on:[[:space:]]*["'"'"']?macos-15-intel|default:[[:space:]]*"macos-15-intel"' \
    .github/workflows/*.yml /dev/null | cut -d: -f1,2 || true)
  if [ -n "$res" ]; then
    mapfile -t l <<<"$res"
    fallo "Flujos de CI que usan macos-15-intel (prohibido; usar el runner de Namespace)" "${l[@]}"
  fi
}

# e) Higiene del repositorio publico: sin rutas de Windows ni correos.
check_higiene() {
  local dirs=() d res
  while IFS= read -r d; do dirs+=("$d"); done < <(existentes "${HIGIENE_RUTAS[@]}")
  [ ${#dirs[@]} -gt 0 ] || return 0
  res=$(grep -rnIE --exclude=check_gates.sh 'C:\\Users|C:/Users' "${dirs[@]}" \
    | sed -E 's/^([^:]+:[0-9]+):.*/\1 (ruta de Windows)/' || true)
  if [ -n "$res" ]; then
    mapfile -t l <<<"$res"
    fallo "Rutas de Windows en el repositorio publico" "${l[@]}"
  fi
  res=$(grep -rnIoE --exclude=check_gates.sh \
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' "${dirs[@]}" \
    | grep -vE '@users\.noreply\.github\.com$|@(example\.com|example\.org)$' \
    | grep -vE '@[0-9]+x\.(png|jpg|jpeg|webp|pdf|svg|heic)$' \
    | sed -E 's/^([^:]+:[0-9]+):.*/\1 (direccion de correo)/' || true)
  if [ -n "$res" ]; then
    mapfile -t l <<<"$res"
    fallo "Direcciones de correo en el repositorio publico (solo noreply de GitHub y example.com/org)" "${l[@]}"
  fi
}

# f) DemoMode solo dentro de #if DEBUG (salvo en App/DemoMode.swift).
# st[n]: 1 = rama activa es DEBUG, 0 = rama que no es DEBUG, 2 = "#if !DEBUG" (su #else es DEBUG).
AWK_DEMOMODE='
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
  {
    t = trim($0)
    if (t ~ /^#if([ \t]|$)/) {
      n++
      if (t ~ /^#if[ \t]+DEBUG$/) st[n] = 1
      else if (t ~ /^#if[ \t]+!DEBUG$/) st[n] = 2
      else st[n] = 0
    } else if (t ~ /^#(else|elseif)([ \t]|$)/) {
      if (n > 0) {
        if (st[n] == 1) st[n] = 0
        else if (st[n] == 2 && t ~ /^#else/) st[n] = 1
      }
    } else if (t ~ /^#endif/) {
      if (n > 0) n--
    }
    if (t ~ /^\/\//) next
    if ($0 ~ /DemoMode/) {
      dentro = 0
      for (i = 1; i <= n; i++) if (st[i] == 1) dentro = 1
      if (!dentro) print FILENAME ":" FNR
    }
  }'

check_demomode() {
  [ -d App ] || return 0
  local f res="" r
  while IFS= read -r f; do
    [ "$f" = "App/DemoMode.swift" ] && continue
    grep -qI 'DemoMode' "$f" || continue
    r=$(awk "$AWK_DEMOMODE" "$f")
    if [ -n "$r" ]; then res+="$r"$'\n'; fi
  done < <(find App -name '*.swift' | LC_ALL=C sort)
  if [ -n "$res" ]; then
    mapfile -t l <<<"${res%$'\n'}"
    fallo "DemoMode mencionado fuera de un bloque #if DEBUG ... #endif" "${l[@]}"
  fi
  if [ -f App/DemoMode.swift ]; then
    local primera
    primera=$(grep -m1 -E '^[[:space:]]*#' App/DemoMode.swift | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' || true)
    if [ "$primera" != "#if DEBUG" ]; then
      fallo "App/DemoMode.swift debe empezar (primera directiva) por #if DEBUG" "App/DemoMode.swift:1"
    fi
  fi
}

resumen() {
  if [ "$FALLOS" -eq 0 ]; then
    echo "Comprobaciones: OK"
    if [ "$AVISOS" -gt 0 ]; then echo "(avisos: $AVISOS)"; fi
    return 0
  fi
  echo "Comprobaciones: $FALLOS fallo(s)"
  return 1
}

ejecutar_todo() {
  check_registros
  check_crlf
  check_portapapeles
  check_intel
  check_higiene
  check_demomode
}

# --self-test: cada regla debe detectar su caso en un directorio temporal fuera del repo.
self_test() {
  local script tmp ok=0 bad=0 o
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "cd /; rm -rf '$tmp'" EXIT
  esperar() { # nombre, salida, patron, [1=debe aparecer | 0=no debe aparecer]
    local quiere="${4:-1}" hay=0
    if grep -qE "$3" <<<"$2"; then hay=1; fi
    if [ "$hay" = "$quiere" ]; then echo "  ok: $1"; ok=$((ok+1)); else echo "  MAL: $1"; bad=$((bad+1)); fi
  }
  correr() { (cd "$tmp" && MODO_AVISO_CRLF=0 bash "$script" 2>&1) || true; }

  cd "$tmp"
  git init -q .
  mkdir -p App/MoveMoney App/Views Core/Sources .github/workflows
  printf 'let a = 1\nprint("x")\n// print("ok")\nNSLog("y")\nlet l = Logger(subsystem: "a")\n' > App/Log.swift
  printf 'import UIKit\nUIPasteboard.general.string = "x"\n' > App/Views/Clip.swift
  printf 'jobs:\n  a:\n    runs-on: macos-15-intel\n' > .github/workflows/mala.yml
  printf 'default: "macos-15-intel"\n' > .github/workflows/mala2.yml
  printf 'let p = "C:\\Users\\alguien"\nlet q = "C:/Users/otro"\n// yo@gmail.com\n' > Core/Sources/Ruta.swift
  printf 'let x = DemoMode.on\n#if DEBUG\nlet y = DemoMode.on\n#else\nlet z = DemoMode.on\n#endif\n#if DEBUG\n#if os(iOS)\nlet w = DemoMode.on\n#endif\nlet v = DemoMode.on\n#endif\n' > App/Views/Demo.swift
  printf 'import Foundation\n#if os(iOS)\n#endif\n' > App/DemoMode.swift
  printf 'a\r\nb\r\n' > crlf.txt
  git -c core.autocrlf=false -c core.safecrlf=false add -A >/dev/null 2>&1
  o=$(correr)
  esperar "registros: print" "$o" 'App/Log\.swift:2:'
  esperar "registros: NSLog" "$o" 'App/Log\.swift:4:'
  esperar "registros: Logger" "$o" 'App/Log\.swift:5:'
  esperar "registros: comentario ignorado" "$o" 'App/Log\.swift:3$' 0
  esperar "crlf" "$o" 'crlf\.txt'
  esperar "portapapeles (sin Pasteboard.swift)" "$o" 'App/Views/Clip\.swift:2:'
  esperar "intel runs-on" "$o" 'mala\.yml:3$'
  esperar "intel default" "$o" 'mala2\.yml:1$'
  esperar "ruta Windows con barra invertida" "$o" 'Ruta\.swift:1 '
  esperar "ruta Windows con barra normal" "$o" 'Ruta\.swift:2 '
  esperar "correo" "$o" 'Ruta\.swift:3 '
  esperar "DemoMode fuera de DEBUG" "$o" 'App/Views/Demo\.swift:1$'
  esperar "DemoMode en #else de DEBUG" "$o" 'App/Views/Demo\.swift:5$'
  esperar "DemoMode en DEBUG permitido (3)" "$o" 'App/Views/Demo\.swift:3$' 0
  esperar "DemoMode anidado en DEBUG permitido (9)" "$o" 'App/Views/Demo\.swift:9$' 0
  esperar "DemoMode tras #endif anidado permitido (11)" "$o" 'App/Views/Demo\.swift:11$' 0
  esperar "DemoMode.swift sin #if DEBUG primero" "$o" 'App/DemoMode\.swift:1$'
  esperar "resumen con fallos" "$o" 'Comprobaciones: [0-9]+ fallo'

  printf 'UIPasteboard.general\n' > App/MoveMoney/Pasteboard.swift
  o=$(correr)
  esperar "portapapeles permitido en Pasteboard.swift" "$o" 'Pasteboard\.swift:1:' 0
  esperar "portapapeles prohibido fuera de Pasteboard.swift" "$o" 'Clip\.swift:2:'

  # Caso limpio: sin falsos positivos.
  rm -r App Core .github crlf.txt
  mkdir -p App Core/Sources .github/workflows
  printf '#if DEBUG\nenum DemoMode {}\n#endif\n' > App/DemoMode.swift
  printf '#if DEBUG\nlet a = DemoMode.on\n#endif\nlet i = "icon@2x.png"\nlet c = "a@example.com b@users.noreply.github.com"\nlet r = footprint(3)\n' > App/Ok.swift
  printf 'runs-on: namespace-profile-onyx\n# NO usar macos-15-intel\n' > .github/workflows/ok.yml
  git -c core.autocrlf=false add -A >/dev/null 2>&1
  o=$(correr)
  esperar "limpio: OK" "$o" '^Comprobaciones: OK'
  if ! grep -qE '^Comprobaciones: OK' <<<"$o"; then echo "$o"; fi

  echo "Self-test: $ok correctos, $bad fallidos"
  [ "$bad" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ ! -e .git ]; then echo "Ejecutar desde la raiz del repo"; exit 2; fi
  ejecutar_todo
  resumen
}

main "$@"
