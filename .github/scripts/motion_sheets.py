#!/usr/bin/env python3
"""Agrupa los fotogramas exportados del .xcresult en rafagas y comprueba que no falte nada (workflow motion-video).

Subcomandos:
  group   --attachments DIR --frames DIR --classes "A B"   copia los fotogramas a FRAMES/<rafaga>/fNNN.png y escribe FRAMES/groups.json
  verify  --frames DIR --sheets DIR                        cada rafaga tiene su hoja <rafaga>.png (y no sobra ninguna)
  selftest                                                 prueba la logica con manifiestos sinteticos (cada comprobacion tiene que poder fallar)

Los adjuntos se llaman «<rafaga>-NN_tTTT»: NN = indice desde 01 (dos cifras o mas), TTT = decimas de segundo desde el primer
fotograma. Cualquier fallo termina con codigo 1 y dice que rafaga o que clase fallo.
"""
import json
import os
import re
import shutil
import sys
import tempfile

NAME = re.compile(r"^(?P<burst>.+)-(?P<index>\d{2,})_t(?P<tenths>\d+)$")
SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f-]{36}$")  # Xcode anade «_<indice>_<UUID>» al nombre sugerido


class SheetError(Exception):
    pass


def human_stem(att):
    exported = att.get("exportedFileName")
    human = att.get("suggestedHumanReadableName") or exported or ""
    stem = human
    for ext in (".png", ".jpg", ".jpeg", ".heic"):
        if stem.lower().endswith(ext):
            stem = stem[: -len(ext)]
            break
    return SUFFIX.sub("", stem)


def test_classes(test):
    ident = str(test.get("testIdentifier") or test.get("testIdentifierURL") or "")
    return {seg for seg in re.split(r"[/.()]+", ident) if seg}


def collect(manifest, classes):
    """Devuelve ({rafaga: [(indice, fichero, decimas)]}, errores)."""
    groups, owners, errors = {}, {}, []
    seen = {c: False for c in classes}
    produced = {c: 0 for c in classes}
    for test in manifest:
        segs = test_classes(test)
        mine = [c for c in classes if c in segs]
        for c in mine:
            seen[c] = True
        for att in test.get("attachments", []):
            exported = att.get("exportedFileName")
            if not exported:
                continue
            m = NAME.match(human_stem(att))
            if not m:
                continue
            burst = m.group("burst")
            groups.setdefault(burst, []).append((int(m.group("index")), exported, int(m.group("tenths"))))
            owners.setdefault(burst, set()).update(mine)
            for c in mine:
                produced[c] += 1
    for c in classes:
        if not seen[c]:
            errors.append("La clase %s no aparece en el manifiesto del xcresult (no ejecuto pruebas)" % c)
        elif produced[c] == 0:
            errors.append("La clase %s ejecuto pruebas pero no dejo ninguna rafaga (ninguna hoja de contacto)" % c)
    for burst, items in sorted(groups.items()):
        indexes = sorted(i for i, _, _ in items)
        expected = list(range(1, len(indexes) + 1))
        if indexes != expected:
            dup = sorted({i for i in indexes if indexes.count(i) > 1})
            gaps = [i for i in range(1, max(indexes) + 1) if i not in indexes]
            errors.append("Rafaga %s incompleta: indices %s (duplicados %s, huecos %s)" % (burst, indexes, dup, gaps))
    if not groups:
        errors.append("El manifiesto no tiene adjuntos con nombre <rafaga>-NN_tTTT")
    return groups, errors


def group(attachments, frames, classes):
    manifest = json.load(open(os.path.join(attachments, "manifest.json"), encoding="utf-8"))
    groups, errors = collect(manifest, classes)
    if errors:
        raise SheetError("\n".join(errors))
    summary = {}
    for burst, items in sorted(groups.items()):
        items.sort()
        folder = os.path.join(frames, burst)
        os.makedirs(folder, exist_ok=True)
        times = []
        for n, (index, exported, tenths) in enumerate(items, start=1):
            shutil.copy(os.path.join(attachments, exported), os.path.join(folder, "f%03d.png" % n))
            times.append("%02d %.1f s" % (index, tenths / 10.0))
        open(os.path.join(folder, "times.txt"), "w", encoding="utf-8").write("\n".join(times) + "\n")
        summary[burst] = len(items)
        print(burst, len(items), "fotogramas; tiempos reales:", ", ".join(t.split()[1] for t in times))
    json.dump(summary, open(os.path.join(frames, "groups.json"), "w", encoding="utf-8"))
    return summary


