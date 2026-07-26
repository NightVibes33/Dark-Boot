#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

from PIL import Image, ImageDraw

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


def forced_bounded_pulse(media_root: Path, destination: Path) -> dict:
    files = module.image_files(media_root)
    if not files:
        raise RuntimeError(f"no fallback artwork in {media_root}")
    source_image = None
    for path in files:
        try:
            with Image.open(path) as image:
                try:
                    image.seek(0)
                except EOFError:
                    pass
                source_image = image.convert("RGBA").copy()
            break
        except Exception:
            continue
    if source_image is None:
        raise RuntimeError(f"no decodable fallback artwork in {media_root}")

    scales = [0.78, 0.83, 0.88, 0.92, 0.88, 0.83, 0.78, 0.83]
    ring_levels = [32, 48, 70, 92, 70, 48, 32, 48]
    frames = []
    for scale, level in zip(scales, ring_levels):
        canvas = Image.new("RGBA", (module.CANVAS, module.CANVAS), (0, 0, 0, 255))
        draw = ImageDraw.Draw(canvas, "RGBA")
        inset = 13 + int((1.0 - scale) * 18)
        draw.ellipse((inset, inset, module.CANVAS - inset - 1, module.CANVAS - inset - 1), outline=(120, 160, 210, level), width=2)

        maximum = max(1, int((module.CANVAS - 18) * scale))
        width = max(1, source_image.width)
        height = max(1, source_image.height)
        ratio = min(maximum / width, maximum / height)
        target = (max(1, round(width * ratio)), max(1, round(height * ratio)))
        artwork = source_image.resize(target, Image.Resampling.LANCZOS)
        x = (module.CANVAS - artwork.width) // 2
        y = (module.CANVAS - artwork.height) // 2
        canvas.alpha_composite(artwork, (x, y))
        frames.append(canvas.convert("P", palette=Image.Palette.ADAPTIVE, colors=64))

    destination.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        destination,
        format="GIF",
        save_all=True,
        append_images=frames[1:],
        duration=[90] * len(frames),
        loop=0,
        optimize=True,
        disposal=2,
    )
    with Image.open(destination) as check:
        count = getattr(check, "n_frames", 1)
    if count < 2:
        raise RuntimeError(f"forced preview still collapsed: {destination}")
    if destination.stat().st_size > module.MAX_OUTPUT_BYTES:
        raise RuntimeError(f"forced preview exceeds size limit: {destination.stat().st_size}")
    return {
        "frames": count,
        "bytes": destination.stat().st_size,
        "sha256": module.sha256(destination),
    }


original_build_animation = module.build_animation


def build_animation(media_root: Path, destination: Path) -> dict:
    try:
        return original_build_animation(media_root, destination)
    except RuntimeError as error:
        if "preview collapsed to 1 frame" not in str(error):
            raise
        metadata = forced_bounded_pulse(media_root, destination)
        print(f"animated_preview_fallback={destination.stem}|reason=identical-static-frames|frames={metadata['frames']}", flush=True)
        return metadata


module.fit_frame = fit_frame
module.build_animation = build_animation
module.main()
