#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "scripts/apply_gif2ani_360_animated_gallery_cards.py"
MODERN = ROOT / "gif2aniprefs/G2ModernGallery.inc"

spec = importlib.util.spec_from_file_location("gif2ani_360_patch", PATCH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load Gif2Ani 3.6.0 patch module")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.patch_modern_gallery()
text = MODERN.read_text()
marker = "visible-card-bundled-animation-v360"
if marker not in text:
    anchor = "@interface G2ModernThemeCell : UITableViewCell"
    if anchor not in text:
        raise RuntimeError("modern cell interface anchor missing")
    declaration = '__attribute__((used)) static const char G2AnimatedCardPreviewMarker[] = "visible-card-bundled-animation-v360";\n\n'
    text = text.replace(anchor, declaration + anchor, 1)
    MODERN.write_text(text)

module.patch_version()
module.verify()
print("gif2ani_360_marker_insertion=success")
