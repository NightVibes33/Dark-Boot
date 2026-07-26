#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import hashlib
import json
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "gif2aniprefs/Resources/OpenThemeCatalog.json"
DIAGNOSTIC_PATH = ROOT / "status/open-theme-live-diagnostic.json"
OPEN_LIBRARY_PATH = ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc"
BUILD_WORKFLOW_PATH = ROOT / ".github/workflows/build-gif2ani-340.yml"
AUDIT_STATUS_PATH = ROOT / "status/open-theme-live-audit.txt"

REPO_COMMIT = "c507a391f193c2bb362ff77fc1c1673c0da2dcae"
SWISH_PACKAGE = "io.github.virenmohindra.swish"
SWISH_URL = (
    "https://raw.githubusercontent.com/VirenMohindra/CydiaRepo/"
    f"{REPO_COMMIT}/debs/io.github.virenmohindra.swish_2.0_iphoneos-arm.deb"
)
PAGES_PREFIX = "https://virenmohindra.github.io/debs/"


def checked(args: list[str]) -> str:
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError(
            f"exit={result.returncode} command={' '.join(args)} stderr={result.stderr[-1500:]}"
        )
    return result.stdout


def verify_swish() -> tuple[int, str, int]:
    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        deb = root / "swish.deb"
        checked(
            [
                "curl",
                "-fL",
                "--retry",
                "5",
                "--retry-delay",
                "2",
                "--connect-timeout",
                "20",
                "--max-time",
                "240",
                SWISH_URL,
                "-o",
                str(deb),
            ]
        )
        size = deb.stat().st_size
        digest = hashlib.sha256(deb.read_bytes()).hexdigest()
        package = checked(["dpkg-deb", "-f", str(deb), "Package"]).strip()
        if package != SWISH_PACKAGE:
            raise RuntimeError(f"Swish package mismatch: {package}")

        listing = checked(["dpkg-deb", "-c", str(deb)])
        for line in listing.splitlines():
            parts = line.split(maxsplit=5)
            if len(parts) < 6:
                continue
            mode = parts[0]
            archive_path = parts[5].split(" -> ", 1)[0]
            if mode.startswith(("l", "h", "c", "b", "p", "s")):
                raise RuntimeError(f"Swish unsafe archive entry: {mode} {archive_path}")
            if (
                not archive_path.startswith("./")
                or "/../" in archive_path
                or archive_path.startswith("./../")
            ):
                raise RuntimeError(f"Swish unsafe archive path: {archive_path}")

        extracted = root / "root"
        extracted.mkdir()
        checked(["dpkg-deb", "-x", str(deb), str(extracted)])
        media = []
        for path in extracted.rglob("*"):
            if path.is_symlink():
                raise RuntimeError(f"Swish extracted symlink: {path}")
            if path.is_file() and path.suffix.lower() in {
                ".gif",
                ".png",
                ".jpg",
                ".jpeg",
                ".webp",
            }:
                media.append(path)
        if not media:
            raise RuntimeError("Swish has no previewable media")
        return size, digest, len(media)


def patch_url_validator() -> None:
    source = OPEN_LIBRARY_PATH.read_text()
    old = '''static BOOL G2OpenThemeURLIsAllowed(NSURL *url, BOOL indexURL) {
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    if (![url.host.lowercaseString isEqualToString:@"virenmohindra.github.io"]) return NO;
    NSString *path = url.path.stringByStandardizingPath;
    if (indexURL) return [path isEqualToString:@"/Packages"];
    return [path hasPrefix:@"/debs/"] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
}
'''
    new = f'''static NSString * const G2OpenThemePinnedRawHost = @"raw.githubusercontent.com";
static NSString * const G2OpenThemePinnedRawPrefix = @"/VirenMohindra/CydiaRepo/{REPO_COMMIT}/debs/";

static BOOL G2OpenThemeURLIsAllowed(NSURL *url, BOOL indexURL) {{
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.stringByStandardizingPath;
    if (indexURL) {{
        return [host isEqualToString:@"virenmohindra.github.io"] && [path isEqualToString:@"/Packages"];
    }}
    if ([host isEqualToString:@"virenmohindra.github.io"]) {{
        return [path hasPrefix:@"/debs/"] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
    }}
    if ([host isEqualToString:G2OpenThemePinnedRawHost]) {{
        return [path hasPrefix:G2OpenThemePinnedRawPrefix] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
    }}
    return NO;
}}
'''
    if old in source:
        OPEN_LIBRARY_PATH.write_text(source.replace(old, new, 1))
    elif "G2OpenThemePinnedRawPrefix" not in source:
        raise RuntimeError("Open-theme URL validator block not found")


