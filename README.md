# Dark-Boot 2.0

Dark-Boot is a production-grade rootless iOS 15/16 startup visual and audio engine for SpringBoard.

## Verified target

- iPad 5th generation (`iPad6,11`)
- iOS 16.7.11 (`20H360`)
- palera1n rootless
- Procursus bootstrap at `/var/jb`
- ElleKit injection
- `iphoneos-arm64`

## Install experience

Install `com.nightvibes33.darkboot_2.0.0_iphoneos-arm64.deb` using Sileo, Zebra, Filza, or `dpkg`.

The package's executable `postinst` script automatically:

1. Creates and permissions the Dark-Boot media directory.
2. Terminates the Preferences app so PreferenceLoader discovers the new pane.
3. Resprings after package configuration completes.

After installation, open **Settings → Dark Boot**. No terminal commands, manual preference-cache cleanup, or separate companion app are required.

## Production features

### Visual engine

- Static PNG, JPEG, HEIC, and other ImageIO-supported images
- Animated GIF and APNG playback with frame limits for the 2 GB iPad
- Looping MP4, MOV, and M4V video backgrounds
- Aspect Fill, Aspect Fit, and Stretch scaling
- Cinematic, Fade, Zoom, Pulse, and Slide entrance animations
- Fade, Zoom, Shrink, and Slide exit animations
- Adjustable dimming and blur
- Accent-color system
- Particle effects
- Animated progress bar
- Custom title, subtitle, title size, and text position
- Built-in cinematic gradient/orb visual when no media is imported

### Audio engine

- WAV, CAF, MP3, M4A, AAC, AIFF, and AVAudioPlayer-compatible formats
- Independent custom sound and video-audio controls
- Volume control
- Silent-switch behavior
- Ducking/mixing control
- Exit fade
- Optional start haptic
- Built-in fallback chime

### Trigger and interaction controls

- Show after every respring or only once per physical boot
- Adjustable startup delay and display duration
- Keep-screen-awake protection
- Tap and swipe dismissal
- Full-experience preview and sound-only preview from Settings

### Safety

- Three-strike SpringBoard crash guard
- Active-session marker recovery
- Media file-size limits
- Video-duration validation
- Memory-conscious static-image conversion
- Animated-image frame cap
- Safety-mode reset from Settings
- No modification of iBoot, bootchain assets, or the sealed system volume

## Media storage

Imported files are stored under:

```text
/var/mobile/Library/Application Support/DarkBoot/
```

Dark-Boot never overwrites Apple boot assets.

## Build verification

GitHub Actions validates that the final package contains:

- Rootless `DarkBoot.dylib` and injection filter
- `DarkBootPrefs.bundle`
- PreferenceLoader registration
- Version `2.0.0`
- Executable `postinst` and `prerm` maintainer scripts
- Automatic Preferences refresh and `sbreload` logic

Local build:

```sh
export THEOS=/opt/theos
make clean package FINALPACKAGE=1
```
