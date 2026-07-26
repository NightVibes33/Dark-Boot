# Gif2Ani Rootless

A rootless iOS 15/16 port of the original **Gif2Ani V2** respring-animation tweak by wizages.

This repository hooks the real BackBoard respring surface through `BKDisplayRenderOverlaySpinny`. The previous Dark-Boot SpringBoard overlay is not used.

## Current version

- Package: `com.nightvibes33.gif2ani`
- Version: `3.4.1`
- Architecture: `iphoneos-arm64`
- Target: rootless iOS 15 and 16
- Injection target: `backboardd` only
- Gallery: **114 first-class themes**
- Downloadable themes: **102**

## 114-theme gallery

Gif2Ani exposes three first-class theme groups inside **Settings → Gif2Ani → Browse and Preview Animations**:

- **12 offline procedural themes** generated locally and available immediately.
- **54 downloadable CC0 themes** from Gif2Ani’s pinned immutable catalog.
- **48 downloadable original Springy packs** from the verified `VirenMohindra/CydiaRepo` catalog.

Every downloadable item is a normal gallery row—not a manual import. The user taps a theme, downloads and previews it, stages it, chooses scaling/background/repeat/duration, and then explicitly taps **Apply and Respring**.

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

### 54 Gif2Ani CC0 downloads

The generated catalog combines six palettes with nine animation engines:

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

This produces exactly `6 × 9 = 54` downloadable themes. Their manifest pins each file’s identifier, byte count, SHA-256, frame count, dimensions, license, author, and recommended settings.

### 48 original Springy downloads

The open-source catalog is snapshotted from `VirenMohindra/CydiaRepo` and contains 48 verified Springy packages. The repository publishes an MIT license; Gif2Ani preserves the original package names, authors, descriptions, versions, depictions, package identifiers, hashes, and source commit.

Gif2Ani does **not** install the old package or its obsolete Springy dependency. It downloads the original DEB from the original repository host, verifies SHA-256 and package identity, safely inspects and extracts the archive, finds compatible animation media, creates a bounded preview, and stages only the animation.

The verified names are recorded in `status/open-theme-library.txt` and include A Wave, Alone, Bipolar Balls, Black Hole, Boo, Bubbles, Colorful Stars In Space, Columns, Complicated, Echo, Fall Leaves, Flower, Fluid, Fragments, Funny Computer, Gameboy Advance, Gamecube Logo, Hello Again, Hypnotoad, Lines, Mograph, Only Human, Pepe Matrix, Pizza, Pizza Hi, Pokemon, Pulse, Rainbow 8, Rainy, Rolling Circles, Routine, Sonic Running, Soup, Spikey, Sploosh, Stay In Lane, Stranger Things, Super Mario, Swimmer, Swish, Tesseract, Three Waves, Time And Money, Twisting Cubes, Upload, Waiting, World Swap, and Yin And Yang.

Some historical themes depict third-party characters or brands. The catalog preserves upstream attribution and distribution metadata; it does not imply endorsement or ownership of those depicted properties.

### Additional compatibility references

A separate legacy reference/import section remains for known Springy, SnowBoard, WinterBoard, and older respring packages whose current original file or redistribution terms are not verified. Those rows are not counted among the 114 first-class themes and are not silently rehosted.

## Download and archive security

The two downloadable catalogs use different but strict trust models:

- Gif2Ani CC0 GIFs are restricted to a pinned HTTPS GitHub commit and checked against a bundled immutable manifest.
- Original Springy DEBs are restricted to the original upstream HTTPS host and checked against a bundled source snapshot.
- Download byte limits and SHA-256 hashes are verified before media is opened.
- Springy package identifiers must match the selected catalog row.
- DEBs and ZIPs are inspected before extraction.
- Absolute paths, traversal paths, symbolic links, hard links, devices, pipes, sockets, and other special files are rejected.
- Extracted file count and total storage are bounded.
- Only compatible image/GIF sequences are normalized into the Gif2Ani cache.
- Downloading, previewing, or staging never installs an old theme package and never contacts `backboardd`.

