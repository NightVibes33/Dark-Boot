#!/usr/bin/env python3
"""Apply the SnowBoard gallery patch, then validate emitted Objective-C."""
from __future__ import annotations

from pathlib import Path

import apply_snowboard_gallery as base


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    base.main()
    path = ROOT / "gif2aniprefs" / "G2OpenThemeLibrary.inc"
    source = path.read_text()
    bad = 'containsString:@"\\"])'
    good = 'containsString:@"\\\\"])'
    if bad in source:
        source = source.replace(bad, good, 1)
        path.write_text(source)
    verified = path.read_text()
    if good not in verified or bad in verified:
        raise RuntimeError("SnowBoard archive-path backslash validation was not emitted correctly")
    print("snowboard_objc_backslash_escape=passed")


if __name__ == "__main__":
    main()
