#!/usr/bin/env python3
"""Apply the SnowBoard gallery patch, then validate emitted Objective-C."""
from __future__ import annotations

from pathlib import Path

import apply_snowboard_gallery as base


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    base.main()

    open_library = ROOT / "gif2aniprefs" / "G2OpenThemeLibrary.inc"
    source = open_library.read_text()
    bad = 'containsString:@"\\"])'
    good = 'containsString:@"\\\\"])'
    if bad in source:
        source = source.replace(bad, good, 1)
        open_library.write_text(source)
    verified = open_library.read_text()
    if good not in verified or bad in verified:
        raise RuntimeError("SnowBoard archive-path backslash validation was not emitted correctly")
    print("snowboard_objc_backslash_escape=passed")

    legacy_source = ROOT / "gif2aniprefs" / "G2ThemeGalleryPart1.inc"
    legacy_text = legacy_source.read_text()
    old = "static NSArray<NSDictionary *> *G2LegacyCatalog(void) {"
    new = "__attribute__((unused)) static NSArray<NSDictionary *> *G2LegacyCatalog(void) {"
    if old in legacy_text:
        legacy_text = legacy_text.replace(old, new, 1)
        legacy_source.write_text(legacy_text)
    if new not in legacy_source.read_text():
        raise RuntimeError("The removed historical compatibility catalog was not marked unused")
    print("snowboard_legacy_catalog_unused_annotation=passed")


if __name__ == "__main__":
    main()
