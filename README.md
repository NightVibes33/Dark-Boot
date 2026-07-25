# Dark-Boot

Dark-Boot is a rootless iOS 15/16 tweak that displays a custom full-screen image and plays a custom sound when SpringBoard starts.

## Verified target

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11 (`20H360`)
- palera1n rootless
- Procursus bootstrap at `/var/jb`
- ElleKit
- `iphoneos-arm64`

## What it changes

Dark-Boot runs when SpringBoard launches after a normal jailbreak boot or respring. It can:

- Display an imported image from the Files picker
- Play an imported WAV, CAF, MP3, M4A, or AIFF sound
- Use Fit, Fill, or Stretch image sizing
- Use Fade, Zoom, or Pulse animation
- Adjust duration and sound volume
- Preview changes without respringing
- Reset imported media safely

## Important limitation

A normal rootless tweak cannot replace the Apple logo displayed by iBoot before iOS userspace starts. Dark-Boot starts as early as a SpringBoard tweak safely can and does not modify the sealed system volume or bootchain.

## Build

The GitHub Actions workflow builds a rootless `.deb` automatically. Open the latest successful **Build Rootless DEB** run and download the `Dark-Boot-rootless-deb` artifact.

Local Theos build:

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

## Install

Install the generated package using Sileo, Zebra, Filza, or:

```sh
dpkg -i com.nightvibes33.darkboot_*_iphoneos-arm64.deb
sbreload
```

Then open **Settings → Dark Boot** to import media and preview it.

## Custom media location

Imported files are stored in:

```text
/var/mobile/Library/Application Support/DarkBoot/
```

Dark-Boot never overwrites Apple boot assets.
