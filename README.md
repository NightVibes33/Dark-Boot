# Dark-Boot

## Production rootless iOS 15/16 startup visual and audio engine

Dark-Boot is a production-grade rootless tweak for palera1n/Procursus devices. It presents a custom full-screen startup experience when SpringBoard starts, with advanced visual, animation, audio, preview, safety, and Settings controls.

> [!IMPORTANT]
> Dark-Boot runs after iOS has reached SpringBoard. A normal rootless tweak cannot replace the early Apple/iBoot logo shown before userspace. Dark-Boot does not modify the bootchain or sealed system volume.

## Verified target

Dark-Boot 2.0.0 was built and verified for:

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11 (`20H360`)
- palera1n rootless
- Procursus bootstrap at `/var/jb`
- ElleKit/MobileSubstrate-compatible injection
- Package architecture: `iphoneos-arm64`
- Theos rootless package scheme

## Installation

Download the latest green `com.nightvibes33.darkboot_2.0.0_iphoneos-arm64.deb` build from the successful GitHub Actions artifact.

### Install with Sileo, Zebra, or Filza

1. Open the `.deb` file.
2. Choose your package installer.
3. Install the package and allow it to finish configuring.
4. Dark-Boot's post-install script closes Settings so PreferenceLoader refreshes, then triggers `sbreload`.
5. After SpringBoard returns, open **Settings → Dark Boot**.

There is no companion app and no terminal command required for normal use.

### Install from a terminal

```sh
sudo dpkg -i com.nightvibes33.darkboot_2.0.0_iphoneos-arm64.deb
# The package postinst triggers sbreload automatically.
```

## Features

### Visual engine

- Static PNG, JPEG, and HEIC images
- Animated GIF and APNG visuals
- Looping MP4, MOV, and M4V video
- Fit, Fill, and Stretch content modes
- Configurable entrance and exit animations
- Blur, dimming, particles, accent colors, and progress indicator
- Custom title and subtitle branding
- Built-in cinematic fallback visual when no media is imported

### Audio engine

- Custom WAV, CAF, MP3, M4A, and AIFF startup sounds
- Configurable volume
- Silent-switch behavior
- Audio ducking
- Fade-out on exit
- Optional video audio
- Fallback system chime
- Optional haptic feedback

### Startup behavior and safety

- Show on every respring or only once per device boot
- Configurable start delay and display duration
- Tap-to-dismiss and swipe-to-dismiss options
- Full-experience preview and sound-only preview
- Three-strike SpringBoard crash guard to prevent respring loops
- Settings recovery control to clear the crash guard
- Media validation and memory-conscious animated-image frame capping

## Settings control center

**Settings → Dark Boot** includes:

- Master enable switch
- Boot-only or every-respring mode
- Delay and duration controls
- Visual import and validation
- Sound import and validation
- Content mode, entrance, exit, blur, dimming, particles, progress, and accent controls
- Audio routing, volume, ducking, fade, video audio, and haptic controls
- Custom title and subtitle fields
- Preview now and preview sound
- Reset imported media
- Restore defaults and clear crash guard
- Apply changes/respring

## Media storage

Imported user media is stored at:

```text
/var/mobile/Library/Application Support/DarkBoot/
```

Dark-Boot never overwrites Apple boot assets. Uninstalling the tweak does not automatically delete your imported media.

## Rootless package layout

The `.deb` installs:

```text
/var/jb/Library/MobileSubstrate/DynamicLibraries/DarkBoot.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/DarkBoot.plist
/var/jb/Library/PreferenceBundles/DarkBootPrefs.bundle/
/var/jb/Library/PreferenceLoader/Preferences/DarkBoot.plist
```

The package also includes executable `postinst` and `prerm` maintainer scripts. The `postinst` script creates the media directory with mobile ownership, refreshes Settings, and triggers `sbreload`.

## Build and CI validation

The GitHub Actions workflow builds and validates the production rootless package. It checks:

- `DarkBoot.dylib`
- `DarkBootPrefs.bundle`
- PreferenceLoader registration
- Executable `postinst` and `prerm` scripts
- Package version `2.0.0`
- Architecture `iphoneos-arm64`

Artifact name:

```text
Dark-Boot-2.0-rootless-deb
```

### Local Theos build

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```

## Known limitations

- Dark-Boot cannot replace the Apple logo presented by iBoot before iOS userspace starts.
- Very large animated files can increase memory use on older devices. Reasonably sized media is recommended, especially on the 2 GB iPad 5th generation.
- PreferenceLoader is required and is declared as a package dependency.

## Version

- Dark-Boot: `2.0.0`
- Package: `com.nightvibes33.darkboot`
- Architecture: `iphoneos-arm64`
- Minimum firmware: `iOS 15.0`
- Repository: https://github.com/NightVibes33/Dark-Boot
