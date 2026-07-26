#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing {label}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    output, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"missing {label}; matches={count}")
    return output


def patch_tools() -> None:
    path = ROOT / "gif2aniprefs/G2ThemeGalleryPart3.inc"
    text = path.read_text()
    text = replace_once(
        text,
        "static int G2RunTool(NSArray<NSString *> *candidates, NSArray<NSString *> *arguments) {\n    for (NSString *tool in candidates) {",
        """static void G2PrepareRootlessToolEnvironment(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        setenv(\"PATH\", \"/var/jb/usr/bin:/var/jb/usr/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin\", 1);
        setenv(\"HOME\", \"/var/mobile\", 1);
        setenv(\"TMPDIR\", \"/tmp\", 1);
        setenv(\"LC_ALL\", \"C\", 1);
    });
}

static int G2RunTool(NSArray<NSString *> *candidates, NSArray<NSString *> *arguments) {
    G2PrepareRootlessToolEnvironment();
    for (NSString *tool in candidates) {""",
        "G2RunTool insertion",
    )
    if "G2PrepareRootlessToolEnvironment();\n    NSString *token" not in text:
        text = text.replace(
            "int *exitCode) {\n    NSString *token = [[NSUUID UUID] UUIDString];",
            "int *exitCode) {\n    G2PrepareRootlessToolEnvironment();\n    NSString *token = [[NSUUID UUID] UUIDString];",
            1,
        )
    text = text.replace(
        'NSLocalizedDescriptionKey:@"The archive could not be inspected safely before extraction."',
        'NSLocalizedDescriptionKey:[NSString stringWithFormat:@"The archive could not be inspected safely before extraction (dpkg-deb exit %d).", code]',
    )
    path.write_text(text)


def patch_previews() -> None:
    path = ROOT / "gif2aniprefs/G2RemoteThemePreviewOverride.inc"
    text = path.read_text()
    helper_marker = "G2BundledThemePreviewAnimationPath"
    if helper_marker not in text:
        anchor = '''static UIImage *G2BundledThemePreview(NSDictionary *pack) {
    NSString *identifier = [pack[@"identifier"] isKindOfClass:NSString.class] ? pack[@"identifier"] : pack[@"package"];
    if (!identifier.length) return nil;
    NSURL *url = [G2ThemeGalleryBundle() URLForResource:identifier withExtension:@"png" subdirectory:@"ThemePreviews"];
    return url.path.length ? [UIImage imageWithContentsOfFile:url.path] : nil;
}
'''
        addition = anchor + '''
static NSString *G2BundledThemePreviewAnimationPath(NSDictionary *pack) {
    NSString *identifier = [pack[@"identifier"] isKindOfClass:NSString.class] ? pack[@"identifier"] : pack[@"package"];
    if (!identifier.length) return nil;
    NSURL *url = [G2ThemeGalleryBundle() URLForResource:identifier withExtension:@"gif" subdirectory:@"ThemePreviewAnimations"];
    return url.path.length ? url.path : nil;
}

static NSArray<UIImage *> *G2BundledThemePreviewAnimationFrames(NSDictionary *pack) {
    NSString *path = G2BundledThemePreviewAnimationPath(pack);
    return path.length ? G2FramesFromGIF(path, 400) : @[];
}
'''
        text = replace_once(text, anchor, addition, "animated preview helpers")

    if "g2_showBundledAnimatedDownloadPreview" not in text:
        anchor = '''- (void)g2_remoteLoadPreview {
    NSUInteger generation = ++self.previewGeneration;
'''
        addition = '''- (BOOL)g2_showBundledAnimatedDownloadPreview {
    NSString *path = G2BundledThemePreviewAnimationPath(self.pack);
    NSArray<UIImage *> *frames = G2BundledThemePreviewAnimationFrames(self.pack);
    if (!path.length || frames.count < 2) return NO;
    self.frames = frames;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.animationImages = frames;
    self.imageView.animationDuration = MAX(0.8, G2NaturalGIFDuration(path));
    self.imageView.animationRepeatCount = 0;
    self.imageView.image = frames.firstObject;
    [self.imageView startAnimating];
    return YES;
}

''' + anchor
        text = replace_once(text, anchor, addition, "animated preview method")

    remote_replacement = '''        if (!G2RemoteCachedThemeIsValid(pack)) {
            [self.activity stopAnimating];
            BOOL animatedPreview = [self g2_showBundledAnimatedDownloadPreview];
            if (!animatedPreview) {
                self.frames = @[];
                UIImage *bundledPreview = G2BundledThemePreview(pack);
                self.imageView.contentMode = bundledPreview ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
                self.imageView.tintColor = self.view.tintColor;
                self.imageView.image = bundledPreview ?: [UIImage systemImageNamed:@"icloud.and.arrow.down.fill"];
            }
            self.statusLabel.text = animatedPreview
                ? @"Animated bounded preview • full CC0 theme not downloaded yet\\nTap Download & Preview. The original GIF byte count, SHA-256, and animation structure are verified before it is cached."
                : @"Built-in catalog theme • not downloaded yet\\nTap Download & Preview. The GIF byte count, SHA-256, and animation structure are verified before it is cached.";
            [self.stageButton setTitle:@"Download & Preview" forState:UIControlStateNormal];
            self.stageButton.enabled = YES;
            self.stageButton.alpha = 1.0;
            return;
        }
'''
    text = regex_once(
        text,
        r'''        if \(!G2RemoteCachedThemeIsValid\(pack\)\) \{.*?            return;\n        \}\n''',
        remote_replacement,
        "Animated bounded preview • full CC0 theme",
        "remote not-downloaded branch",
    )

    source_replacement = '''        if (!openInfo) {
            [self.activity stopAnimating];
            BOOL animatedPreview = [self g2_showBundledAnimatedDownloadPreview];
            if (!animatedPreview) {
                self.frames = @[];
                UIImage *bundledPreview = G2BundledThemePreview(pack);
                self.imageView.contentMode = bundledPreview ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
                self.imageView.tintColor = self.view.tintColor;
                self.imageView.image = bundledPreview ?: [UIImage systemImageNamed:@"shippingbox.and.arrow.backward.fill"];
            }
            self.statusLabel.text = animatedPreview
                ? [NSString stringWithFormat:@"Animated bounded preview • original pack not downloaded yet\\n%@\\nTap Download & Preview. Gif2Ani verifies bytes, SHA-256, package identity, archive paths, and artwork before caching only this animation.", pack[@"license"] ?: @"Original credits are preserved."]
                : [NSString stringWithFormat:@"Original source pack • not downloaded yet\\n%@\\nTap Download & Preview. Gif2Ani verifies SHA-256 and package identity before extracting only the animation files.", pack[@"license"] ?: @"Original credits are preserved."];
            [self.stageButton setTitle:@"Download & Preview" forState:UIControlStateNormal];
            self.stageButton.enabled = YES;
            self.stageButton.alpha = 1.0;
            return;
        }
'''
    text = regex_once(
        text,
        r'''        if \(!openInfo\) \{.*?            return;\n        \}\n''',
        source_replacement,
        "Animated bounded preview • original pack not downloaded yet",
        "source DEB not-downloaded branch",
    )

    if "bundled-262-animated-download-previews-v359" not in text:
        text = text.replace(
            '    "bundled-real-theme-previews-v352\\0";',
            '    "bundled-real-theme-previews-v352\\0"\n    "bundled-262-animated-download-previews-v359\\0";',
            1,
        )
    path.write_text(text)


