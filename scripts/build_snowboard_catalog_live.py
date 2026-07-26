#!/usr/bin/env python3
"""Extend the deterministic SnowBoard verifier with known live Packix pages."""
from __future__ import annotations

import build_snowboard_catalog as base
import build_snowboard_catalog_seeded as seeded


LIVE_PAGE_URLS = [
    "https://www.ios-repo-updates.com/repository/hende/package/beta.hende.megapack/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.rkycyku.allin1.respring/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/respring.hende.megapack/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/respring.hende.razerlogo/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.bluspark.pixeliosrespringpack1/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.shadows.checkra1nrespring/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.thwlfu.cakrespring/",
]

_original_package_pages = seeded.package_pages


def live_package_pages() -> list[base.PackagePage]:
    packages = {page.package: page for page in _original_package_pages()}
    for page_url in LIVE_PAGE_URLS:
        try:
            page = base.parse_package_page(page_url)
        except Exception as exc:  # noqa: BLE001
            print(f"live_page_warning={page_url}|{base.clean_text(str(exc))}", flush=True)
            continue
        if page is not None:
            packages.setdefault(page.package, page)
    return sorted(packages.values(), key=lambda item: item.package)


seeded.package_pages = live_package_pages

if __name__ == "__main__":
    seeded.main()