def verify(frames, sheets):
    expected = set(json.load(open(os.path.join(frames, "groups.json"), encoding="utf-8")))
    have = {f[:-4] for f in os.listdir(sheets) if f.endswith(".png")}
    errors = ["Falta la hoja de la rafaga %s" % b for b in sorted(expected - have)]
    errors += ["Hoja sin rafaga: %s" % b for b in sorted(have - expected)]
    errors += ["Hoja vacia: %s" % b for b in sorted(expected & have) if os.path.getsize(os.path.join(sheets, b + ".png")) == 0]
    if errors:
        raise SheetError("\n".join(errors))
    print("Hojas correctas:", " ".join(sorted(have)))


def _manifest(tests):
    return [{"testIdentifier": ident, "attachments": [{"exportedFileName": "x%d" % k, "suggestedHumanReadableName": "%s_0_%s.png" % (name, "0" * 8 + "-0000-0000-0000-" + "0" * 12)} for k, name in enumerate(names)]} for ident, names in tests]


def selftest():
    def names(burst, n):
        return ["%s-%02d_t%03d" % (burst, i, i * 4) if i < 100 else "%s-%d_t%03d" % (burst, i, i * 4) for i in range(1, n + 1)]

    def errs(tests, classes):
        return collect(_manifest(tests), classes)[1]

    ok = [("MotionTourTests/testGalleryBurst()", names("gallery-burst", 16))]
    assert errs(ok, ["MotionTourTests"]) == [], "un caso bueno no debe fallar"
    gap = names("gallery-burst", 16)
    del gap[5]
    assert any("incompleta" in e and "gallery-burst" in e for e in errs([("MotionTourTests/testA()", gap)], ["MotionTourTests"])), "un hueco debe fallar"
    assert any("incompleta" in e and "gallery-burst" in e for e in errs([("MotionTourTests/testA()", names("gallery-burst", 4) + names("gallery-burst", 4))], ["MotionTourTests"])), "un duplicado debe fallar"
    two = [("MotionTourTests/testA()", names("gallery-burst", 3)), ("MotionTourTests/testB()", names("gallery-burst", 3))]
    assert any("incompleta" in e for e in errs(two, ["MotionTourTests"])), "el mismo nombre en dos pruebas debe fallar"
    assert any("MotionTourHomeTests" in e and "ninguna rafaga" in e for e in errs(ok + [("MotionTourHomeTests/testPlaceholder()", [])], ["MotionTourTests", "MotionTourHomeTests"])), "una clase sin rafagas debe fallar"
    assert any("MotionTourShellTests" in e for e in errs(ok, ["MotionTourTests", "MotionTourShellTests"])), "una clase ausente debe fallar"
    big, bad = collect(_manifest([("MotionTourTests/testA()", names("larga", 120))]), ["MotionTourTests"])
    assert bad == [] and len(big["larga"]) == 120, "los fotogramas 100+ no pueden perderse en silencio"
    tmp = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(tmp, "f", "a"))
        json.dump({"a": 2, "b": 2}, open(os.path.join(tmp, "f", "groups.json"), "w"))
        os.makedirs(os.path.join(tmp, "s"))
        open(os.path.join(tmp, "s", "a.png"), "wb").write(b"x")
        try:
            verify(os.path.join(tmp, "f"), os.path.join(tmp, "s"))
            raise AssertionError("una hoja que falta debe fallar")
        except SheetError:
            pass
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("selftest correcto: hueco, duplicado, nombre repetido, clase sin rafagas, clase ausente, 100+ y hoja que falta")


def main(argv):
    def opt(flag):
        return argv[argv.index(flag) + 1]

    try:
        if argv[0] == "selftest":
            selftest()
        elif argv[0] == "group":
            group(opt("--attachments"), opt("--frames"), opt("--classes").replace(",", " ").split())
        elif argv[0] == "verify":
            verify(opt("--frames"), opt("--sheets"))
        else:
            raise SheetError("subcomando desconocido: " + argv[0])
    except SheetError as e:
        print("ERROR:", e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
