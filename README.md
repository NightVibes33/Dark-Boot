# Gif2Ani Rootless

A rootless iOS 15/16 port of the original **Gif2Ani V2** respring-animation tweak by wizages.

This repository hooks the real BackBoard respring surface through `BKDisplayRenderOverlaySpinny`. The previous Dark-Boot SpringBoard overlay is not used.

## Current version

- Package: `com.nightvibes33.gif2ani`
- Version: `3.4.0`
- Architecture: `iphoneos-arm64`
- Target: rootless iOS 15 and 16
- Injection target: `backboardd` only
- Gallery: **66 selectable built-in themes**

## 66-theme gallery

Gif2Ani 3.4 exposes two built-in layers inside **Settings → Gif2Ani → Browse and Preview Animations**:

- **12 offline themes** generated locally and available immediately.
- **54 downloadable CC0 themes** generated as six color palettes multiplied by nine animation engines.

The 54 downloadable themes are pinned to a specific source commit and may only download over HTTPS from the expected repository path. A downloaded theme is cached, previewed with bounded decoding, and staged only after the user taps **Stage This Animation**. Staging preserves the user’s selected scaling, background, repeat mode, and duration.

### Offline themes

1. Pulse Rings
2. Orbit Dots
3. Neon Bars
4. Radar Sweep
5. Cyber Grid
6. Square Tunnel
7. Equalizer
8. Spark Burst
9. Halo Spinner
10. Glitch Blocks
11. Energy Wave
12. Rotating Cube

### Downloadable theme matrix

Palettes:

- Cyan
- Magenta
- Lime
- Amber
- Violet
- Ice

Animation engines:

- Pulse Rings
- Orbit Dots
- Equalizer
- Radar Sweep
- Cyber Grid
- Square Tunnel
- Spark Burst
- Halo Spinner
- Energy Wave

This produces exactly `6 × 9 = 54` downloadable themes and `12 + 54 = 66` selectable built-in themes.

The gallery also contains a separate **54-package legacy compatibility catalog** for known Springy, SnowBoard, WinterBoard, and older respring packages. Those entries are references and import targets; artwork without clear redistribution permission is not silently rehosted.

## Import support

Gif2Ani can safely discover or import:

- Animated GIF files
- Springy packs
- SnowBoard Respring themes
- Compatible frame folders
- ZIP archives
- DEB packages

Imports are bounded by file-count, archive-size, extracted-size, source-frame, decoded-frame, dimension, and estimated-memory limits. Imported content is staged first and is never activated merely by selecting or downloading it.

## 3.0.0 physical-device incident

Version 3.0.0 crash-looped `backboardd` immediately after a GIF was selected, before **Apply and Respring** was tapped.

The physical-device crash reports and source path identified the failure chain:

1. The document picker copied the selected GIF directly into the live path.
2. It immediately posted a Darwin reload notification to `backboardd`.
3. The reload callback decoded the GIF synchronously inside BackBoard.
4. The old decoder called `+[UIScreen mainScreen]` for image scale while running inside `backboardd`.
5. UIKit raised an uncaught exception; `backboardd` aborted while Gif2Ani and ElleKit were loaded.
6. The live GIF remained and `isEnabled` defaulted to `true`, so subsequent BackBoard launches repeated the failure and produced a boot loop.

The old build also had a separate memory-safety risk: it could retain up to 180 frames at 2048 pixels in a critical process on a 2 GB device. The immediate abort and the decoder limits both required correction.

## Crash-safe activation design

Activation is a staged transaction:

- The tweak is disabled by default.
- Selecting, downloading, generating, or importing an animation writes only `Pending.gif`.
- Staging sends no Darwin notification and does not contact `backboardd`.
- Import validation runs inside Settings, not inside `backboardd`.
- **Apply and Respring** atomically promotes `Pending.gif` to `Active.gif`.
- The decoder uses image scale `1.0`; it never calls `UIScreen.mainScreen` inside `backboardd`.
- Media is decoded lazily only when the actual respring animation starts.
- The old `BKImageSequence` override was replaced with a bounded `CAKeyframeAnimation` on the existing BackBoard content layer.
- A load sentinel automatically quarantines `Active.gif` if `backboardd` restarts during decode or animation startup.
- Invalid media is moved to `Rejected.gif`, the tweak disables itself, and Apple’s normal animation is used.
- Applying a new theme keeps a rollback copy until promotion and preference verification succeed.

### Hard limits for the 2 GB iPad

- Maximum input file: 25 MB
- Maximum source frames: 240
- Maximum decoded frames: 24
- Maximum decoded dimension: 640 px
- Maximum estimated and actual decoded memory: 48 MB
- Maximum imported files: 5,000
- Maximum archive size: 100 MB
- Maximum extracted size: 150 MB

## Preserved controls

- Enable/disable state
- Animated GIF import
- Fit, fill, stretch, and center scaling
- Custom loop count
- Custom playback duration
- Background color picker
- Explicit Apply and Respring
- Automatic fallback to Apple’s normal respring animation
- Automatic crash-loop quarantine
- Reset layout and playback settings
- Current status and diagnostics

## Dependency replacements

The original project depended on Cephei, libcolorpicker, and WriteAnywhere. The rootless port keeps the same user-facing functionality with native iOS alternatives:

- Native plist-backed preferences
- `UIColorPickerViewController`
- `UIDocumentPickerViewController`
- Mobile-owned application-support storage
- Bounded ImageIO thumbnail decoding
- `NSURLSession` for pinned catalog downloads

The original legacy helper source remains in the repository for historical reference, but it is not linked into the package.

## Verified physical-device state

Target device:

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11
- palera1n rootless
- 2 GB RAM

Verified recovery and installation results from the 3.1 safety redesign:

- Version 3.0.0, its injection files, preferences, and selected GIF were removed in jailbreak safe mode.
- Recovery verification confirmed both `backboardd` and SpringBoard were running afterward.
- The crash-safe rootless arm64 build passed its source and package validation workflow.
- A two-frame 64×64 test GIF was placed only in `Pending.gif` for 15 seconds.
- `backboardd` remained on the same PID throughout that staged-only test.
- No `Active.gif`, `Rejected.gif`, or `load-in-progress` sentinel was created.

The 3.4 gallery build is CI-validated for rootless arm64 packaging. Its complete Apply-and-Respring path still requires a controlled physical-device test outside jailbreak safe mode. Keep a working safe-mode recovery path available during that test.

## Usage

1. Open **Settings → Gif2Ani**.
2. Open **Browse and Preview Animations**.
3. Choose one of the 12 offline themes, download one of the 54 CC0 themes, select an installed pack, or import your own media.
4. Preview it and tap **Stage This Animation**.
5. Return to the main Gif2Ani pane and configure scaling, background, repeat mode, and duration.
6. Tap **Apply and Respring** when ready.

Merely selecting, downloading, previewing, or staging an animation does not contact or restart `backboardd`.

## Build

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

The package is created as:

```text
packages/com.nightvibes33.gif2ani_3.4.0_iphoneos-arm64.deb
```

The dedicated workflow validates the 66-theme source contract, compiles the rootless arm64 tweak and Settings bundle, inspects the packaged resources and injection files, uploads the DEB artifact, and records the result in `status/build-340.txt`.

Recovery branches:

```text
backup-gif2ani-3.0.0-crash-build
backup-darkboot-2.0.1-before-gif2ani
```
