#!/usr/bin/env python3
"""Build the SnowBoard catalog from deterministic published package metadata.

Every package is still downloaded directly from its original repository and
must pass SHA-256, package ID, version, architecture, archive-path, .theme-path,
and artwork verification. Unreachable or mismatched packages are excluded.
"""
from __future__ import annotations

import concurrent.futures
import json
import tempfile
from pathlib import Path

import build_snowboard_catalog as base
import requests as transport


SEEDS = {
    "https://www.ios-repo-updates.com/repository/basepack/package/com.project.brooklyn/": base.PackagePage(
        page_url="https://www.ios-repo-updates.com/repository/basepack/package/com.project.brooklyn/",
        package="com.project.brooklyn",
        display_name="Brooklyn",
        version="1.2",
        author="project11x",
        repository="Basepack",
        description="All Apple logos from the Apple 2018 event as SnowBoard respring animations.",
        download_url="https://repo.basepack.co/download/com.project.brooklyn.deb",
        expected_sha256="29510ee724455cf2b9b8636fefe430955490de62a67e06683057df310c96822b",
    ),
    "https://www.ios-repo-updates.com/repository/redentic-s-repo/package/com.redenticdev.respringpack/": base.PackagePage(
        page_url="https://www.ios-repo-updates.com/repository/redentic-s-repo/package/com.redenticdev.respringpack/",
        package="com.redenticdev.respringpack",
        display_name="Redentic's Respring Pack",
        version="1.2.0",
        author="RedenticDev",
        repository="Redentic's Repo",
        description="A free SnowBoard respring pack with multiple fun icons.",
        download_url="https://redentic.dev/debs/com.redenticdev.respringpack_1.2.0_iphoneos-arm.deb",
        expected_sha256="6d62c438ea6da37c1cdf81a3236f1bf7805092a4cfce14d816ef290a574cfb35",
    ),
    "https://www.ios-repo-updates.com/repository/twickd/package/com.twickd.rilind-kycyku.all-in-one-respring-pack/": base.PackagePage(
        page_url="https://www.ios-repo-updates.com/repository/twickd/package/com.twickd.rilind-kycyku.all-in-one-respring-pack/",
        package="com.twickd.rilind-kycyku.all-in-one-respring-pack",
        display_name="All in one Respring Pack",
        version="1.4",
        author="Rilind Kyçyku",
        repository="Twickd",
        description="A large free SnowBoard-compatible respring animation pack.",
        download_url="https://repo.twickd.com/files/com.twickd.rilind-kycyku.all-in-one-respring-pack/versions/8f34db0578bfb0db13468753d2c1e3c8.deb",
        expected_sha256="08c41fd97e83f57445a007328d7ca2bcbd61222ab4b3682033305f498a041935",
    ),
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.shadows.respringmix/": base.PackagePage(
        page_url="https://www.ios-repo-updates.com/repository/iospackix/package/com.shadows.respringmix/",
        package="com.shadows.respringmix",
        display_name="Respring Mix",
        version="1.0",
        author="Shadows",
        repository="Packix",
        description="A free pack of SnowBoard-compatible respring themes.",
        download_url="https://repo.packix.com/debs/com.shadows.respringmix_1.0.deb",
        expected_sha256="6b17a65ada7fc8b3b54a0f79eab69929015d603d775f703d98a5b4d04e753cb3",
    ),
}


def package_pages() -> list[base.PackagePage]:
    pages: dict[str, base.PackagePage] = dict(SEEDS)
    for page_url in sorted(getattr(transport, "KNOWN", {})):
        if page_url in pages:
            continue
        parsed = base.parse_package_page(page_url)
        if parsed is not None:
            pages[page_url] = parsed
    unique: dict[str, base.PackagePage] = {}
    for page in pages.values():
        unique.setdefault(page.package, page)
    return sorted(unique.values(), key=lambda item: item.package)


def inspect_one(page: base.PackagePage, work_root: Path):
    try:
        records, package = base.inspect_package(page, work_root)
        return page, records, package, None
    except Exception as exc:  # noqa: BLE001
        return page, [], None, base.clean_text(str(exc))


def main() -> None:
    pages = package_pages()
    print(f"candidate_page_count={len(pages)}", flush=True)
    records: list[dict] = []
    packages: list[dict] = []
    failures: list[str] = []

    with tempfile.TemporaryDirectory(prefix="gif2ani-snowboard-") as temporary:
        work_root = Path(temporary)
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, max(1, len(pages)))) as executor:
            futures = [executor.submit(inspect_one, page, work_root) for page in pages]
            completed = 0
            for future in concurrent.futures.as_completed(futures):
                page, package_records, package_result, error = future.result()
                completed += 1
                if error:
                    failures.append(f"{page.page_url}|{error}")
                    print(f"candidate_{completed:03d}=rejected|{page.package}|{error}", flush=True)
                    continue
                records.extend(package_records)
                packages.append(package_result)
                print(
                    f"verified_package_{len(packages):03d}={page.package}|subthemes={len(package_records)}|"
                    f"bytes={package_result['bytes']}|sha256={package_result['sha256']}",
                    flush=True,
                )

    deduped = {record["identifier"]: record for record in records}
    records = sorted(deduped.values(), key=lambda item: (item["name"].lower(), item["identifier"]))
    packages = sorted(packages, key=lambda item: item["package"])
    if len(packages) < 3 or len(records) < 10:
        raise RuntimeError(f"verified SnowBoard inventory is too small: {len(packages)} packages / {len(records)} themes")

    manifest = {
        "version": 1,
        "catalogType": "verified-snowboard-respring",
        "count": len(records),
        "packageCount": len(packages),
        "candidateCount": len(pages),
        "policy": "Only free direct public original DEBs with a published matching SHA-256 and verified .theme artwork are included. Packages are downloaded and extracted for artwork only; they are never installed.",
        "themes": records,
    }
    base.OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    base.OUTPUT.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

    base.STATUS.parent.mkdir(parents=True, exist_ok=True)
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
    for index, package in enumerate(packages, 1):
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
    lines.extend(["", "--- rejected/unavailable ---", *failures])
    base.STATUS.write_text("\n".join(lines) + "\n")

    print(f"snowboard_verified_package_count={len(packages)}")
    print(f"snowboard_verified_theme_count={len(records)}")
    print(f"snowboard_rejected_count={len(failures)}")


if __name__ == "__main__":
    main()
