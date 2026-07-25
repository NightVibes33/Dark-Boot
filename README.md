# Dark-Boot

Dark-Boot is a rootless iOS tweak that attempts to display a custom full-screen visual and play optional audio when SpringBoard starts.

> [!IMPORTANT]
> Dark-Boot does **not** replace the Apple logo shown by iBoot. It runs only after iOS userspace and SpringBoard have started. It does not modify the bootchain, the sealed system volume, or Apple boot assets.

## Current status

### Version 2.0.1

Dark-Boot 2.0.1 fixes the blank Settings page shipped in 2.0.0.

The 2.0.0 package used an invalid PreferenceLoader specifier structure: `Root.plist` had a top-level array instead of a dictionary containing an `items` array. The Settings entry appeared, but opening it returned an empty page.

Version 2.0.1 changes that structure and has been verified on the connected iPad to install:

- Package version `2.0.1`
- `iphoneos-arm64` architecture
- Rootless tweak files under `/var/jb`
- A PreferenceLoader entry for **Settings → Dark Boot**
- A Settings bundle containing 45 installed specifiers
- Import, preview, reset, and respring controls in the installed `Root.plist`

This verification proves that the Settings controls are physically installed and loadable. It does **not** by itself prove that every visual, audio, media-import, or animation option works correctly on the device. Those behaviors require direct on-device testing.

## Verified device

The installation and Settings structure were checked on:

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11 (`20H360`)
- palera1n rootless
- Procursus bootstrap at `/var/jb`
- ARM64

## Installation

Install the latest successful package:

```text
com.nightvibes33.darkboot_2.0.1_iphoneos-arm64.deb
```

Using Sileo, Zebra, Filza, or a terminal:

```sh
sudo dpkg -i com.nightvibes33.darkboot_2.0.1_iphoneos-arm64.deb
```

The package post-install script closes Settings and starts `sbreload`. After SpringBoard returns, fully close Settings, reopen it, and open:

```text
Settings → Dark Boot
```

## Settings controls included in 2.0.1

The installed Settings pane contains controls for:

- Enabling or disabling Dark-Boot
- Showing after every respring or once per device boot
- Startup delay and display duration
- Image scaling and entrance/exit animation choices
- Accent color, dimming, blur, particles, and progress display
- Custom title and subtitle text
- Startup sound, volume, audio routing, fade, video audio, and haptics
- Tap and swipe dismissal
- Importing visual media and startup audio
- Full preview and sound-only preview
- Resetting imported media
- Crash-guard recovery and respring

These controls are verified as present in the installed package. Their runtime behavior must be validated individually on the target iPad.

## Runtime features implemented in source

The source currently contains code paths for:

- PNG, JPEG, HEIC, GIF/APNG, MP4, MOV, and M4V visuals
- Static and animated image display
- Looping video playback
- Custom audio playback through `AVAudioPlayer`
- Built-in fallback visual and system chime
- Entrance and exit animations
- Progress, blur, dimming, particles, and branding layers
- Boot-only and every-respring modes
- Tap/swipe dismissal
- A rapid-restart crash guard

These are implementation claims, not blanket on-device verification claims. A feature should be considered verified only after its corresponding Settings action is tested successfully on the iPad.

## Media storage

Imported media is stored at:

```text
/var/mobile/Library/Application Support/DarkBoot/
```

Dark-Boot does not overwrite Apple boot assets. Removing the package does not automatically remove imported media.

## Rootless package layout

```text
/var/jb/Library/MobileSubstrate/DynamicLibraries/DarkBoot.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/DarkBoot.plist
/var/jb/Library/PreferenceBundles/DarkBootPrefs.bundle/
/var/jb/Library/PreferenceLoader/Preferences/DarkBoot.plist
```

## CI validation

The GitHub Actions build for 2.0.1 validates:

- Package ID and version
- `iphoneos-arm64` architecture
- Rootless tweak and preference paths
- Executable `postinst` and `prerm` scripts
- A parseable packaged `Root.plist`
- A dictionary containing an `items` array
- At least 35 Settings specifiers
- Required import, preview, and respring controls

CI cannot prove that SpringBoard renders the overlay correctly on a physical device.

## Known limitations

- It cannot replace the Apple/iBoot logo.
- The overlay begins only after SpringBoard launches.
- Large GIFs or videos can pressure memory on the 2 GB iPad 5th generation.
- PreferenceLoader and a compatible rootless tweak-injection framework are required.
- Version 2.0.0 has a broken blank Settings pane and should not be used.
- Runtime media, animation, and audio behavior is still being validated on the target iPad.

## Version

- Current package: `2.0.1`
- Package ID: `com.nightvibes33.darkboot`
- Architecture: `iphoneos-arm64`
- Minimum firmware target: iOS 15.0
- Repository: https://github.com/NightVibes33/Dark-Boot
