#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageSequence, ImageStat

MODULE_PATH = Path(__file__).with_name("build_animated_theme_previews.py")
spec = importlib.util.spec_from_file_location("gif2ani_preview_base", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load animated preview generator")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

MAX_MEAN_COLOR_ERROR = 10.0
MAX_SINGLE_FRAME_ERROR = 18.0


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
    return canvas.convert("RGB")


def shared_palette_frames(frames: list[Image.Image]) -> list[Image.Image]:
    rgb = [frame.convert("RGB") for frame in frames]
    sheet = Image.new("RGB", (module.CANVAS, module.CANVAS * len(rgb)), (0, 0, 0))
    for index, frame in enumerate(rgb):
        sheet.paste(frame, (0, module.CANVAS * index))
    master = sheet.quantize(
        colors=256,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    palette_image = Image.new("P", (1, 1))
    palette = master.getpalette()
    if palette is None:
        raise RuntimeError("could not construct shared GIF palette")
    palette_image.putpalette(palette)
    return [
        frame.quantize(palette=palette_image, dither=Image.Dither.FLOYDSTEINBERG)
        for frame in rgb
    ]


def frame_error(reference: Image.Image, actual: Image.Image) -> float:
    difference = ImageChops.difference(reference.convert("RGB"), actual.convert("RGB"))
    mean = ImageStat.Stat(difference).mean
    return sum(mean) / 3.0


def save_animation(
    reference_frames: list[Image.Image],
    durations: list[int],
    destination: Path,
) -> tuple[int, float, float]:
    if len(reference_frames) != len(durations):
        raise RuntimeError("preview frame/duration count mismatch")
    encoded = shared_palette_frames(reference_frames)
    encoded[0].save(
        destination,
        format="GIF",
        save_all=True,
        append_images=encoded[1:],
        duration=durations,
        loop=0,
        optimize=False,
        disposal=2,
    )

    with Image.open(destination) as image:
        decoded = [frame.convert("RGB").copy() for frame in ImageSequence.Iterator(image)]
    if len(decoded) < 2:
        raise RuntimeError(
            f"preview collapsed to {len(decoded)} frame from {len(reference_frames)}: {destination}"
        )

    # GIF writers may legally coalesce repeated or mirrored duplicate frames. Color
    # fidelity is checked against the closest original reference frame rather than
    # requiring duplicate frames to survive as separate encoded image blocks.
    errors = [
        min(frame_error(reference, actual) for reference in reference_frames)
        for actual in decoded
    ]
    mean_error = sum(errors) / len(errors)
    maximum_error = max(errors)
    if mean_error > MAX_MEAN_COLOR_ERROR or maximum_error > MAX_SINGLE_FRAME_ERROR:
        raise RuntimeError(
            f"color fidelity failed for {destination.name}: mean={mean_error:.3f}, max={maximum_error:.3f}"
        )
    return len(decoded), mean_error, maximum_error


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
    ring_levels = [24, 38, 56, 78, 56, 38, 24, 38]
    frames: list[Image.Image] = []
    for scale, level in zip(scales, ring_levels):
        canvas = Image.new("RGBA", (module.CANVAS, module.CANVAS), (0, 0, 0, 255))
        draw = ImageDraw.Draw(canvas, "RGBA")
        inset = 13 + int((1.0 - scale) * 18)
        draw.ellipse(
            (inset, inset, module.CANVAS - inset - 1, module.CANVAS - inset - 1),
            outline=(96, 128, 168, level),
            width=2,
        )
        maximum = max(1, int((module.CANVAS - 18) * scale))
        width = max(1, source_image.width)
        height = max(1, source_image.height)
        ratio = min(maximum / width, maximum / height)
        target = (max(1, round(width * ratio)), max(1, round(height * ratio)))
        artwork = source_image.resize(target, Image.Resampling.LANCZOS)
        x = (module.CANVAS - artwork.width) // 2
        y = (module.CANVAS - artwork.height) // 2
        canvas.alpha_composite(artwork, (x, y))
        frames.append(canvas.convert("RGB"))

    destination.parent.mkdir(parents=True, exist_ok=True)
    count, mean_error, maximum_error = save_animation(frames, [90] * len(frames), destination)
    if destination.stat().st_size > module.MAX_OUTPUT_BYTES:
        raise RuntimeError(f"forced preview exceeds size limit: {destination.stat().st_size}")
    return {
        "frames": count,
        "bytes": destination.stat().st_size,
        "sha256": module.sha256(destination),
        "meanAbsoluteColorError": round(mean_error, 4),
        "maximumFrameColorError": round(maximum_error, 4),
        "paletteColors": 256,
    }


def build_animation(media_root: Path, destination: Path) -> dict:
    files = module.image_files(media_root)
    if not files:
        raise RuntimeError(f"no images in {media_root}")
    gifs = [path for path in files if path.suffix.lower() == ".gif"]
    if gifs:
        frames, durations = module.frames_from_gif(max(gifs, key=lambda path: path.stat().st_size))
    elif len(files) > 1:
        frames, durations = module.frames_from_files(files)
    else:
        frames, durations = module.pulse_frames(files[0])
    if len(frames) < 2:
        return forced_bounded_pulse(media_root, destination)

    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        count, mean_error, maximum_error = save_animation(frames, durations, destination)
    except RuntimeError as error:
        if "collapsed to 1 frame" not in str(error):
            raise
        metadata = forced_bounded_pulse(media_root, destination)
        print(
            f"animated_preview_fallback={destination.stem}|reason=identical-static-frames|frames={metadata['frames']}",
            flush=True,
        )
        return metadata

    if destination.stat().st_size > module.MAX_OUTPUT_BYTES:
        reduced = frames[::2] if len(frames) > 4 else frames
        reduced_durations = [min(250, duration * 2) for duration in durations[::2]]
        count, mean_error, maximum_error = save_animation(reduced, reduced_durations, destination)
    if destination.stat().st_size > module.MAX_OUTPUT_BYTES:
        raise RuntimeError(f"color-faithful preview exceeds size limit: {destination.stat().st_size}")

    return {
        "frames": count,
        "bytes": destination.stat().st_size,
        "sha256": module.sha256(destination),
        "meanAbsoluteColorError": round(mean_error, 4),
        "maximumFrameColorError": round(maximum_error, 4),
        "paletteColors": 256,
    }


module.fit_frame = fit_frame
module.build_animation = build_animation
module.main()
