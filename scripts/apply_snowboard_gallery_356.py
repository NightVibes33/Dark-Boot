#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

import apply_snowboard_gallery as base


def main() -> None:
    base.main()
    path = Path(__file__).resolve().parents[1] / "gif2aniprefs" / "G2OpenThemeLibrary.inc"
    source = path.read_text()
    bad = 'containsString:@"\\"])'
    good = 'containsString:@"\\\\"])'
    if bad in source:
        source = source.replace(bad, good)
        path.write_text(source)
    if good not in path.read_text():
        raise RuntimeError("SnowBoard archive-path backslash validation was not generated correctly")
    print("snowboard_objc_backslash_escape=passed")


if __name__ == "__main__":
    main()
