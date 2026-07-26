#!/usr/bin/env python3
"""Apply the SnowBoard gallery patch with validated Objective-C escaping."""
from __future__ import annotations

import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "apply_snowboard_gallery.py"

text = GENERATOR.read_text()
bad = r'[archiveSubpath containsString:@"\"])'
good = r'[archiveSubpath containsString:@"\\"])'

if bad in text:
    text = text.replace(bad, good, 1)
elif good not in text:
    raise RuntimeError("SnowBoard archive-path escape expression was not found")

GENERATOR.write_text(text)
compiled = compile(text, str(GENERATOR), "exec")
namespace = {"__name__": "__main__", "__file__": str(GENERATOR)}
exec(compiled, namespace)
