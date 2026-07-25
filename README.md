# Gif2Ani Rootless

A rootless iOS 15/16 port of the original **Gif2Ani V2** respring-animation tweak by wizages.

This repository no longer contains the previous Dark-Boot SpringBoard overlay. It now hooks the real BackBoard respring animation classes:

- `BKImageSequence`
- `BKDisplayRenderOverlaySpinny`

## Current version

- Package: `com.nightvibes33.gif2ani`
- Version: `3.0.0`
- Architecture: `iphoneos-arm64`
- Target: rootless iOS 15 and 16
- Injection target: `backboardd` only

## Preserved Gif2Ani features

- Enable/disable toggle
- Animated GIF import
- Fit, fill, stretch, and center scaling
- Custom loop count
- Custom playback duration
- Background color picker
- Apply and respring
- Automatic fallback to Apple's normal respring animation if the GIF cannot load

## Dependency replacements

The original project depended on Cephei, libcolorpicker, and WriteAnywhere. Version 3.0.0 preserves their user-facing functionality with native iOS alternatives:

- Preferences are read with a native plist-backed manager.
- Background color uses `UIColorPickerViewController`.
- GIF import uses `UIDocumentPickerViewController` and direct mobile-owned storage.
- GIF decoding uses bounded ImageIO decoding for lower memory use on 2 GB devices.

The original legacy helper source remains in the repository for historical reference, but it is not linked into the rootless package.

## Verified physical-device status

Verified on:

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11
- palera1n rootless

Confirmed on the physical iPad:

- Gif2Ani 3.0.0 is installed.
- The preference bundle and PreferenceLoader entry are installed.
- The tweak dylib is installed under `/var/jb`.
- `backboardd` loaded the tweak and created its runtime marker.
- Both required BackBoard classes exist on iOS 16.7.11.
- The previous `com.nightvibes33.darkboot` package, injection files, Settings bundle, preference entry, media directory, and preference plist were removed.

At the time of verification no GIF had been selected, so the runtime marker correctly reported `gifExists=false`, `frameCount=0`, and `event=gif-load-failed`. A custom animation is not considered visually verified until a GIF is selected in Settings and the iPad is resprung.

## Usage

1. Open **Settings → Gif2Ani**.
2. Turn on **Enable Gif2Ani**.
3. Tap **Select GIF** and choose an animated GIF.
4. Configure scaling, loop count, duration, and background color.
5. Tap **Apply and Respring**.

## Build

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

The validated package is created as:

```text
packages/com.nightvibes33.gif2ani_3.0.0_iphoneos-arm64.deb
```

The previous Dark-Boot 2.0.1 implementation remains recoverable from the branch:

```text
backup-darkboot-2.0.1-before-gif2ani
```
