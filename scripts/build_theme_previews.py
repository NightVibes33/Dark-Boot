#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "gif2aniprefs" / "Resources"
OUTPUT = RESOURCES / "ThemePreviews"
CC0_COMMIT = "b5d5eda04359409865772038895e660d709deb18"
ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(url: str, destination: Path, expected_sha: str, expected_bytes: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        "curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3",
        "--connect-timeout", "20", "--max-time", "240", "--output", str(destination), url,
    ], check=True)
    actual_bytes = destination.stat().st_size
    actual_sha = sha256(destination)
    if actual_bytes != expected_bytes:
        raise RuntimeError(f"byte mismatch for {url}: {actual_bytes} != {expected_bytes}")
    if actual_sha != expected_sha.lower():
        raise RuntimeError(f"sha mismatch for {url}: {actual_sha} != {expected_sha}")


def save_thumbnail(source: Path, destination: Path) -> None:
    with Image.open(source) as image:
        try:
            image.seek(0)
        except EOFError:
            pass
        frame = image.convert("RGBA")
        frame.thumbnail((220, 220), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (220, 220), (0, 0, 0, 255))
        x = (220 - frame.width) // 2
        y = (220 - frame.height) // 2
        canvas.alpha_composite(frame, (x, y))
        canvas.convert("RGB").save(destination, "PNG", optimize=True)


def cc0_thumbnail(theme: dict, work: Path) -> str:
    identifier = theme["id"]
    source = work / "cc0" / theme["file"]
    url = f"https://raw.githubusercontent.com/NightVibes33/Codex-DEB-Test/{CC0_COMMIT}/gif2ani-themes/v1/{theme['file']}"
    fetch(url, source, theme["sha256"], int(theme["bytes"]))
    save_thumbnail(source, OUTPUT / f"{identifier}.png")
    return identifier


def image_score(path: Path, sibling_count: int) -> int:
    lower = str(path).lower()
    score = sibling_count * 10
    if path.suffix.lower() == ".gif":
        score += 100000
    for token, value in (
        ("springy", 5000), ("respring", 4500), ("bootlogo", 4000),
        ("animation", 3000), ("frames", 1500), ("theme", 500),
        ("preview", -6000), ("icon", -8000), ("depiction", -5000),
        ("screenshot", -5000), ("thumbnail", -5000),
    ):
        if token in lower:
            score += value
    return score


def best_image(extract_root: Path) -> Path:
    candidates = [p for p in extract_root.rglob("*") if p.is_file() and p.suffix.lower() in ALLOWED_EXTENSIONS]
    if not candidates:
        raise RuntimeError(f"no image files in {extract_root}")
    counts: dict[Path, int] = {}
    for path in candidates:
        counts[path.parent] = counts.get(path.parent, 0) + 1
    ranked = sorted(candidates, key=lambda p: (image_score(p, counts[p.parent]), str(p)), reverse=True)
    for candidate in ranked:
        try:
            with Image.open(candidate) as image:
                image.verify()
            return candidate
        except Exception:
            continue
    raise RuntimeError(f"no decodable image files in {extract_root}")


def springy_thumbnail(theme: dict, work: Path) -> str:
    identifier = theme["identifier"]
    package_work = work / "springy" / identifier
    deb = package_work / "theme.deb"
    extracted = package_work / "root"
    package_work.mkdir(parents=True, exist_ok=True)
    fetch(theme["downloadURL"], deb, theme["sha256"], int(theme["bytes"]))
    package_id = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Package"], text=True).strip()
    if package_id != theme["package"]:
        raise RuntimeError(f"package mismatch: {package_id} != {theme['package']}")
    subprocess.run(["dpkg-deb", "-x", str(deb), str(extracted)], check=True)
    source = best_image(extracted)
    save_thumbnail(source, OUTPUT / f"{identifier}.png")
    return identifier


def main() -> None:
    cc0_manifest = json.loads((RESOURCES / "ThemeCatalog.json").read_text())
    springy_manifest = json.loads((RESOURCES / "OpenThemeCatalog.json").read_text())
    cc0 = cc0_manifest["themes"]
    springy = springy_manifest["themes"]
    if len(cc0) != 54 or len(springy) != 48:
        raise RuntimeError(f"unexpected catalog counts: {len(cc0)} CC0, {len(springy)} Springy")

    shutil.rmtree(OUTPUT, ignore_errors=True)
    OUTPUT.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="gif2ani-previews-") as temp:
        work = Path(temp)
        jobs = []
        with ThreadPoolExecutor(max_workers=6) as pool:
            for theme in cc0:
                jobs.append(pool.submit(cc0_thumbnail, theme, work))
            for theme in springy:
                jobs.append(pool.submit(springy_thumbnail, theme, work))
            completed = 0
            for future in as_completed(jobs):
                identifier = future.result()
                completed += 1
                print(f"preview {completed:03d}/102: {identifier}", flush=True)

    previews = sorted(OUTPUT.glob("*.png"))
    if len(previews) != 102:
        raise RuntimeError(f"generated {len(previews)} previews instead of 102")
    total = sum(path.stat().st_size for path in previews)
    print(f"generated_previews={len(previews)}")
    print(f"generated_preview_bytes={total}")


if __name__ == "__main__":
    main()
