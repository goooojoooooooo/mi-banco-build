"""Baja una vez los logos que van dentro de Mi Banco (sin red en tiempo de ejecución para estos).

Lee los dominios del directorio de comercios (Core/Sources/MiBancoCore/MerchantDirectory.swift) y
añade los tres bancos. Para cada dominio prueba, por orden, y se queda con la mejor imagen (la más grande,
casi cuadrada y que no sea un genérico):
  a. iTunes Search API (pública, sin clave): el icono de la app de la marca (artworkUrl512), cuadrado y de alta
     resolución. Se elige el resultado cuyo nombre o vendedor pertenece claramente a la marca; la tabla
     OVERRIDES fija un término de búsqueda o un trackId cuando la coincidencia es ambigua.
  b. La propia web: /apple-touch-icon.png (y -precomposed), o el icono más grande declarado en el HTML
     (<link rel="apple-touch-icon"|"icon" sizes=...>) o en el manifest web.
  c. Servicios de favicons (Google, gstatic, DuckDuckGo), último recurso.
Si una fuente da >= 180 px no se siguen probando las demás. Se rechaza todo lo de menos de 120 px y los
placeholders (huella del globo por defecto). Guarda PNG en App/Resources/Logos/<dominio>.png: 192x192 como
máximo (nunca se amplía por encima de la fuente), con transparencia solo si el original la tiene y no es un
icono a sangre con las esquinas recortadas (esos se aplanan sobre blanco). manifest.json: fuente y tamaño por dominio.

Solo se envía el nombre de la marca o el dominio. Uso: python -I tools/fetch_logos.py [dominio ...]
(con dominios solo se rehacen esos; sin argumentos, todos).
"""
from __future__ import annotations

import hashlib
import io
import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = ROOT / "Core" / "Sources" / "MiBancoCore" / "MerchantDirectory.swift"
OUT = ROOT / "App" / "Resources" / "Logos"
BANKS = ["revolut.com", "imagin.com", "traderepublic.com"]
TARGET = 192
GOOD_SIDE = 180      # con esto se deja de buscar
MIN_SIDE = 120       # por debajo se rechaza
UA = "Mozilla/5.0 (logo-fetch script)"

# Por dominio: "term" = búsqueda en iTunes, "id" = trackId fijo, "brand" = palabras que deben aparecer en el nombre
# de la app o del vendedor, "games" = admite juegos, "skip_itunes" = la marca no tiene una app propia fiable.
OVERRIDES: dict[str, dict] = {
    "glovoapp.com": {"id": 951812684},      # "Glovo: Comida a domicilio" (el slug "glovoapp" no casa con el nombre)
    "yelmocines.es": {"id": 1498225311},    # Cine Yelmo
    "youtube.com": {"id": 544007664},       # YouTube (la búsqueda por "youtube" también da Music, Kids...)
    "microsoft.com": {"id": 541164041},     # Microsoft 365 / Copilot en vez de Outlook
    "100montaditos.com": {"term": "100 montaditos", "brand": "montaditos"},
    "hipercor.es": {"term": "hipercor", "brand": "hipercor"},
    "hm.com": {"term": "H&M", "brand": "h m"},
    "iberdrola.es": {"term": "iberdrola clientes", "brand": "iberdrola"},
    "leroymerlin.es": {"term": "leroy merlin", "brand": "leroy merlin"},
    "stradivarius.com": {"term": "stradivarius", "brand": "stradivarius"},
    "vodafone.es": {"term": "mi vodafone", "brand": "vodafone"},
    "yoigo.com": {"term": "yoigo", "brand": "yoigo"},
}


def domains_from_directory() -> list[str]:
    text = DIRECTORY.read_text(encoding="utf-8")
    found = re.findall(r'^\s*\("([a-z0-9.-]+\.[a-z]{2,})", \[', text, flags=re.M)
    return sorted(set(found))


def get(url: str, limit: int = 4_000_000) -> bytes | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            if r.status != 200:
                return None
            return r.read(limit)
    except (urllib.error.URLError, TimeoutError, ConnectionError, ValueError):
        return None


def norm(text: str) -> list[str]:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.findall(r"[a-z0-9]+", text)


