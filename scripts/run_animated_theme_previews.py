#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

from PIL import Image

MODULE_PATH = Path(__file__).with_name("build_animated_theme_previews.py")
spec = importlib.util.spec_from_file_location("gif2ani_animated_previews", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load animated preview generator")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fit_frame(image: Image.Image, scale: float = 1.0) -> Image.Image:
    source = image.convert("RGBA")
    maximum = max(1, int((module.CANVAS - 8) * scale))
    width = max(1, source.width)
    height = max(1, source.height)
    ratio = min(maximum / width, maximum / height)
    target = (max(1, round(width * ratio)), max(1, round(height * ratio)))
    source = source.resize(target, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (module.CANVAS, module.CANVAS), (0, 0, 0, 255))
    x = (module.CANVAS - source.width) // 2
    y = (module.CANVAS - source.height) // 2
    canvas.alpha_composite(source, (x, y))
    return canvas.convert("P", palette=Image.Palette.ADAPTIVE, colors=64)


module.fit_frame = fit_frame
module.main()
