#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        raise RuntimeError(f"expected source block not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new, 1))


def add_helpers() -> None:
    path = ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc"
    marker = "static NSString *G2CleanDebPackageIDFromOutput"
    if marker in path.read_text():
        return
    insertion = r'''
static NSString *G2CleanDebPackageIDFromOutput(NSString *output) {
    if (![output isKindOfClass:NSString.class] || !output.length) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+.-"];
    for (NSString *rawLine in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!line.length || [line containsString:@".."] || [line hasPrefix:@"."]) continue;
        if (G2StringContainsOnlyCharacters(line, allowed)) return line;
    }
    return nil;
}

static void G2WriteOpenThemePackageVerificationDiagnostic(NSDictionary *pack,
                                                           NSString *actualPackageID,
                                                           int toolExitCode,
                                                           NSString *mode,
                                                           NSString *actualSHA256,
                                                           NSUInteger actualBytes) {
    NSString *root = [G2OpenThemeLibraryRoot stringByDeletingLastPathComponent];
    NSString *path = [root stringByAppendingPathComponent:@"LastPackageVerification.plist"];
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    NSDictionary *record = @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"themeName": [pack[@"name"] isKindOfClass:NSString.class] ? pack[@"name"] : @"",
        @"themeIdentifier": [pack[@"identifier"] isKindOfClass:NSString.class] ? pack[@"identifier"] : @"",
        @"expectedPackage": [pack[@"package"] isKindOfClass:NSString.class] ? pack[@"package"] : @"",
        @"actualPackage": actualPackageID ?: @"",
        @"toolExitCode": @(toolExitCode),
        @"verificationMode": mode ?: @"unknown",
        @"actualSHA256": actualSHA256 ?: @"",
        @"actualBytes": @(actualBytes)
    };
    [record writeToFile:path atomically:YES];
    chown(path.fileSystemRepresentation, 501, 501);
    chmod(path.fileSystemRepresentation, 0644);
}

'''
    needle = "@implementation G2ThemeGalleryController (G2OpenThemeLibrary)\n"
    text = path.read_text()
    if needle not in text:
        raise RuntimeError("open-theme implementation marker not found")
    path.write_text(text.replace(needle, insertion + needle, 1))


def patch_download_verifier() -> None:
    path = ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc"
    old = '''        unsigned long long expectedMaximum = MIN(G2MaximumArchiveBytes, [pack[@"downloadBytes"] unsignedLongLongValue] + 65536ULL);
        NSData *data = G2CurlDownloadData(url, YES, expectedMaximum, &error);
        NSString *actualSHA = data && !error ? G2SHA256ForData(data) : nil;
        if (!error && ![actualSHA isEqualToString:pack[@"sha256"]]) error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:75 userInfo:@{NSLocalizedDescriptionKey:@"SHA-256 verification failed. The package was not opened or cached."}];

        NSFileManager *manager = NSFileManager.defaultManager;
        NSString *work = [G2OpenThemeLibraryRoot stringByAppendingPathComponent:[NSString stringWithFormat:@".download-%@", NSUUID.UUID.UUIDString]];
        NSString *debPath = [work stringByAppendingPathComponent:@"theme.deb"];
        NSString *extractRoot = [work stringByAppendingPathComponent:@"Extracted"];
        if (!error && ![manager createDirectoryAtPath:extractRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) success = NO;
        if (!error && ![data writeToFile:debPath options:NSDataWritingAtomic error:&error]) success = NO;
        if (!error) {
            int code = -1;
            NSString *expectedPackageID = [pack[@"package"] isKindOfClass:NSString.class] ? pack[@"package"] : @"";
            NSString *packageOutput = G2RunToolCapture(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-f", debPath, @"Package"], &code);
            NSString *packageID = [packageOutput stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (code != 0 || !expectedPackageID.length || ![packageID isEqualToString:expectedPackageID]) {
                NSString *actual = packageID.length ? packageID : @"(empty)";
                NSString *expected = expectedPackageID.length ? expectedPackageID : @"(missing catalog package)";
                NSString *message = [NSString stringWithFormat:@"The downloaded DEB package identifier does not match the selected theme. Expected %@, received %@.", expected, actual];
                error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:76 userInfo:@{NSLocalizedDescriptionKey:message}];
            }
        }
'''
    new = '''        NSNumber *expectedBytes = [pack[@"downloadBytes"] isKindOfClass:NSNumber.class] ? pack[@"downloadBytes"] : nil;
        unsigned long long expectedMaximum = MIN(G2MaximumArchiveBytes, expectedBytes.unsignedLongLongValue + 65536ULL);
        NSData *data = G2CurlDownloadData(url, YES, expectedMaximum, &error);
        if (!error && (!expectedBytes || expectedBytes.unsignedLongLongValue == 0 || data.length != expectedBytes.unsignedLongLongValue)) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:74 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded DEB byte count does not match the verified catalog."}];
        }
        NSString *actualSHA = data && !error ? G2SHA256ForData(data) : nil;
        if (!error && ![actualSHA isEqualToString:pack[@"sha256"]]) error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:75 userInfo:@{NSLocalizedDescriptionKey:@"SHA-256 verification failed. The package was not opened or cached."}];

        NSFileManager *manager = NSFileManager.defaultManager;
        NSString *work = [G2OpenThemeLibraryRoot stringByAppendingPathComponent:[NSString stringWithFormat:@".download-%@", NSUUID.UUID.UUIDString]];
        NSString *debPath = [work stringByAppendingPathComponent:@"theme.deb"];
        NSString *extractRoot = [work stringByAppendingPathComponent:@"Extracted"];
        if (!error && ![manager createDirectoryAtPath:extractRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) success = NO;
        if (!error && ![data writeToFile:debPath options:NSDataWritingAtomic error:&error]) success = NO;
        if (!error) {
            int code = -1;
            NSString *expectedPackageID = [pack[@"package"] isKindOfClass:NSString.class] ? pack[@"package"] : @"";
            NSString *packageOutput = G2RunToolCapture(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-f", debPath, @"Package"], &code);
            NSString *packageID = G2CleanDebPackageIDFromOutput(packageOutput);
            NSString *mode = @"sha256-bound-package-identity-fallback-v358";
            if (!expectedPackageID.length) {
                mode = @"catalog-package-missing";
                error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:76 userInfo:@{NSLocalizedDescriptionKey:@"The verified catalog entry is missing its package identifier."}];
            } else if (code == 0 && packageID.length) {
                if ([packageID isEqualToString:expectedPackageID]) {
                    mode = @"strict-package-id-match";
                } else {
                    mode = @"strict-package-id-mismatch";
                    NSString *message = [NSString stringWithFormat:@"The downloaded DEB package identifier does not match the selected theme. Expected %@, received %@.", expectedPackageID, packageID];
                    error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:76 userInfo:@{NSLocalizedDescriptionKey:message}];
                }
            }
            G2WriteOpenThemePackageVerificationDiagnostic(pack, packageID, code, mode, actualSHA, data.length);
        }
'''
    replace_once(path, old, new, "sha256-bound-package-identity-fallback-v358")


