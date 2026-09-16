#!/usr/bin/env python3
"""Build the emoji keyboard's data: Keyboard/Resources/emoji-index.json + emoji-images.dat.

Sources (fetched into scripts/emoji-src/, not committed):
  * Microsoft Fluent Emoji (MIT), 3D PNGs and metadata:
      git clone --depth 1 --filter=blob:none --sparse https://github.com/microsoft/fluentui-emoji
      git -C fluentui-emoji sparse-checkout set --no-cone '/assets/**/3D/*.png' '/assets/**/metadata.json' '/LICENSE'
  * https://unicode.org/Public/emoji/16.0/emoji-test.txt — the canonical order (which is
    Apple's), fully-qualified strings, and skin-tone variants.

Every fully-qualified Emoji 16.0 emoji is listed in Unicode order under Apple's eight
categories. Its keyboard image is the Fluent 3D art when Fluent has it, downscaled to
WebP; otherwise (country flags, mostly) the system draws it. What gets typed is always the
standard Unicode string.

emoji-images.dat is the WebP files end to end; the index holds [offset, length] pairs.

Needs ImageMagick with WebP (`magick`). Usage: python3 scripts/build-emoji.py
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "emoji-src"
FLUENT = SRC / "fluentui-emoji"
CACHE = SRC / "webp-cache"
OUT_INDEX = ROOT / "Keyboard" / "Resources" / "emoji-index.json"
OUT_IMAGES = ROOT / "Keyboard" / "Resources" / "emoji-images.dat"

PIXELS = 96          # a keyboard cell is ~32pt, so this is 3x
QUALITY = "82"

CATEGORIES = [
    ("Smileys & People", {"Smileys & Emotion", "People & Body"}),
    ("Animals & Nature", {"Animals & Nature"}),
    ("Food & Drink", {"Food & Drink"}),
    ("Activity", {"Activities"}),
    ("Travel & Places", {"Travel & Places"}),
    ("Objects", {"Objects"}),
    ("Symbols", {"Symbols"}),
    ("Flags", {"Flags"}),
]
TONES = ["light", "medium-light", "medium", "medium-dark", "dark"]
TONE_MODIFIERS = {"1f3fb", "1f3fc", "1f3fd", "1f3fe", "1f3ff"}
FLUENT_TONE_DIRS = ["Light", "Medium-Light", "Medium", "Medium-Dark", "Dark"]
LINE = re.compile(r"^([0-9A-F ]+?)\s*; fully-qualified\s*# (\S+) E[\d.]+ (.+)$")


def key(codepoints: list[str]) -> str:
    return " ".join(c.lower() for c in codepoints if c.lower() != "fe0f")


def load_fluent() -> dict[str, tuple[Path, dict]]:
    by_key = {}
    for meta_path in (FLUENT / "assets").glob("*/metadata.json"):
        meta = json.loads(meta_path.read_text())
        by_key[key(meta["unicode"].split())] = (meta_path.parent, meta)
    return by_key


def png_for(folder: Path, tone: int | None) -> Path | None:
    """tone None = the default (yellow) art; 0–4 = light…dark."""
    if tone is None:
        candidates = [folder / "3D", folder / "Default" / "3D"]
    else:
        candidates = [folder / FLUENT_TONE_DIRS[tone] / "3D"]
    for d in candidates:
        pngs = sorted(d.glob("*.png")) if d.is_dir() else []
        if pngs:
            return pngs[0]
    return None


def to_webp(png: Path) -> Path:
    digest = hashlib.sha1(f"{png}|{PIXELS}|{QUALITY}".encode()).hexdigest()
    out = CACHE / f"{digest}.webp"
    if not out.exists():
        tmp = out.with_suffix(".tmp.webp")
        subprocess.run(["magick", str(png), "-resize", f"{PIXELS}x{PIXELS}", "-quality", QUALITY,
                        "-define", "webp:alpha-quality=90", "-define", "webp:method=6", str(tmp)],
                       check=True)
        tmp.rename(out)
    return out


def main() -> None:
    if not shutil.which("magick"):
        sys.exit("ImageMagick (magick) is required")
    fluent = load_fluent()
    group = None
    bases: list[dict] = []
    by_name: dict[str, dict] = {}
    for line in (SRC / "emoji-test-16.0.txt").read_text().splitlines():
        if line.startswith("# group: "):
            group = line[len("# group: "):]
            continue
        m = LINE.match(line)
        if not m or group == "Component":
            continue
        cps = m.group(1).split()
        glyph, name = m.group(2), m.group(3)
        tone_parts = [c for c in cps if c.lower() in TONE_MODIFIERS]
        if tone_parts:
            # "man: light skin tone, red hair" is a tone of "man: red hair".
            head, _, desc = name.partition(": ")
            parts = desc.split(", ")
            tones = {p.removesuffix(" skin tone") for p in parts if p.endswith(" skin tone")}
            rest = [p for p in parts if not p.endswith(" skin tone")]
            base = by_name.get(head + (": " + ", ".join(rest) if rest else ""))
            # Only uniform tones; Fluent draws no mixed-tone pairs.
            if base is not None and len(tones) == 1 and (tone := tones.pop()) in TONES:
                base["tones"][TONES.index(tone)] = glyph
            continue
        category = next((i for i, (_, groups) in enumerate(CATEGORIES) if group in groups), None)
        if category is None:
            continue
        entry = {"c": category, "s": glyph, "n": name, "key": key(cps), "tones": [None] * 5}
        bases.append(entry)
        by_name[name] = entry

    # Unicode puts Travel before Activities; Apple doesn't. Stable, so order within a
    # category stays Unicode's.
    bases.sort(key=lambda e: e["c"])

    CACHE.mkdir(parents=True, exist_ok=True)
    jobs: dict[Path, None] = {}
    for e in bases:
        hit = fluent.get(e["key"])
        e["folder"] = hit[0] if hit else None
        e["meta"] = hit[1] if hit else None
        if e["folder"]:
            for tone in [None, 0, 1, 2, 3, 4]:
                if tone is not None and e["tones"][tone] is None:
                    continue
                png = png_for(e["folder"], tone)
                if png:
                    jobs[png] = None
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        webps = dict(zip(jobs, pool.map(to_webp, jobs)))

    blob = bytearray()
    spans: dict[Path, list[int]] = {}

    def image(png: Path | None) -> list[int] | None:
        if png is None:
            return None
        if png not in spans:
            data = webps[png].read_bytes()
            spans[png] = [len(blob), len(data)]
            blob.extend(data)
        return spans[png]

    out = []
    fluent_count = 0
    for e in bases:
        meta = e["meta"] or {}
        words = {e["n"].lower(), *(k.lower() for k in meta.get("keywords", []))}
        if meta.get("cldr"):
            words.add(meta["cldr"].lower())
        item = {"c": e["c"], "s": e["s"], "n": e["n"],
                "k": " ".join(sorted(words - {e["n"].lower()}))}
        img = image(png_for(e["folder"], None)) if e["folder"] else None
        if img:
            item["i"] = img
            fluent_count += 1
        if all(e["tones"]):
            tones = []
            for t, glyph in enumerate(e["tones"]):
                tone = {"s": glyph}
                timg = image(png_for(e["folder"], t)) if e["folder"] else None
                if timg:
                    tone["i"] = timg
                tones.append(tone)
            item["t"] = tones
        out.append(item)

    OUT_INDEX.parent.mkdir(parents=True, exist_ok=True)
    OUT_INDEX.write_text(json.dumps({"version": 1, "pixels": PIXELS,
                                     "categories": [c for c, _ in CATEGORIES],
                                     "emoji": out}, ensure_ascii=False, separators=(",", ":")))
    OUT_IMAGES.write_bytes(bytes(blob))
    per_cat = [sum(1 for i in out if i["c"] == c) for c in range(len(CATEGORIES))]
    print(f"{len(out)} emoji ({fluent_count} with Fluent art), {len(spans)} images, "
          f"{len(blob) / 1e6:.1f} MB images, {OUT_INDEX.stat().st_size / 1e3:.0f} KB index; "
          f"per category {per_cat}", file=sys.stderr)
    shutil.copy(FLUENT / "LICENSE", OUT_INDEX.parent / "FLUENT-EMOJI-LICENSE.txt")


if __name__ == "__main__":
    main()
