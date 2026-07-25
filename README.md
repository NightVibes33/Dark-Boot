# Gif2Ani Rootless

A rootless iOS 15/16 port of the original **Gif2Ani V2** respring-animation tweak by wizages.

This repository hooks the real BackBoard respring surface through `BKDisplayRenderOverlaySpinny`. The previous Dark-Boot SpringBoard overlay is not used.

## Current version

- Package: `com.nightvibes33.gif2ani`
- Version: `3.0.1`
- Architecture: `iphoneos-arm64`
- Target: rootless iOS 15 and 16
- Injection target: `backboardd` only

## 3.0.0 incident and root cause

Version 3.0.0 could crash-loop `backboardd` immediately after a GIF was selected, even before **Apply and Respring** was tapped.

The cause was a combination of four unsafe behaviors:

1. `isEnabled` defaulted to `true` when no preference existed.
2. The document picker copied the selected file directly into the live GIF path.
3. The picker immediately posted a Darwin reload notification to `backboardd`.
4. `backboardd` decoded and retained a large animated-image frame array during that notification.

The original limits allowed up to 180 decoded frames at 2048 pixels, which can require hundreds of megabytes or more. That is not safe inside a critical process on the 2 GB iPad 5th generation.

## 3.0.1 safety redesign

Version 3.0.1 changes activation into a staged transaction:

- The tweak is disabled by default.
- Selecting a GIF writes only `Pending.gif`.
- Selecting a GIF sends no live notification to `backboardd`.
- Import validation runs inside Settings, not inside `backboardd`.
- **Apply and Respring** atomically promotes `Pending.gif` to `Active.gif`.
- Media is decoded lazily only when the real respring animation starts.
- The legacy `BKImageSequence` override was replaced with a safer `CAKeyframeAnimation` on the existing BackBoard content layer.
- A load sentinel automatically quarantines `Active.gif` if `backboardd` restarts during decode or animation startup.
- Invalid media is moved to `Rejected.gif`, the tweak disables itself, and Apple's normal animation is used.

### Hard limits for the 2 GB iPad

- Maximum input file: 25 MB
- Maximum decoded frames: 24
- Maximum decoded dimension: 640 px
- Maximum estimated/actual decoded memory: 48 MB

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

## Verified device target

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11
- palera1n rootless

Version 3.0.0 was removed after the physical-device crash. Version 3.0.1 must remain disabled until its package build, safe-mode installation, staged-import behavior, normal boot, and explicit apply path have each been verified.

## Usage

1. Open **Settings → Gif2Ani**.
2. Tap **Select and Stage GIF**.
3. Review the displayed frame, size, and decoded-memory estimate.
4. Configure scaling, loop count, duration, and background color.
5. Tap **Apply and Respring**.

Merely selecting a GIF does not contact or reload `backboardd`.

## Build

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

The package is created as:

```text
packages/com.nightvibes33.gif2ani_3.0.1_iphoneos-arm64.deb
```

Recovery branches:

```text
backup-gif2ani-3.0.0-crash-build
backup-darkboot-2.0.1-before-gif2ani
```