def patch_version_and_copy() -> None:
    root = ROOT / "gif2aniprefs/Resources/Root.plist"
    text = root.read_text().replace("GIF2ANI 3.5.7", "GIF2ANI 3.5.8")
    root.write_text(text)

    control = ROOT / "control"
    lines = control.read_text().splitlines()
    description = (
        "Description: Crash-safe custom respring animations for BackBoard on rootless iOS 15 and 16. "
        "Gif2Ani 3.5.8 hardens the shared Springy and SnowBoard downloader: exact source URL, byte count, and SHA-256 bind each downloaded DEB to its audited catalog record; dpkg-deb package metadata is parsed as an additional strict check when available, while a tool-launch or empty-output failure no longer falsely rejects a cryptographically identical package. "
        "A clean real package-ID mismatch remains blocked, and every attempt records its expected ID, actual ID, exit code, hash, byte count, and verification mode in LastPackageVerification.plist. "
        "The gallery contains 274 themes: 12 offline animations, 54 pinned CC0 downloads, 48 verified Springy packs, and 160 verified SnowBoard respring themes."
    )
    out=[]
    for line in lines:
        if line.startswith("Version:"):
            out.append("Version: 3.5.8")
        elif line.startswith("Description:"):
            out.append(description)
        else:
            out.append(line)
    control.write_text("\n".join(out)+"\n")


def verify() -> None:
    library=(ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc").read_text()
    root=(ROOT / "gif2aniprefs/Resources/Root.plist").read_text()
    control=(ROOT / "control").read_text()
    assert "G2CleanDebPackageIDFromOutput" in library
    assert "LastPackageVerification.plist" in library
    assert "sha256-bound-package-identity-fallback-v358" in library
    assert "strict-package-id-mismatch" in library
    assert "data.length != expectedBytes.unsignedLongLongValue" in library
    assert "GIF2ANI 3.5.8" in root
    assert "274-THEME ANIMATION GALLERY" in root
    assert "Version: 3.5.8" in control
    print("gif2ani_358_sha_bound_identity=success")
    print("gallery_total=274")


def main() -> None:
    add_helpers()
    patch_download_verifier()
    patch_version_and_copy()
    verify()


if __name__ == "__main__":
    main()
