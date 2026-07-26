#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("apply_gif2ani_359_archive_and_animated_previews_v2.py")
spec = importlib.util.spec_from_file_location("gif2ani_359_patch", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load Gif2Ani 3.5.9 patch module")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def regex_once(text: str, pattern: str, replacement: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    output, count = re.subn(pattern, lambda _match: replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"missing {label}; matches={count}")
    return output


module.regex_once = regex_once
module.main()