## Import support

Gif2Ani can safely discover or import:

- Animated GIF files
- Springy packs
- SnowBoard Respring themes
- Compatible frame folders
- ZIP archives
- DEB packages

Imports are bounded by file count, archive size, extracted size, source frames, decoded frames, dimensions, and estimated memory. Imported content is staged first and is never activated merely by selecting or importing it.

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
- Import and archive validation run inside Settings, not inside `backboardd`.
- **Apply and Respring** atomically promotes `Pending.gif` to `Active.gif`.
- The decoder uses image scale `1.0`; it never calls `UIScreen.mainScreen` inside `backboardd`.
- Media is decoded lazily only when the actual respring animation starts.
- The old `BKImageSequence` override was replaced with a bounded `CAKeyframeAnimation` on a dedicated BackBoard overlay layer.
- A load sentinel automatically quarantines `Active.gif` if `backboardd` restarts during decode or animation startup.
- Invalid media is moved to `Rejected.gif`, the tweak disables itself, and Apple’s normal animation is used.
- Applying a new theme keeps a rollback copy until promotion and preference verification succeed.

### Hard limits for the 2 GB iPad

- Maximum GIF input: 25 MB
- Maximum source frames: 240
- Maximum decoded frames: 24
- Maximum decoded dimension: 640 px
- Maximum estimated and actual decoded memory: 48 MB
- Maximum imported files: 5,000
- Maximum archive size: 100 MB
- Maximum extracted size: 150 MB

## Preserved controls

- Enable/disable state
- Fit, fill, stretch, and center scaling
- Custom repeat count
- Original or custom total playback duration
- Background color picker with alpha
- Explicit Apply and Respring
- Automatic fallback to Apple’s normal respring animation
- Automatic crash-loop quarantine
- Reset layout and playback settings
- Current status and diagnostics

Staging a catalog theme preserves the user’s selected controls rather than silently replacing them with catalog recommendations.

## Dependency replacements

The original project depended on Cephei, libcolorpicker, WriteAnywhere, and Springy-era package layouts. The rootless port uses native or internal alternatives:

- Native plist-backed preferences
- `UIColorPickerViewController`
- `UIDocumentPickerViewController`
- Mobile-owned application-support storage
- Bounded ImageIO thumbnail decoding
- `NSURLSession` ephemeral downloads
- Built-in DEB/ZIP inspection and extraction guards
- Native gallery, preview, staging, and cache management paths

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
- A two-frame 64×64 test GIF was placed only in `Pending.gif` for 15 seconds.
- `backboardd` remained on the same PID throughout that staged-only test.
- No `Active.gif`, `Rejected.gif`, or `load-in-progress` sentinel was created.

The current gallery and package are CI-validated for rootless arm64 packaging. The complete 3.4.1 Apply-and-Respring path and representative source-backed DEB downloads still require a controlled physical-device test outside jailbreak safe mode. Keep a working safe-mode recovery path available during that test.

## Usage

1. Open **Settings → Gif2Ani**.
2. Open **Browse and Preview Animations**.
3. Choose one of the 12 offline themes, one of the 54 CC0 downloads, one of the 48 original Springy downloads, an installed pack, or your own imported media.
4. For a downloadable theme, tap **Download & Preview**.
5. Preview it and tap **Stage This Animation**.
6. Return to the main Gif2Ani pane and configure scaling, background, repeat mode, and duration.
7. Tap **Apply and Respring** when ready.

Merely selecting, downloading, previewing, or staging an animation does not contact or restart `backboardd`.

## Build

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

The package is created as:

```text
packages/com.nightvibes33.gif2ani_3.4.1_iphoneos-arm64.deb
```

The dedicated workflow validates both bundled manifests, the 102 downloadable theme rows, staging and integrity code, the rootless injection files, the PreferenceLoader bundle, and the resulting arm64 Mach-O binaries. It uploads the DEB artifact and records the result in `status/build-341.txt`.

Recovery branches:

```text
backup-gif2ani-3.0.0-crash-build
backup-darkboot-2.0.1-before-gif2ani
```