def patch_version() -> None:
    control = ROOT / "control"
    lines = control.read_text().splitlines()
    description = (
        "Description: Crash-safe custom respring animations for BackBoard on rootless iOS 15 and 16. "
        "Gif2Ani 3.5.9 fixes the Settings-only archive rejection by giving every spawned jailbreak tool the complete rootless PATH, HOME, TMPDIR, and C locale before dpkg-deb inspection or extraction. "
        "It bundles 262 bounded animated previews for every downloadable catalog entry: 54 CC0 themes, 48 verified Springy packs, and 160 verified SnowBoard respring themes. "
        "Full packages remain protected by pinned HTTPS source, exact byte count, SHA-256, package identity, safe archive paths, extracted size, file count, and selected artwork checks. "
        "The gallery contains 274 themes total, including 12 offline animations."
    )
    output = []
    for line in lines:
        if line.startswith("Version:"):
            output.append("Version: 3.5.9")
        elif line.startswith("Description:"):
            output.append(description)
        else:
            output.append(line)
    control.write_text("\n".join(output) + "\n")

    root = ROOT / "gif2aniprefs/Resources/Root.plist"
    text = root.read_text().replace("GIF2ANI 3.5.8", "GIF2ANI 3.5.9")
    text = text.replace(
        "Expanded verified gallery: 12 offline animations, 54 pinned CC0 downloads, 48 original Springy pack downloads, and 160 verified SnowBoard respring themes. Nothing contacts BackBoard until you explicitly tap Apply and Respring.",
        "Expanded verified gallery with animated previews: 12 offline animations, 54 pinned CC0 downloads, 48 original Springy packs, and 160 verified SnowBoard respring themes. Nothing contacts BackBoard until you explicitly tap Apply and Respring.",
    )
    root.write_text(text)


def verify() -> None:
    part3 = (ROOT / "gif2aniprefs/G2ThemeGalleryPart3.inc").read_text()
    remote = (ROOT / "gif2aniprefs/G2RemoteThemePreviewOverride.inc").read_text()
    control = (ROOT / "control").read_text()
    root = (ROOT / "gif2aniprefs/Resources/Root.plist").read_text()
    assert part3.count("G2PrepareRootlessToolEnvironment();") >= 2
    assert 'setenv("PATH", "/var/jb/usr/bin:' in part3
    assert "ThemePreviewAnimations" in remote
    assert "bundled-262-animated-download-previews-v359" in remote
    assert "Animated bounded preview • original pack not downloaded yet" in remote
    assert "Version: 3.5.9" in control
    assert "GIF2ANI 3.5.9" in root
    print("gif2ani_359_rootless_archive_environment=success")
    print("gif2ani_359_animated_preview_runtime=success")


def main() -> None:
    patch_tools()
    patch_previews()
    patch_version()
    verify()


if __name__ == "__main__":
    main()
