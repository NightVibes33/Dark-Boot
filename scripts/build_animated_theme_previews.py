#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from PIL import Image, ImageSequence

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "gif2aniprefs" / "Resources"
OUTPUT = RESOURCES / "ThemePreviewAnimations"
MANIFEST = RESOURCES / "ThemePreviewAnimations.json"
CC0_COMMIT = "b5d5eda04359409865772038895e660d709deb18"
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
CANVAS = 144
MAX_FRAMES = 10
MAX_OUTPUT_BYTES = 280_000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(url: str, destination: Path, expected_sha: str, expected_bytes: int) -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    completed = subprocess.run(
        [
            "curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3",
            "--connect-timeout", "20", "--max-time", "300", "--output", str(destination),
            "--write-out", "%{url_effective}", url,
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if destination.stat().st_size != int(expected_bytes):
        raise RuntimeError(f"byte mismatch for {url}: {destination.stat().st_size} != {expected_bytes}")
    actual_sha = sha256(destination)
    if actual_sha != expected_sha.lower():
        raise RuntimeError(f"sha mismatch for {url}: {actual_sha} != {expected_sha}")
    return completed.stdout.strip()


def natural_key(path: Path) -> list[object]:
    return [int(piece) if piece.isdigit() else piece.lower() for piece in re.split(r"(\d+)", str(path))]


def sample_indexes(count: int, maximum: int = MAX_FRAMES) -> list[int]:
    if count <= maximum:
        return list(range(count))
    return sorted({round(index * (count - 1) / (maximum - 1)) for index in range(maximum)})


def fit_frame(image: Image.Image, scale: float = 1.0) -> Image.Image:
    source = image.convert("RGBA")
    maximum = max(1, int((CANVAS - 8) * scale))
    source.thumbnail((maximum, maximum), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 255))
    x = (CANVAS - source.width) // 2
    y = (CANVAS - source.height) // 2
    canvas.alpha_composite(source, (x, y))
    return canvas.convert("P", palette=Image.Palette.ADAPTIVE, colors=64)


def frames_from_gif(path: Path) -> tuple[list[Image.Image], list[int]]:
    with Image.open(path) as image:
        total = getattr(image, "n_frames", 1)
        indexes = set(sample_indexes(total))
        frames: list[Image.Image] = []
        durations: list[int] = []
        for index, frame in enumerate(ImageSequence.Iterator(image)):
            if index not in indexes:
                continue
            frames.append(fit_frame(frame.copy()))
            raw_duration = int(frame.info.get("duration", image.info.get("duration", 80)) or 80)
            durations.append(max(40, min(250, raw_duration)))
        return frames, durations


def frames_from_files(files: list[Path]) -> tuple[list[Image.Image], list[int]]:
    selected = [files[index] for index in sample_indexes(len(files))]
    frames: list[Image.Image] = []
    for path in selected:
        try:
            with Image.open(path) as image:
                if getattr(image, "n_frames", 1) > 1:
                    nested, _ = frames_from_gif(path)
                    frames.extend(nested[: max(1, MAX_FRAMES - len(frames))])
                else:
                    frames.append(fit_frame(image.copy()))
        except Exception:
            continue
        if len(frames) >= MAX_FRAMES:
            break
    return frames[:MAX_FRAMES], [80] * min(MAX_FRAMES, len(frames))


def pulse_frames(path: Path) -> tuple[list[Image.Image], list[int]]:
    with Image.open(path) as image:
        original = image.copy()
    scales = [0.88, 0.93, 0.98, 1.0, 0.98, 0.93, 0.88, 0.93]
    return [fit_frame(original, scale) for scale in scales], [90] * len(scales)


def image_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root] if root.suffix.lower() in IMAGE_EXTENSIONS else []
    return sorted(
        [path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS],
        key=natural_key,
    )


def score_directory(directory: Path, files: list[Path]) -> int:
    lower = str(directory).lower()
    score = len(files) * 100
    for token, value in (
        ("springy", 6000), ("respring", 5500), ("bootlogo", 5000),
        ("animation", 4000), ("frames", 2500), ("theme", 800),
        ("preview", -7000), ("icon", -9000), ("depiction", -7000),
    ):
        if token in lower:
            score += value
    return score


def best_media_root(root: Path) -> Path:
    files = image_files(root)
    if not files:
        raise RuntimeError(f"no preview media in {root}")
    by_directory: dict[Path, list[Path]] = {}
    for path in files:
        by_directory.setdefault(path.parent, []).append(path)
    return max(by_directory, key=lambda directory: (score_directory(directory, by_directory[directory]), str(directory)))


def build_animation(media_root: Path, destination: Path) -> dict:
    files = image_files(media_root)
    if not files:
        raise RuntimeError(f"no images in {media_root}")
    gifs = [path for path in files if path.suffix.lower() == ".gif"]
    if gifs:
        frames, durations = frames_from_gif(max(gifs, key=lambda path: path.stat().st_size))
    elif len(files) > 1:
        frames, durations = frames_from_files(files)
    else:
        frames, durations = pulse_frames(files[0])
    if len(frames) < 2:
        frames, durations = pulse_frames(files[0])
    if len(frames) < 2:
        raise RuntimeError(f"could not create at least two frames from {media_root}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        destination,
        format="GIF",
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=2,
    )
    if destination.stat().st_size > MAX_OUTPUT_BYTES:
        reduced = frames[::2] if len(frames) > 4 else frames
        reduced_durations = [min(250, duration * 2) for duration in durations[::2]]
        reduced[0].save(
            destination,
            format="GIF",
            save_all=True,
            append_images=reduced[1:],
            duration=reduced_durations,
            loop=0,
            optimize=True,
            disposal=2,
        )
    with Image.open(destination) as check:
        count = getattr(check, "n_frames", 1)
        if count < 2:
            raise RuntimeError(f"preview collapsed to {count} frame: {destination}")
    return {
        "frames": count,
        "bytes": destination.stat().st_size,
        "sha256": sha256(destination),
    }


