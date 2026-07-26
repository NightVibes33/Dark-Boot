#!/usr/bin/env python3
"""Build the SnowBoard catalog with deterministic verified package seeds.

The listing site may block GitHub-hosted runners. These seeds contain metadata
published on the original package pages, but every DEB is still downloaded from
its original repository and must pass the normal SHA-256, package ID, version,
architecture, archive-path, .theme-path, and artwork verification in
build_snowboard_catalog.py.
"""
from __future__ import annotations

import build_snowboard_catalog as base


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

EXTRA_PAGES = {
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringpack/",
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringrespringpack2/",
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringrespringpack3/",
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringfxxk/",
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.doughnuts/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/respring.hende.megapack/",
    "https://www.ios-repo-updates.com/repository/hende/package/beta.hende.megapack/",
    "https://www.ios-repo-updates.com/repository/iospackix/package/com.rkycyku.allin1.respring/",
}

_original_parse = base.parse_package_page


def seeded_discovery() -> list[str]:
    # Avoid making release success depend on section-index availability. The
    # explicit list contains the largest known packs and individual legacy rows.
    return sorted(set(base.EXPLICIT_PACKAGE_PAGES) | set(SEEDS) | EXTRA_PAGES)


def seeded_parse(page_url: str):
    seed = SEEDS.get(page_url)
    if seed is not None:
        return seed
    return _original_parse(page_url)


base.discover_package_pages = seeded_discovery
base.parse_package_page = seeded_parse

if __name__ == "__main__":
    base.main()