def slug(domain: str) -> str:
    return domain.split(".")[0]


# --- a. iTunes ---------------------------------------------------------------------------------------------

def itunes_candidates(domain: str) -> list[tuple[str, str]]:
    """[(descripción, url del icono 512)] de las apps que claramente son de la marca."""
    ov = OVERRIDES.get(domain, {})
    if ov.get("skip_itunes"):
        return []
    if "id" in ov:
        url = f"https://itunes.apple.com/lookup?id={ov['id']}&country=es"
        data = get(url)
        results = json.loads(data)["results"] if data else []
        return [(f"itunes:{r['trackId']}", r["artworkUrl512"]) for r in results if r.get("artworkUrl512")]
    term = ov.get("term", slug(domain))
    brand = norm(ov.get("brand", term))
    url = ("https://itunes.apple.com/search?term=" + urllib.parse.quote(term)
           + "&country=es&entity=software&limit=8")
    data = get(url)
    if not data:
        return []
    try:
        results = json.loads(data)["results"]
    except (ValueError, KeyError):
        return []
    out = []
    for r in results:
        name = norm(r.get("trackName", ""))
        seller = norm(r.get("sellerName", ""))
        if r.get("primaryGenreName") == "Games" and not ov.get("games"):
            continue
        # Nombre: todas las palabras de la marca como palabras sueltas, o pegadas ("glovoapp" / "glovo").
        joined = "".join(name)
        hit_name = all(w in name for w in brand) or (len(brand) == 1 and joined.startswith(brand[0]))
        hit_seller = all(w in seller for w in brand)
        if (hit_name or hit_seller) and r.get("artworkUrl512"):
            out.append((f"itunes:{r['trackId']}:{r.get('trackName', '')[:30]}", r["artworkUrl512"]))
    return out[:2]


# --- b. la propia web --------------------------------------------------------------------------------------

def site_candidates(domain: str) -> list[tuple[str, str]]:
    cands: list[tuple[str, str]] = []
    for host in (f"www.{domain}", domain):
        for path in ("/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"):
            cands.append(("site:touch", f"https://{host}{path}"))
        data = get(f"https://{host}/", limit=600_000)
        if not data:
            continue
        html = data.decode("utf-8", "ignore")
        found = []
        for tag in re.findall(r"<link\b[^>]*>", html, flags=re.I):
            rel = re.search(r'rel=["\']([^"\']+)["\']', tag, flags=re.I)
            href = re.search(r'href=["\']([^"\']+)["\']', tag, flags=re.I)
            if not rel or not href or "icon" not in rel.group(1).lower() or "mask" in rel.group(1).lower():
                continue
            sizes = re.search(r'sizes=["\'](\d+)x\d+', tag, flags=re.I)
            side = int(sizes.group(1)) if sizes else (180 if "apple" in rel.group(1).lower() else 0)
            found.append((side, urllib.parse.urljoin(f"https://{host}/", href.group(1))))
        for side, url in sorted(found, reverse=True)[:3]:
            cands.append(("site:link", url))
        break
    return cands


# --- c. favicons --------------------------------------------------------------------------------------------

def favicon_candidates(domain: str) -> list[tuple[str, str]]:
    return [
        ("google", f"https://www.google.com/s2/favicons?domain={domain}&sz=256"),
        ("gstatic", "https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL"
                    f"&url=https://{domain}&size=256"),
        ("duckduckgo", f"https://icons.duckduckgo.com/ip3/{domain}.ico"),
    ]


# --- imágenes -----------------------------------------------------------------------------------------------

def decode(data: bytes) -> Image.Image | None:
    try:
        img = Image.open(io.BytesIO(data))
        if img.format == "ICO":
            sizes = sorted(img.ico.sizes(), key=lambda s: s[0] * s[1])
            if sizes:
                img.size = sizes[-1]
        img.load()
        return img.convert("RGBA")
    except Exception:  # noqa: BLE001 - cualquier imagen rota se descarta
        return None


def fingerprint(img: Image.Image) -> str:
    return hashlib.sha1(img.resize((16, 16), Image.Resampling.LANCZOS).tobytes()).hexdigest()


