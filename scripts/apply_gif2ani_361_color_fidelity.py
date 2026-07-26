#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "control"
ROOT_PLIST = ROOT / "gif2aniprefs/Resources/Root.plist"


def main() -> None:
    lines = CONTROL.read_text().splitlines()
    description = (
        "Description: Crash-safe custom respring animations for BackBoard on rootless iOS 15 and 16. "
        "Gif2Ani 3.6.1 regenerates all 262 bundled downloadable previews with one shared 256-color palette per animation, preserved RGBA compositing, and strict mean/max color-error gates so pre-download gallery cards match the verified extracted artwork instead of appearing neon, muddy, or discolored. "
        "Only visible cards decode frames; off-screen cells release animations and a 12 MB bounded cache protects 2 GB devices. "
        "It retains the rootless archive fix, 274-theme gallery, and source package integrity verification."
    )
    output = []
    for line in lines:
        if line.startswith("Version:"):
            output.append("Version: 3.6.1")
        elif line.startswith("Description:"):
            output.append(description)
        else:
            output.append(line)
    CONTROL.write_text("\n".join(output) + "\n")

    plist = ROOT_PLIST.read_text()
    plist = plist.replace("GIF2ANI 3.6.0", "GIF2ANI 3.6.1")
    plist = plist.replace(
        "Downloadable theme cards animate from their bundled preview before download. Only visible cards decode frames; off-screen cards release animations to protect this 2 GB iPad.",
        "Downloadable theme cards animate before download using color-faithful shared 256-color palettes. Only visible cards decode frames; off-screen cards release animations to protect this 2 GB iPad.",
    )
    ROOT_PLIST.write_text(plist)

    assert "Version: 3.6.1" in CONTROL.read_text()
    assert "GIF2ANI 3.6.1" in ROOT_PLIST.read_text()
    print("gif2ani_361_color_fidelity_version=success")


if __name__ == "__main__":
    main()
