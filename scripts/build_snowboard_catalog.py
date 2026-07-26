#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "gif2aniprefs" / "Resources" / "SnowBoardCatalog.json"
STATUS = ROOT / "status" / "snowboard-catalog-audit.txt"
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}

SECTION_PAGES = [
    "https://www.ios-repo-updates.com/section/respring%20logos/",
    "https://www.ios-repo-updates.com/section/respring%EF%BC%88%E6%B3%A8%E9%94%80%E5%8A%A8%E7%94%BB%EF%BC%89/",
]

# These source pages cover the larger SnowBoard-era packs that are not filed
# in the old Respring Logos sections. Invalid/offline pages are skipped.
EXPLICIT_PACKAGE_PAGES = [
    "https://www.ios-repo-updates.com/repository/basepack/package/com.project.brooklyn/",
    "https://www.ios-repo-updates.com/repository/redentic-s-repo/package/com.redenticdev.respringpack/",
    "https://www.ios-repo-updates.com/repository/redentic-s-repo/package/com.redenticdev.swrespringpack/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.rkycyku.allin1.respring/",
    "https://www.ios-repo-updates.com/repository/twickd/package/com.twickd.rilind-kycyku.all-in-one-respring-pack/",
    "https://www.ios-repo-updates.com/repository/packix/package/com.shadows.checkra1nrespring/",
    "https://www.ios-repo-updates.com/repository/packix/package/respring.hende.megapack/",
    "https://www.ios-repo-updates.com/repository/packix/package/respring.hende.razerlogo/",
    "https://www.ios-repo-updates.com/repository/packix/package/beta.hende.megapack/",
    "https://www.ios-repo-updates.com/repository/packix/package/com.bluspark.pixeliosrespringpack1/",
]

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": "Gif2Ani-SnowBoard-Catalog/1.0 (+https://github.com/NightVibes33/Dark-Boot)",
    "Accept": "text/html,application/xhtml+xml,application/octet-stream;q=0.9,*/*;q=0.8",
})


@dataclass(frozen=True)
class PackagePage:
    page_url: str
    package: str
    display_name: str
    version: str
    author: str
    repository: str
    description: str
    download_url: str
    expected_sha256: str


def fetch(url: str, *, timeout: int = 45) -> requests.Response:
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            response = SESSION.get(url, timeout=timeout, allow_redirects=True)
            response.raise_for_status()
            return response
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            if attempt < 3:
                time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"could not fetch {url}: {last_error}")


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def discover_package_pages() -> list[str]:
    pages = set(EXPLICIT_PACKAGE_PAGES)
    for section_url in SECTION_PAGES:
        try:
            soup = BeautifulSoup(fetch(section_url).text, "html.parser")
        except Exception as exc:  # noqa: BLE001
            print(f"section_warning={section_url}|{exc}", flush=True)
            continue
        for anchor in soup.find_all("a", href=True):
            href = urljoin(section_url, anchor["href"])
            if "/repository/" in href and "/package/" in href and not href.rstrip("/").endswith("/amp"):
                pages.add(href.split("?")[0])
    return sorted(pages)


def field_from_text(text: str, label: str) -> str:
    pattern = rf"(?:^|\s){re.escape(label)}\s+(.+?)(?=\s+(?:Added Date|Updated Date|Free package|Repository|Author|Section|Version|Architecture|Size|Installed-Size|Depends|Compatibility|Description|Version History)\b|$)"
    match = re.search(pattern, text, flags=re.I | re.S)
    return clean_text(match.group(1)) if match else ""