def verify_deb(deb: Path, package: str) -> None:
    actual = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Package"], text=True).strip()
    if actual != package:
        raise RuntimeError(f"package mismatch: {actual} != {package}")


def cc0_job(theme: dict, work: Path) -> tuple[str, dict]:
    identifier = theme["id"]
    source = work / "cc0" / identifier / Path(theme["file"]).name
    url = f"https://raw.githubusercontent.com/NightVibes33/Codex-DEB-Test/{CC0_COMMIT}/gif2ani-themes/v1/{theme['file']}"
    fetch(url, source, theme["sha256"], int(theme["bytes"]))
    metadata = build_animation(source, OUTPUT / f"{identifier}.gif")
    metadata.update({"identifier": identifier, "catalog": "cc0", "source": url})
    return identifier, metadata


def springy_job(theme: dict, work: Path) -> tuple[str, dict]:
    identifier = theme["identifier"]
    package_root = work / "springy" / identifier
    deb = package_root / "theme.deb"
    extracted = package_root / "root"
    fetch(theme["downloadURL"], deb, theme["sha256"], int(theme["bytes"]))
    verify_deb(deb, theme["package"])
    subprocess.run(["dpkg-deb", "-x", str(deb), str(extracted)], check=True)
    media_root = best_media_root(extracted)
    metadata = build_animation(media_root, OUTPUT / f"{identifier}.gif")
    metadata.update({"identifier": identifier, "catalog": "springy", "package": theme["package"]})
    return identifier, metadata


def prepare_snowboard_packages(themes: list[dict], work: Path) -> dict[str, Path]:
    packages: dict[str, dict] = {}
    for theme in themes:
        packages.setdefault(theme["package"], theme)
    extracted_roots: dict[str, Path] = {}
    for package, theme in sorted(packages.items()):
        package_root = work / "snowboard" / re.sub(r"[^A-Za-z0-9_.-]+", "-", package)
        deb = package_root / "theme.deb"
        extracted = package_root / "root"
        fetch(theme["downloadURL"], deb, theme["sha256"], int(theme["bytes"]))
        verify_deb(deb, package)
        subprocess.run(["dpkg-deb", "-x", str(deb), str(extracted)], check=True)
        extracted_roots[package] = extracted
    return extracted_roots


def snowboard_job(theme: dict, extracted_roots: dict[str, Path]) -> tuple[str, dict]:
    identifier = theme["identifier"]
    root = extracted_roots[theme["package"]]
    relative = Path(theme["archiveSubpath"])
    if relative.is_absolute() or ".." in relative.parts:
        raise RuntimeError(f"unsafe SnowBoard path: {relative}")
    media_root = root / relative
    if not media_root.is_dir():
        raise RuntimeError(f"missing SnowBoard theme path: {media_root}")
    metadata = build_animation(media_root, OUTPUT / f"{identifier}.gif")
    metadata.update({"identifier": identifier, "catalog": "snowboard", "package": theme["package"]})
    return identifier, metadata


def main() -> None:
    cc0 = json.loads((RESOURCES / "ThemeCatalog.json").read_text())["themes"]
    springy = json.loads((RESOURCES / "OpenThemeCatalog.json").read_text())["themes"]
    snowboard_manifest = json.loads((RESOURCES / "SnowBoardCatalog.json").read_text())
    snowboard = snowboard_manifest["themes"]
    if (len(cc0), len(springy), len(snowboard), snowboard_manifest.get("packageCount")) != (54, 48, 160, 7):
        raise RuntimeError("unexpected source catalog counts")

    shutil.rmtree(OUTPUT, ignore_errors=True)
    OUTPUT.mkdir(parents=True)
    records: dict[str, dict] = {}
    with tempfile.TemporaryDirectory(prefix="gif2ani-animated-previews-") as temporary:
        work = Path(temporary)
        snowboard_roots = prepare_snowboard_packages(snowboard, work)
        jobs = []
        with ThreadPoolExecutor(max_workers=6) as pool:
            jobs.extend(pool.submit(cc0_job, theme, work) for theme in cc0)
            jobs.extend(pool.submit(springy_job, theme, work) for theme in springy)
            jobs.extend(pool.submit(snowboard_job, theme, snowboard_roots) for theme in snowboard)
            for completed, future in enumerate(as_completed(jobs), 1):
                identifier, metadata = future.result()
                if identifier in records:
                    raise RuntimeError(f"duplicate preview identifier: {identifier}")
                records[identifier] = metadata
                print(f"animated_preview={completed:03d}/262|{identifier}|frames={metadata['frames']}|bytes={metadata['bytes']}", flush=True)

    files = sorted(OUTPUT.glob("*.gif"))
    if len(files) != 262 or len(records) != 262:
        raise RuntimeError(f"generated {len(files)} files and {len(records)} records instead of 262")
    total = sum(path.stat().st_size for path in files)
    if total > 55 * 1024 * 1024:
        raise RuntimeError(f"animated preview bundle is too large: {total}")
    manifest = {
        "version": 1,
        "count": 262,
        "totalBytes": total,
        "limits": {"canvas": CANVAS, "maximumFrames": MAX_FRAMES, "maximumFileBytes": MAX_OUTPUT_BYTES},
        "previews": [records[key] for key in sorted(records)],
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("animated_preview_count=262")
    print(f"animated_preview_total_bytes={total}")
    print("animated_preview_validation=success")


if __name__ == "__main__":
    main()
