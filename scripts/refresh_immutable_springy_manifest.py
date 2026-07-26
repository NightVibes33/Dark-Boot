#!/usr/bin/env python3
from __future__ import annotations

import concurrent.futures
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "gif2aniprefs" / "Resources" / "OpenThemeCatalog.json"
MEDIA_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pinned_url(record: dict) -> str:
    commit = str(record.get("sourceCommit", "")).lower()
    filename = str(record.get("filename", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError(f"invalid sourceCommit for {record.get('identifier')}: {commit!r}")
    if not filename.startswith("./debs/") or not filename.endswith(".deb"):
        raise RuntimeError(f"invalid filename for {record.get('identifier')}: {filename!r}")
    if ".." in filename or "\\" in filename:
        raise RuntimeError(f"unsafe filename for {record.get('identifier')}: {filename!r}")
    return f"https://raw.githubusercontent.com/VirenMohindra/CydiaRepo/{commit}/{filename[2:]}"


def normalized_display_name(raw_name: str, identifier: str) -> str:
    # Preserve actual package qualifiers such as "(DankerThings)" while removing
    # only the repository's generic product suffix.
    value = re.sub(r"\s*-\s*Springy BootLogo\b", "", raw_name, flags=re.IGNORECASE)
    value = re.sub(r"\s+", " ", value).strip()
    if not value or len(value) > 120 or any(ch in value for ch in "\r\n\t"):
        raise RuntimeError(f"invalid DEB Name field for {identifier}: {raw_name!r}")
    return value


def inspect_record(record: dict, work_root: Path) -> tuple[str, dict]:
    identifier = str(record["identifier"])
    package = str(record["package"])
    if identifier != package or not re.fullmatch(r"io\.github\.virenmohindra\.[A-Za-z0-9.-]+", package):
        raise RuntimeError(f"invalid package identity: {identifier!r} / {package!r}")

    item_root = work_root / identifier
    deb_path = item_root / "theme.deb"
    extract_root = item_root / "root"
    item_root.mkdir(parents=True, exist_ok=True)
    url = pinned_url(record)

    completed = subprocess.run([
        "curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3",
        "--connect-timeout", "20", "--max-time", "300",
        "--output", str(deb_path), "--write-out", "%{url_effective}", url,
    ], check=True, text=True, stdout=subprocess.PIPE)
    effective = completed.stdout.strip()
    if effective != url:
        raise RuntimeError(f"unexpected redirect for {identifier}: {effective!r}")

    size = deb_path.stat().st_size
    if size <= 0 or size > MAX_ARCHIVE_BYTES:
        raise RuntimeError(f"unsafe archive size for {identifier}: {size}")
    sha256 = file_sha256(deb_path)
    actual_package = subprocess.check_output(
        ["dpkg-deb", "-f", str(deb_path), "Package"], text=True
    ).strip()
    if actual_package != package:
        raise RuntimeError(f"package mismatch for {identifier}: {actual_package!r}")

    raw_name = subprocess.check_output(
        ["dpkg-deb", "-f", str(deb_path), "Name"], text=True
    ).strip()
    display_name = normalized_display_name(raw_name, identifier)

    architecture = subprocess.check_output(
        ["dpkg-deb", "-f", str(deb_path), "Architecture"], text=True
    ).strip()
    if architecture not in {"iphoneos-arm", "iphoneos-arm64", "all"}:
        raise RuntimeError(f"unexpected architecture for {identifier}: {architecture!r}")

    subprocess.run(["dpkg-deb", "-x", str(deb_path), str(extract_root)], check=True)
    media_count = sum(
        1 for path in extract_root.rglob("*")
        if path.is_file() and path.suffix.lower() in MEDIA_EXTENSIONS
    )
    if media_count < 2:
        raise RuntimeError(f"not enough animation artwork in {identifier}: {media_count}")

    updated = dict(record)
    old_bytes = int(record.get("bytes", 0) or 0)
    old_sha = str(record.get("sha256", "")).lower()
    if old_bytes and old_bytes != size:
        updated["legacyPagesBytes"] = old_bytes
    if re.fullmatch(r"[0-9a-f]{64}", old_sha) and old_sha != sha256:
        updated["legacyPagesSHA256"] = old_sha
    updated["name"] = display_name
    updated["sourcePackageName"] = raw_name
    updated["downloadURL"] = url
    updated["sha256"] = sha256
    updated["bytes"] = size
    updated["payloadSource"] = "Immutable raw Git DEB at the recorded source commit, downloaded and independently inspected."
    updated["immutableVerifiedMediaFiles"] = media_count
    return identifier, updated


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text())
    records = manifest.get("themes")
    if not isinstance(records, list) or len(records) != 48:
        raise RuntimeError(f"expected 48 Springy records, got {len(records) if isinstance(records, list) else 'invalid'}")
    if manifest.get("sourceRepository") != "VirenMohindra/CydiaRepo":
        raise RuntimeError("unexpected source repository")
    if manifest.get("sourceLicense") != "MIT":
        raise RuntimeError("unexpected source license")

    with tempfile.TemporaryDirectory(prefix="gif2ani-immutable-manifest-") as temporary:
        work_root = Path(temporary)
        results: dict[str, dict] = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            futures = [executor.submit(inspect_record, record, work_root) for record in records]
            completed_count = 0
            for future in concurrent.futures.as_completed(futures):
                identifier, updated = future.result()
                results[identifier] = updated
                completed_count += 1
                print(
                    f"verified {completed_count:02d}/48 {identifier} "
                    f"name={updated['name']!r} bytes={updated['bytes']} sha256={updated['sha256']}",
                    flush=True,
                )

    updated_records = [results[str(record["identifier"])] for record in records]
    if len(results) != 48 or len({record["identifier"] for record in updated_records}) != 48:
        raise RuntimeError("immutable manifest result set is incomplete")

    verified_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    manifest["count"] = 48
    manifest["downloadPolicy"] = "Immutable raw Git commit URL; SHA-256, byte count, package identity, exact package name, and extracted artwork verified"
    manifest["immutableCatalogVerifiedAtUTC"] = verified_at
    manifest["namesDerivedFromDEBMetadata"] = True
    manifest["themes"] = updated_records
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

    total_bytes = sum(int(record["bytes"]) for record in updated_records)
    changed = sum(1 for record in updated_records if "legacyPagesSHA256" in record or "legacyPagesBytes" in record)
    print("immutable_manifest_count=48")
    print(f"immutable_manifest_total_bytes={total_bytes}")
    print(f"records_changed_from_pages_snapshot={changed}")
    print("names_derived_from_deb_metadata=48")
    print(f"immutable_catalog_verified_at_utc={verified_at}")


if __name__ == "__main__":
    main()