def placeholder_prints() -> set[str]:
    prints = set()
    for fake in ["no-existe-mibanco-xq7.invalid", "zzqqxx-mibanco-404.com"]:
        for _, url in favicon_candidates(fake):
            data = get(url)
            img = decode(data) if data else None
            if img is not None:
                prints.add(fingerprint(img))
    return prints


def usable(img: Image.Image | None, bad: set[str]) -> bool:
    if img is None:
        return False
    w, h = img.size
    if min(w, h) < MIN_SIDE or min(w, h) / max(w, h) < 0.8:
        return False
    if fingerprint(img) in bad:
        return False
    extrema = img.getextrema()
    flat = all(lo == hi for lo, hi in extrema)
    return extrema[3][1] > 0 and not flat


def finish(img: Image.Image) -> Image.Image:
    """Cuadrado, como mucho 192 px (sin ampliar) y sin transparencia solo en iconos a sangre con esquinas cortadas."""
    w, h = img.size
    side = max(w, h)
    if w != h:
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(img, ((side - w) // 2, (side - h) // 2))
        img = canvas
    alpha = img.getchannel("A")
    corners = [alpha.getpixel(p) for p in [(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)]]
    if min(corners) < 250:
        opaque = sum(1 for a in alpha.tobytes() if a > 200) / (side * side)
        if opaque >= 0.6:  # icono redondeado a sangre: sobre la baldosa clara se ve mejor con las esquinas blancas
            white = Image.new("RGBA", img.size, (255, 255, 255, 255))
            white.alpha_composite(img)
            img = white
    else:
        img = img.convert("RGB").convert("RGBA") if min(alpha.getextrema()) == 255 else img
    if side > TARGET:
        img = img.resize((TARGET, TARGET), Image.Resampling.LANCZOS)
    if min(img.getchannel("A").getextrema()) == 255:
        img = img.convert("RGB")
    return img


def best_for(domain: str, bad: set[str]) -> tuple[str, Image.Image] | None:
    best: tuple[str, Image.Image] | None = None

    def consider(source: str, url: str) -> None:
        nonlocal best
        data = get(url)
        img = decode(data) if data else None
        if usable(img, bad) and (best is None or min(img.size) > min(best[1].size)):
            best = (source, img)

    for stage in (itunes_candidates, site_candidates, favicon_candidates):
        for source, url in stage(domain):
            consider(source, url)
            if best is not None and min(best[1].size) >= GOOD_SIDE:
                return best
            time.sleep(0.1)
        if best is not None and min(best[1].size) >= GOOD_SIDE:
            break
    return best


def main(argv: list[str]) -> int:
    all_domains = domains_from_directory() + BANKS
    wanted = argv or all_domains
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    manifest: dict[str, dict] = {}
    if argv and manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))["logos"]
    bad = placeholder_prints()
    failed: list[str] = []
    for domain in wanted:
        chosen = best_for(domain, bad)
        if chosen is None:
            failed.append(domain)
            manifest.pop(domain, None)
            (OUT / f"{domain}.png").unlink(missing_ok=True)
            print(f"sin logo  {domain}")
            continue
        source, img = chosen
        final = finish(img)
        final.save(OUT / f"{domain}.png", optimize=True)
        manifest[domain] = {"source": source, "original": list(img.size), "stored": list(final.size),
                            "lowres": min(img.size) < GOOD_SIDE}
        print(f"ok {source:34} {img.size[0]}x{img.size[1]} -> {final.size[0]}  {domain}")
    if not argv:
        for stale in OUT.glob("*.png"):
            if stale.stem not in manifest:
                stale.unlink()
    failed_all = sorted(d for d in all_domains if d not in manifest)
    manifest = dict(sorted(manifest.items()))
    manifest_path.write_text(
        json.dumps({"logos": manifest, "failed": failed_all}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8", newline="\n")
    low = [d for d, m in manifest.items() if m["lowres"]]
    print(f"\n{len(manifest)} de {len(all_domains)} con logo ({len(low)} por debajo de {GOOD_SIDE} px: {', '.join(low)})")
    print(f"fallan: {', '.join(failed_all) or 'ninguno'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