def parse_package_page(page_url: str) -> PackagePage | None:
    response = fetch(page_url)
    soup = BeautifulSoup(response.text, "html.parser")
    text = clean_text(soup.get_text(" "))
    if "Free package" not in text:
        return None

    package = field_from_text(text, "Identifier")
    if not package:
        parts = [part for part in urlparse(page_url).path.split("/") if part]
        package = parts[-1] if parts else ""
    if not re.fullmatch(r"[A-Za-z0-9.+~-]+", package):
        return None

    heading = soup.find("h1")
    display_name = clean_text(heading.get_text(" ")) if heading else package
    author = field_from_text(text, "Author")
    repository = field_from_text(text, "Repository")
    description_match = re.search(r"Description\s+(.+?)\s+(?:Depiction\s+)?Version History", text, re.I | re.S)
    description = clean_text(description_match.group(1)) if description_match else "SnowBoard-compatible respring theme"

    download_anchor = None
    for anchor in soup.find_all("a", href=True):
        label = clean_text(anchor.get_text(" "))
        if label.lower().startswith("download "):
            download_anchor = anchor
            break
    if not download_anchor:
        return None

    link_label = clean_text(download_anchor.get_text(" "))
    version_match = re.search(r"\bversion\s+(.+)$", link_label, re.I)
    version = clean_text(version_match.group(1)) if version_match else field_from_text(text, "Version")
    download_url = urljoin(page_url, download_anchor["href"])
    if urlparse(download_url).scheme != "https":
        return None

    context = download_anchor.find_parent(["li", "div", "tr"]) or download_anchor.parent
    context_text = clean_text(context.get_text(" ")) if context else ""
    sha_match = re.search(r"SHA256\s+([0-9a-fA-F]{64})", context_text)
    if not sha_match:
        # Some pages flatten version history without wrapping each release.
        after = text[text.find(link_label):]
        sha_match = re.search(r"SHA256\s+([0-9a-fA-F]{64})", after)
    if not sha_match:
        return None

    return PackagePage(
        page_url=page_url,
        package=package,
        display_name=display_name,
        version=version,
        author=author or "Original theme author",
        repository=repository or urlparse(download_url).netloc,
        description=description,
        download_url=download_url,
        expected_sha256=sha_match.group(1).lower(),
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(args: list[str]) -> str:
    completed = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return completed.stdout


def safe_archive(deb: Path) -> None:
    listing = command(["dpkg-deb", "-c", str(deb)])
    entries = 0
    for raw in listing.splitlines():
        if not raw.strip():
            continue
        mode = raw[0]
        if mode in "lhcbps":
            raise RuntimeError(f"unsafe archive entry type {mode}")
        marker = raw.rfind(" ./")
        if marker < 0:
            continue
        path = raw[marker + 2:].split(" -> ", 1)[0].replace("\\", "/")
        parts = [part for part in path.split("/") if part and part != "."]
        if path.startswith("/") or ".." in parts:
            raise RuntimeError(f"unsafe archive path {path}")
        entries += 1
        if entries > 5000:
            raise RuntimeError("archive contains more than 5000 entries")
    if not entries:
        raise RuntimeError("archive has no readable entries")


def slug(value: str) -> str:
    result = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return result[:80] or "theme"


def theme_directories(extract_root: Path) -> list[Path]:
    candidates: list[Path] = []
    for path in extract_root.rglob("*"):
        if not path.is_dir() or not path.name.lower().endswith(".theme"):
            continue
        images = [item for item in path.rglob("*") if item.is_file() and item.suffix.lower() in IMAGE_EXTENSIONS]
        if images:
            candidates.append(path)
    # Keep the deepest .theme when packages contain wrapper themes.
    output: list[Path] = []
    for candidate in sorted(candidates, key=lambda p: (len(p.parts), str(p).lower()), reverse=True):
        if any(candidate in kept.parents for kept in output):
            continue
        output.append(candidate)
    return sorted(output, key=lambda p: str(p).lower())


def inspect_package(page: PackagePage, work_root: Path) -> tuple[list[dict], dict]:
    package_root = work_root / slug(page.package)
    package_root.mkdir(parents=True, exist_ok=True)
    deb = package_root / "package.deb"

    response = fetch(page.download_url, timeout=180)
    data = response.content
    if not data or len(data) > MAX_ARCHIVE_BYTES:
        raise RuntimeError(f"invalid archive size {len(data)}")
    deb.write_bytes(data)
    actual_sha = sha256_file(deb)
    if actual_sha != page.expected_sha256:
        raise RuntimeError(f"sha256 mismatch {actual_sha} != {page.expected_sha256}")

    actual_package = clean_text(command(["dpkg-deb", "-f", str(deb), "Package"]))
    actual_version = clean_text(command(["dpkg-deb", "-f", str(deb), "Version"]))
    architecture = clean_text(command(["dpkg-deb", "-f", str(deb), "Architecture"]))
    actual_name = clean_text(command(["dpkg-deb", "-f", str(deb), "Name"])) or page.display_name
    if actual_package != page.package:
        raise RuntimeError(f"package mismatch {actual_package} != {page.package}")
    if page.version and actual_version != page.version:
        raise RuntimeError(f"version mismatch {actual_version} != {page.version}")
    if architecture not in {"iphoneos-arm", "iphoneos-arm64", "all"}:
        raise RuntimeError(f"unexpected architecture {architecture}")

    safe_archive(deb)
    extracted = package_root / "root"
    command(["dpkg-deb", "-x", str(deb), str(extracted)])
    themes = theme_directories(extracted)
    if not themes:
        raise RuntimeError("no .theme directory containing image artwork")

    records: list[dict] = []
    used_identifiers: set[str] = set()
    for theme in themes:
        images = sorted(
            [item for item in theme.rglob("*") if item.is_file() and item.suffix.lower() in IMAGE_EXTENSIONS],
            key=lambda p: str(p).lower(),
        )
        if not images:
            continue
        relative = theme.relative_to(extracted).as_posix()
        theme_name = theme.name[:-6] if theme.name.lower().endswith(".theme") else theme.name
        base_identifier = f"snowboard.{slug(page.package)}.{slug(theme_name)}"
        identifier = base_identifier
        suffix = 2
        while identifier in used_identifiers:
            identifier = f"{base_identifier}-{suffix}"
            suffix += 1
        used_identifiers.add(identifier)
        animated = any(image.suffix.lower() == ".gif" for image in images) or len(images) > 1
        records.append({
            "identifier": identifier,
            "package": actual_package,
            "packageName": actual_name,
            "name": theme_name,
            "version": actual_version,
            "architecture": architecture,
            "downloadURL": page.download_url,
            "effectiveURL": response.url,
            "sha256": actual_sha,
            "bytes": len(data),
            "archiveSubpath": relative,
            "mediaFiles": len(images),
            "animationKind": "animated" if animated else "static-logo",
            "source": page.repository,
            "sourcePage": page.page_url,
            "author": page.author,
            "description": page.description,
            "verification": "Direct public HTTPS DEB; page SHA-256, package identity, version, architecture, safe archive paths, .theme path, and image artwork verified",
        })

    if not records:
        raise RuntimeError("no usable SnowBoard subthemes")
    package_result = {
        "package": actual_package,
        "name": actual_name,
        "version": actual_version,
        "bytes": len(data),
        "sha256": actual_sha,
        "downloadURL": page.download_url,
        "effectiveURL": response.url,
        "subthemes": len(records),
    }
    return records, package_result


def main() -> None:
    pages = discover_package_pages()
    print(f"candidate_page_count={len(pages)}", flush=True)
    records: list[dict] = []
    packages: list[dict] = []
    failures: list[str] = []
    seen_packages: set[str] = set()

    with tempfile.TemporaryDirectory(prefix="gif2ani-snowboard-") as temporary:
        work_root = Path(temporary)
        for index, page_url in enumerate(pages, 1):
            try:
                page = parse_package_page(page_url)
                if page is None:
                    failures.append(f"{page_url}|not-free-or-no-direct-sha256-download")
                    continue
                if page.package in seen_packages:
                    continue
                package_records, package_result = inspect_package(page, work_root)
                seen_packages.add(page.package)
                records.extend(package_records)
                packages.append(package_result)
                print(
                    f"verified_package_{len(packages):03d}={page.package}|subthemes={len(package_records)}|"
                    f"bytes={package_result['bytes']}|sha256={package_result['sha256']}",
                    flush=True,
                )
            except Exception as exc:  # noqa: BLE001
                failures.append(f"{page_url}|{clean_text(str(exc))}")
                print(f"candidate_failure_{index:03d}={page_url}|{clean_text(str(exc))}", flush=True)

    deduped: dict[str, dict] = {}
    for record in records:
        deduped[record["identifier"]] = record
    records = sorted(deduped.values(), key=lambda item: (item["name"].lower(), item["identifier"]))
    if len(packages) < 3 or len(records) < 10:
        raise RuntimeError(f"verified SnowBoard inventory is too small: {len(packages)} packages / {len(records)} themes")

    manifest = {
        "version": 1,
        "catalogType": "verified-snowboard-respring",
        "count": len(records),
        "packageCount": len(packages),
        "discoveryPages": pages,
        "policy": "Only free direct public original DEBs with a published matching SHA-256 and verified .theme artwork are included. Packages are downloaded and extracted for artwork only; they are never installed.",
        "themes": records,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

    STATUS.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "Gif2Ani Verified SnowBoard Respring Catalog",
        f"candidate_page_count={len(pages)}",
        f"verified_package_count={len(packages)}",
        f"verified_theme_count={len(records)}",
        f"rejected_or_unavailable_count={len(failures)}",
        "all_included_packages_free=true",
        "all_included_downloads_https=true",
        "all_included_sha256_verified=true",
        "all_included_package_ids_verified=true",
        "all_included_theme_paths_verified=true",
        "",
        "--- packages ---",
    ]
    for index, package in enumerate(sorted(packages, key=lambda p: p["package"]), 1):
        lines.append(
            f"{index:03d}. {package['package']} | {package['name']} | {package['version']} | "
            f"subthemes={package['subthemes']} | bytes={package['bytes']} | sha256={package['sha256']} | "
            f"url={package['downloadURL']} | effective={package['effectiveURL']}"
        )
    lines.extend(["", "--- themes ---"])
    for index, record in enumerate(records, 1):
        lines.append(
            f"{index:03d}. {record['name']} | {record['identifier']} | package={record['package']} | "
            f"path={record['archiveSubpath']} | media={record['mediaFiles']} | kind={record['animationKind']}"
        )
    lines.extend(["", "--- rejected/unavailable ---"])
    lines.extend(failures)
    STATUS.write_text("\n".join(lines) + "\n")

    print(f"snowboard_verified_package_count={len(packages)}")
    print(f"snowboard_verified_theme_count={len(records)}")
    print(f"snowboard_rejected_count={len(failures)}")


if __name__ == "__main__":
    main()
