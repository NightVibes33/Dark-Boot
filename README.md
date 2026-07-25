# Gif2Ani Rootless

A rootless iOS 15/16 port of the original **Gif2Ani V2** respring-animation tweak by wizages.

This repository hooks the real BackBoard respring surface through `BKDisplayRenderOverlaySpinny`. The previous Dark-Boot SpringBoard overlay is not used.

## Current version

- Package: `com.nightvibes33.gif2ani`
- Version: `3.1.0`
- Architecture: `iphoneos-arm64`
- Target: rootless iOS 15 and 16
- Injection target: `backboardd` only

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

## 3.1.0 safety redesign

Version 3.1.0 changes activation into a staged transaction:

- The tweak is disabled by default.
- Selecting a GIF writes only `Pending.gif`.
- Selecting a GIF sends no Darwin notification and does not contact `backboardd`.
- Import validation runs inside Settings, not inside `backboardd`.
- **Apply and Respring** atomically promotes `Pending.gif` to `Active.gif`.
- The decoder uses image scale `1.0`; it never calls `UIScreen.mainScreen` inside `backboardd`.
- Media is decoded lazily only when the actual respring animation starts.
- The legacy `BKImageSequence` override was replaced with a bounded `CAKeyframeAnimation` on the existing BackBoard content layer.
- A load sentinel automatically quarantines `Active.gif` if `backboardd` restarts during decode or animation startup.
- Invalid media is moved to `Rejected.gif`, the tweak disables itself, and Apple's normal animation is used.

### Hard limits for the 2 GB iPad

- Maximum input file: 25 MB
- Maximum decoded frames: 24
- Maximum decoded dimension: 640 px
- Maximum estimated and actual decoded memory: 48 MB

## Preserved features

- Enable/disable state
- Animated GIF import
- Fit, fill, stretch, and center scaling
- Custom loop count
- Custom playback duration
- Background color picker
- Explicit Apply and Respring
- Automatic fallback to Apple's normal respring animation
- Automatic crash-loop quarantine

## Dependency replacements

The original project depended on Cephei, libcolorpicker, and WriteAnywhere. The rootless port keeps the same user-facing functionality with native iOS alternatives:

- Native plist-backed preferences
- `UIColorPickerViewController`
- `UIDocumentPickerViewController`
- Mobile-owned application-support storage
- Bounded ImageIO thumbnail decoding

The original legacy helper source remains in the repository for historical reference, but it is not linked into the package.

## Verified physical-device state

Target device:

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11
- palera1n rootless
- 2 GB RAM

Verified recovery and installation results:

- Version 3.0.0, its injection files, preferences, and selected GIF were removed in jailbreak safe mode.
- Recovery verification confirmed both `backboardd` and SpringBoard were running afterward.
- Version 3.1.0 passed the rootless arm64 build and crash-safety validation workflow.
- Version 3.1.0 was installed on the physical iPad with `isEnabled=false` and no active GIF.
- A two-frame 64×64 test GIF was placed only in `Pending.gif` for 15 seconds.
- `backboardd` remained on the same PID throughout that staged-only test.
- No `Active.gif`, `Rejected.gif`, or `load-in-progress` sentinel was created.
- The test GIF was removed; the final device state is installed, disabled, and contains no GIF media.

The explicit Apply-and-Respring path has not yet been tested outside jailbreak safe mode. Keep the tweak disabled until a controlled normal-jailbreak test is completed.

## Usage

1. Open **Settings → Gif2Ani**.
2. Tap **Select and Stage GIF**.
3. Review the displayed frame, size, and decoded-memory estimate.
4. Configure scaling, loop count, duration, and background color.
5. Tap **Apply and Respring** only after the controlled normal-jailbreak test is complete.

Merely selecting a GIF does not contact or reload `backboardd`.

## Build

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

The package is created as:

```text
packages/com.nightvibes33.gif2ani_3.1.0_iphoneos-arm64.deb
```

Recovery branches:

```text
backup-gif2ani-3.0.0-crash-build
backup-darkboot-2.0.1-before-gif2ani
```
