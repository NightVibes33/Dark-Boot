#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, marker: str | None = None) -> None:
    text = path.read_text()
    if marker and marker in text:
        return
    if old not in text:
        raise RuntimeError(f"expected source block not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1))


def patch_controller() -> None:
    path = ROOT / "gif2aniprefs/G2ThemeGalleryController.m"
    replace_once(
        path,
        "static NSArray<NSDictionary *> *G2PreferredOpenThemeCatalog(void);\n",
        "static NSArray<NSDictionary *> *G2PreferredOpenThemeCatalog(void);\n"
        "static NSArray<NSDictionary *> *G2BundledSnowBoardCatalog(void);\n",
        "G2BundledSnowBoardCatalog(void);",
    )
    replace_once(
        path,
        "static BOOL G2OpenThemeURLIsAllowed(NSURL *url, BOOL indexURL);\n",
        "static BOOL G2OpenThemeURLIsAllowed(NSURL *url, BOOL indexURL);\n"
        "static BOOL G2SnowBoardThemeURLIsAllowed(NSURL *url);\n",
        "G2SnowBoardThemeURLIsAllowed(NSURL *url);",
    )
    replace_once(
        path,
        '#include "G2BundledOpenThemeCatalog.inc"\n',
        '#include "G2BundledOpenThemeCatalog.inc"\n#include "G2BundledSnowBoardCatalog.inc"\n',
        'include "G2BundledSnowBoardCatalog.inc"',
    )
    old = '''static NSArray<NSDictionary *> *G2PreferredOpenThemeCatalog(void) {
    NSArray<NSDictionary *> *bundled = G2BundledOpenThemeCatalog();
    // The bundled snapshot is independently verified and must be usable even
    // when an older on-device catalog.plist is malformed or stale.
    if (bundled.count >= 48) return bundled;

    NSArray<NSDictionary *> *cached = G2LoadCachedOpenThemeCatalog();
    return cached ?: @[];
}
'''
    new = '''static NSArray<NSDictionary *> *G2PreferredOpenThemeCatalog(void) {
    NSArray<NSDictionary *> *springy = G2BundledOpenThemeCatalog();
    if (springy.count < 48) springy = G2LoadCachedOpenThemeCatalog() ?: @[];
    NSArray<NSDictionary *> *snowboard = G2BundledSnowBoardCatalog();
    NSMutableArray<NSDictionary *> *combined = [NSMutableArray arrayWithCapacity:springy.count + snowboard.count];
    [combined addObjectsFromArray:springy];
    [combined addObjectsFromArray:snowboard];
    return combined.copy;
}
'''
    replace_once(path, old, new, "springy.count + snowboard.count")


def patch_open_library() -> None:
    path = ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc"
    replace_once(
        path,
        '''    if ([host isEqualToString:G2OpenThemePinnedRawHost]) {
        return [path hasPrefix:G2OpenThemePinnedRawPrefix] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
    }
    return NO;
''',
        '''    if ([host isEqualToString:G2OpenThemePinnedRawHost]) {
        return [path hasPrefix:G2OpenThemePinnedRawPrefix] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
    }
    if (G2SnowBoardThemeURLIsAllowed(url)) return YES;
    return NO;
''',
        "G2SnowBoardThemeURLIsAllowed(url)",
    )

    replace_once(
        path,
        '''static NSString *G2OpenThemePackageDirectory(NSDictionary *pack) {
    NSString *package = pack[@"package"];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if (![package hasPrefix:@"io.github.virenmohindra."] || !G2StringContainsOnlyCharacters(package, allowed)) return nil;
    return [G2OpenThemeLibraryRoot stringByAppendingPathComponent:package];
}
''',
        '''static NSString *G2OpenThemePackageDirectory(NSDictionary *pack) {
    NSString *identifier = [pack[@"identifier"] isKindOfClass:NSString.class] ? pack[@"identifier"] : pack[@"package"];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if (!identifier.length || !G2StringContainsOnlyCharacters(identifier, allowed) || [identifier containsString:@".."] || [identifier hasPrefix:@"."]) return nil;
    return [G2OpenThemeLibraryRoot stringByAppendingPathComponent:identifier];
}
''',
        "[pack[@\"identifier\"] isKindOfClass",
    )

    old_loop = '''    for (NSString *directory in directories) {
        NSArray<NSString *> *files = G2NaturallySortedImageFiles(directory);
        if (!files.count) continue;
        for (NSString *file in files) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"gif"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
            if (!G2ValidateGIFData(data, nil)) continue;
            NSInteger score = G2AnimationCandidateScore(file, 1, YES);
            if (score > bestScore) {
                bestScore = score;
                best = @{@"kind":@"gif", @"path":file};
            }
        }
        if (files.count >= 2) {
            NSInteger score = G2AnimationCandidateScore(directory, files.count, NO);
            if (score > bestScore) {
                bestScore = score;
                best = @{@"kind":@"frames", @"path":directory, @"count":@(files.count)};
            }
        }
    }
'''
    new_loop = '''    for (NSString *directory in directories) {
        NSArray<NSString *> *files = G2NaturallySortedImageFiles(directory);
        if (!files.count) continue;
        for (NSString *file in files) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"gif"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
            if (!G2ValidateGIFData(data, nil)) continue;
            NSInteger score = G2AnimationCandidateScore(file, 1, YES);
            if (score > bestScore) {
                bestScore = score;
                best = @{@"kind":@"gif", @"path":file};
            }
        }
        if (files.count >= 2) {
            NSInteger score = G2AnimationCandidateScore(directory, files.count, NO);
            if (score > bestScore) {
                bestScore = score;
                best = @{@"kind":@"frames", @"path":directory, @"count":@(files.count)};
            }
        } else if (files.count == 1 && ![files.firstObject.pathExtension.lowercaseString isEqualToString:@"gif"]) {
            UIImage *image = [UIImage imageWithContentsOfFile:files.firstObject];
            if (image) {
                NSInteger score = G2AnimationCandidateScore(files.firstObject, 1, NO) - 500;
                if (score > bestScore) {
                    bestScore = score;
                    best = @{@"kind":@"still", @"path":files.firstObject, @"count":@1};
                }
            }
        }
    }
'''
    replace_once(path, old_loop, new_loop, '@"kind":@"still"')

    replace_once(
        path,
        '    NSString *kind = candidate[@"kind"];\n    NSString *sourcePath = candidate[@"path"];\n',
        '    NSString *kind = candidate[@"kind"];\n    NSString *normalizedKind = kind;\n    NSString *sourcePath = candidate[@"path"];\n',
        "NSString *normalizedKind = kind;",
    )
    replace_once(
        path,
        '''        if (success) success = G2FramesFromDirectory(destination, 400).count > 1;
        if (!success && error && !*error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:71 userInfo:@{NSLocalizedDescriptionKey:@"The package did not contain at least two usable animation frames."}];
    }

    if (success) {
''',
        '''        if (success) success = G2FramesFromDirectory(destination, 400).count > 1;
        if (!success && error && !*error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:71 userInfo:@{NSLocalizedDescriptionKey:@"The package did not contain at least two usable animation frames."}];
    } else if ([kind isEqualToString:@"still"]) {
        normalizedKind = @"frames";
        relativePath = @"Frames";
        NSString *destination = [staging stringByAppendingPathComponent:relativePath];
        success = [manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error];
        NSString *extension = sourcePath.pathExtension.lowercaseString.length ? sourcePath.pathExtension.lowercaseString : @"png";
        if (success) success = [manager copyItemAtPath:sourcePath toPath:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"0000.%@", extension]] error:error];
        if (success) success = [manager copyItemAtPath:sourcePath toPath:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"0001.%@", extension]] error:error];
        if (success) success = G2FramesFromDirectory(destination, 400).count > 1;
        if (!success && error && !*error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:71 userInfo:@{NSLocalizedDescriptionKey:@"The static respring logo could not be normalized safely."}];
    }

    if (success) {
''',
        "static respring logo could not be normalized",
    )
    replace_once(path, '@"kind": kind ?: @"",\n', '@"kind": normalizedKind ?: @"",\n', "normalizedKind ?: @\"\"")

    replace_once(
        path,
        '        NSDictionary *candidate = !error ? G2BestAnimationCandidateInTree(extractRoot) : nil;\n',
        '''        NSString *candidateRoot = extractRoot;
        NSString *archiveSubpath = [pack[@"archiveSubpath"] isKindOfClass:NSString.class] ? pack[@"archiveSubpath"] : nil;
        if (!error && archiveSubpath.length) {
            if ([archiveSubpath hasPrefix:@"/"] || [archiveSubpath containsString:@".."] || [archiveSubpath containsString:@"\\"]) {
                error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:79 userInfo:@{NSLocalizedDescriptionKey:@"The selected SnowBoard theme path is unsafe."}];
            } else {
                NSString *resolved = [[extractRoot stringByAppendingPathComponent:archiveSubpath] stringByStandardizingPath];
                NSString *prefix = [extractRoot.stringByStandardizingPath stringByAppendingString:@"/"];
                BOOL isDirectory = NO;
                if (![resolved hasPrefix:prefix] || ![manager fileExistsAtPath:resolved isDirectory:&isDirectory] || !isDirectory) {
                    error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:80 userInfo:@{NSLocalizedDescriptionKey:@"The verified SnowBoard subtheme was not present in the downloaded package."}];
                } else {
                    candidateRoot = resolved;
                }
            }
        }
        NSDictionary *candidate = !error ? G2BestAnimationCandidateInTree(candidateRoot) : nil;
''',
        "verified SnowBoard subtheme was not present",
    )

    replace_once(
        path,
        '            if (packs.count) strongSelf.openThemes = packs;\n',
        '''            if (packs.count) {
                NSMutableArray<NSDictionary *> *combined = [packs mutableCopy];
                [combined addObjectsFromArray:G2BundledSnowBoardCatalog()];
                strongSelf.openThemes = combined.copy;
            }
''',
        "[combined addObjectsFromArray:G2BundledSnowBoardCatalog()]",
    )


def patch_legacy_ui() -> None:
    part5 = ROOT / "gif2aniprefs/G2ThemeGalleryPart5.inc"
    replace_once(part5, "    self.legacy = G2LegacyCatalog();\n", "    self.legacy = @[];\n", "self.legacy = @[];")
    text = part5.read_text()
    text = text.replace('return @"Open Source Pack Library";', 'return @"Verified Springy & SnowBoard Library";')
    text = text.replace('Every row downloads its original Springy DEB, verifies SHA-256 and package identity, extracts only safe image content, previews it, and stages it without installing the old package.',
                        'Every row downloads its original verified DEB, checks SHA-256 and package identity, extracts only its selected Springy or SnowBoard respring artwork, previews it, and never installs the old package.')
    part5.write_text(text)

    part6 = ROOT / "gif2aniprefs/G2ThemeGalleryPart6.inc"
    old = '''    if ([pack[@"kind"] isEqualToString:@"legacy"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:pack[@"name"]
                                                                       message:[NSString stringWithFormat:@"%@ is a historical respring package whose current original file or redistribution terms could not be verified. The verified open-source library above is one-tap downloadable; this separate row remains an import/reference fallback.", pack[@"package"]]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Import Pack File" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self importPack]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
'''
    new = '''    if ([pack[@"kind"] isEqualToString:@"legacy"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Source unavailable"
                                                                       message:[NSString stringWithFormat:@"%@ is not in the verified download catalog because no free original public DEB with matching integrity metadata was found. It cannot be imported from this row.", pack[@"package"]]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
'''
    replace_once(part6, old, new, "It cannot be imported from this row")

    modern = ROOT / "gif2aniprefs/G2ModernGallery.inc"
    text = modern.read_text()
    text = text.replace("G2LegacyCatalog()", "@[]")
    text = text.replace('return @"Historical compatibility";', 'return @"Verified source";')
    text = text.replace('Original Springy repository', 'Original verified repository')
    modern.write_text(text)


def patch_version() -> None:
    control = ROOT / "control"
    text = control.read_text()
    text = text.replace("Version: 3.5.5", "Version: 3.5.6")
    if "Version: 3.5.6" not in text:
        raise RuntimeError("control version was not updated")
    control.write_text(text)

    root = ROOT / "gif2aniprefs/Resources/Root.plist"
    text = root.read_text().replace("GIF2ANI 3.5.5", "GIF2ANI 3.5.6")
    if "GIF2ANI 3.5.6" not in text:
        raise RuntimeError("Settings version label was not updated")
    text = text.replace("114 first-class themes", "Expanded verified Springy and SnowBoard gallery")
    root.write_text(text)


def main() -> None:
    patch_controller()
    patch_open_library()
    patch_legacy_ui()
    patch_version()
    print("snowboard_gallery_source_patch=success")


if __name__ == "__main__":
    main()
