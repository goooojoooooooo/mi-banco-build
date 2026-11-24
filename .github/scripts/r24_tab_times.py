#!/usr/bin/env python3
"""R31: imprime las cifras de «Cambio de pestaña con un solo toque» que dejó la prueba en el xcresult.

El log de xcodebuild no trae ni las actividades ni los fallos esperados, pero el xcresult sí. Mejor esfuerzo: nunca falla.
Uso: r24_tab_times.py <ruta.xcresult>
"""
import json
import subprocess
import sys

KEY = "Cambio de pestaña con un solo toque"
TEST = "testTabSwitchSingleTapStrict"


def run(args):
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", *args],
                         capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        return None, out.stderr.strip()[:300]
    try:
        return json.loads(out.stdout), ""
    except ValueError:
        return None, "salida que no es JSON"


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for value in node.values():
            yield from strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from strings(value)


def find_ids(node):
    if isinstance(node, dict):
        if str(node.get("name", "")).startswith(TEST) and node.get("nodeIdentifier"):
            yield node["nodeIdentifier"]
        for value in node.values():
            yield from find_ids(value)
    elif isinstance(node, list):
        for value in node:
            yield from find_ids(value)


def main():
    path = sys.argv[1]
    tests, error = run(["tests", "--path", path])
    if tests is None:
        print("R24: no se pudo leer el xcresult (" + error + ")")
        return
    ids = sorted(set(find_ids(tests)))
    if not ids:
        print("R24: la prueba " + TEST + " no está en el xcresult")
        return
    found = set()
    for test_id in ids:
        for sub in ("test-details", "activities"):
            data, error = run([sub, "--test-id", test_id, "--path", path])
            if data is None:
                print("R24: " + sub + " no disponible (" + error + ")")
                continue
            found.update(s for s in strings(data) if KEY in s)
    found.update(s for s in strings(tests) if KEY in s)
    if not found:
        print("R24: el xcresult no trae el mensaje «" + KEY + "»")
    for line in sorted(found):
        print("R24: " + line)


try:
    main()
except Exception as exc:  # mejor esfuerzo: el resumen no debe romper la ejecución
    print("R24: error al leer el xcresult (" + type(exc).__name__ + ")")