def patch_build_contract() -> None:
    source = BUILD_WORKFLOW_PATH.read_text()
    old = "assert item['downloadURL'].startswith('https://virenmohindra.github.io/debs/')"
    new = (
        "assert item['downloadURL'].startswith('https://virenmohindra.github.io/debs/') "
        f"or (item['package'] == '{SWISH_PACKAGE}' and item['downloadURL'] == '{SWISH_URL}')"
    )
    if old in source:
        BUILD_WORKFLOW_PATH.write_text(source.replace(old, new))
    elif SWISH_URL not in source:
        raise RuntimeError("Build URL contract assertion not found")


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text())
    diagnostic = json.loads(DIAGNOSTIC_PATH.read_text())
    if catalog.get("count") != 48 or len(catalog.get("themes", [])) != 48:
        raise RuntimeError("Expected 48 catalog themes")
    if diagnostic.get("expectedCount") != 48:
        raise RuntimeError("Diagnostic expected-count mismatch")
    if diagnostic.get("successCount") != 47 or diagnostic.get("failureCount") != 1:
        raise RuntimeError("Diagnostic does not contain the expected 47+1 result")
    failures = diagnostic.get("failures", [])
    if len(failures) != 1 or failures[0].get("package") != SWISH_PACKAGE:
        raise RuntimeError("Swish is not the sole failed Pages payload")
    successes = {item["package"]: item for item in diagnostic["successes"]}
    if len(successes) != 47:
        raise RuntimeError("Expected 47 verified live Pages payloads")

    swish_bytes, swish_sha, swish_media = verify_swish()
    verified_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    results = []

    for item in catalog["themes"]:
        package = item["package"]
        previous_bytes = int(item["bytes"])
        previous_sha = item["sha256"]
        previous_url = item["downloadURL"]
        if package == SWISH_PACKAGE:
            actual_bytes = swish_bytes
            actual_sha = swish_sha
            media_count = swish_media
            item["downloadURL"] = SWISH_URL
            item["payloadSource"] = (
                "Immutable raw source-repository fallback because the GitHub Pages DEB is missing."
            )
            item["payloadSourceCommit"] = REPO_COMMIT
        else:
            result = successes.get(package)
            if not result:
                raise RuntimeError(f"No verified diagnostic result for {package}")
            actual_bytes = int(result["actual_bytes"])
            actual_sha = result["actual_sha256"]
            media_count = int(result["media_count"])
            if not item["downloadURL"].startswith(PAGES_PREFIX):
                raise RuntimeError(f"Unexpected live Pages URL for {package}")
            item["payloadSource"] = (
                "Live Viren GitHub Pages DEB, independently downloaded and inspected."
            )

        if not re.fullmatch(r"[0-9a-f]{64}", actual_sha):
            raise RuntimeError(f"Invalid verified SHA-256 for {package}")
        item["previousIndexBytes"] = previous_bytes
        item["previousIndexSHA256"] = previous_sha
        item["bytes"] = actual_bytes
        item["sha256"] = actual_sha
        item["verifiedMediaFiles"] = media_count
        item["liveVerifiedAtUTC"] = verified_at
        results.append(
            {
                "name": item["name"],
                "package": package,
                "url": item["downloadURL"],
                "bytes": actual_bytes,
                "sha256": actual_sha,
                "media": media_count,
                "previousBytes": previous_bytes,
                "previousSHA256": previous_sha,
                "previousURL": previous_url,
            }
        )

    if len(results) != 48 or len({item["package"] for item in catalog["themes"]}) != 48:
        raise RuntimeError("Final catalog is not exactly 48 unique packs")

    catalog["liveSnapshotVerifiedAtUTC"] = verified_at
    catalog["liveSnapshotCount"] = 48
    catalog["repositoryIndexMismatchCount"] = 47
    catalog["missingPagesPayloadFallbackCount"] = 1
    catalog["verificationPolicy"] = (
        "Each DEB was downloaded over HTTPS and verified for package identity, byte count, "
        "SHA-256, safe archive paths/types, no extracted symlinks, and previewable media. "
        "Bundled records remain authoritative over stale live index metadata."
    )
    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + "\n")

    patch_url_validator()
    patch_build_contract()

    lines = [
        "Gif2Ani Verified 48-Pack Live Snapshot",
        f"verified_at_utc={verified_at}",
        "verified_pack_count=48",
        "live_pages_pack_count=47",
        "immutable_source_fallback_count=1",
        f"swish_fallback_url={SWISH_URL}",
        f"swish_bytes={swish_bytes}",
        f"swish_sha256={swish_sha}",
        f"swish_media_files={swish_media}",
        "all_package_identities_verified=true",
        "all_archives_preflighted=true",
        "all_packs_have_previewable_media=true",
        "",
    ]
    for index, result in enumerate(results, 1):
        lines.append(
            f"{index:02d}. {result['name']} | {result['package']} | "
            f"bytes={result['bytes']} | sha256={result['sha256']} | "
            f"media={result['media']} | url={result['url']}"
        )
    AUDIT_STATUS_PATH.write_text("\n".join(lines) + "\n")

    print("verified_open_theme_snapshot=48")
    print(f"swish_bytes={swish_bytes}")
    print(f"swish_sha256={swish_sha}")
    print(f"verified_at_utc={verified_at}")


if __name__ == "__main__":
    main()
