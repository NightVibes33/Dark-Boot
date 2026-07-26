#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        raise RuntimeError(f"expected source block not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1))


def patch_capture() -> None:
    path = ROOT / "gif2aniprefs/G2ThemeGalleryPart3.inc"
    old = '''static NSString *G2RunToolCapture(NSArray<NSString *> *candidates,
                                  NSArray<NSString *> *arguments,
                                  int *exitCode) {
    NSString *capturePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"gif2ani-capture-%@.txt", [[NSUUID UUID] UUIDString]]];
    for (NSString *tool in candidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) continue;
        NSUInteger argc = arguments.count + 2;
        char **argv = calloc(argc, sizeof(char *));
        if (!argv) return nil;
        argv[0] = strdup(tool.lastPathComponent.UTF8String);
        for (NSUInteger i = 0; i < arguments.count; i++) argv[i+1] = strdup(arguments[i].UTF8String);
        argv[argc-1] = NULL;

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, capturePath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_TRUNC, 0600);
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
        pid_t pid = 0;
        int spawnResult = posix_spawn(&pid, tool.fileSystemRepresentation, &actions, NULL, argv, environ);
        posix_spawn_file_actions_destroy(&actions);
        for (NSUInteger i = 0; i < argc-1; i++) free(argv[i]);
        free(argv);
        if (spawnResult != 0) continue;
        int status = 0;
        int code = -1;
        if (waitpid(pid, &status, 0) == pid && WIFEXITED(status)) code = WEXITSTATUS(status);
        NSData *data = [NSData dataWithContentsOfFile:capturePath];
        [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
        if (exitCode) *exitCode = code;
        return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    }
    [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
    if (exitCode) *exitCode = -1;
    return nil;
}
'''
    new = '''static NSString *G2RunToolCapture(NSArray<NSString *> *candidates,
                                  NSArray<NSString *> *arguments,
                                  int *exitCode) {
    NSString *token = [[NSUUID UUID] UUIDString];
    NSString *capturePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"gif2ani-capture-%@.txt", token]];
    NSString *errorPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"gif2ani-stderr-%@.txt", token]];
    for (NSString *tool in candidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) continue;
        NSUInteger argc = arguments.count + 2;
        char **argv = calloc(argc, sizeof(char *));
        if (!argv) return nil;
        argv[0] = strdup(tool.lastPathComponent.UTF8String);
        for (NSUInteger i = 0; i < arguments.count; i++) argv[i+1] = strdup(arguments[i].UTF8String);
        argv[argc-1] = NULL;

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, capturePath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_TRUNC, 0600);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, errorPath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_TRUNC, 0600);
        pid_t pid = 0;
        int spawnResult = posix_spawn(&pid, tool.fileSystemRepresentation, &actions, NULL, argv, environ);
        posix_spawn_file_actions_destroy(&actions);
        for (NSUInteger i = 0; i < argc-1; i++) free(argv[i]);
        free(argv);
        if (spawnResult != 0) continue;
        int status = 0;
        int code = -1;
        if (waitpid(pid, &status, 0) == pid && WIFEXITED(status)) code = WEXITSTATUS(status);
        NSData *data = [NSData dataWithContentsOfFile:capturePath];
        [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:errorPath error:nil];
        if (exitCode) *exitCode = code;
        return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    }
    [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:errorPath error:nil];
    if (exitCode) *exitCode = -1;
    return nil;
}
'''
    replace_once(path, old, new, "gif2ani-stderr-%@.txt")


def patch_package_validation() -> None:
    path = ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc"
    old = '''        if (!error) {
            int code = -1;
            NSString *packageID = [G2RunToolCapture(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-f", debPath, @"Package"], &code) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (code != 0 || ![packageID isEqualToString:pack[@"package"]]) error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:76 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded DEB package identifier does not match the selected theme."}];
        }
'''
    new = '''        if (!error) {
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
    replace_once(path, old, new, "Expected %@, received %@")


def patch_root_plist() -> None:
    path = ROOT / "gif2aniprefs/Resources/Root.plist"
    text = path.read_text()
    text = text.replace("GIF2ANI 3.5.6", "GIF2ANI 3.5.7")
    text = text.replace(
        "Expanded verified Springy and SnowBoard gallery: 12 offline, 54 pinned CC0 downloads, and 48 original Springy pack downloads. Nothing contacts BackBoard until you explicitly tap Apply and Respring.",
        "Expanded verified gallery: 12 offline animations, 54 pinned CC0 downloads, 48 original Springy pack downloads, and 160 verified SnowBoard respring themes. Nothing contacts BackBoard until you explicitly tap Apply and Respring.",
    )
    text = text.replace("114-THEME ANIMATION GALLERY", "274-THEME ANIMATION GALLERY")
    text = text.replace(
        "Tap any downloadable theme to fetch its verified original file, preview it, and stage it. Then return here to choose scaling, background, repeat, and duration before Apply. The 48 Springy DEBs are extracted for animation media only; the old packages are never installed.",
        "Tap any downloadable theme to fetch its verified original file, preview it, and stage it. Then return here to choose scaling, background, repeat, and duration before Apply. The 48 Springy packs and 160 SnowBoard themes are extracted for respring artwork only; the original packages are never installed.",
    )
    path.write_text(text)


def patch_control() -> None:
    path = ROOT / "control"
    lines = path.read_text().splitlines()
    description = (
        "Description: Crash-safe custom respring animations for BackBoard on rootless iOS 15 and 16. "
        "Gif2Ani 3.5.7 fixes the shared Springy and SnowBoard downloader by capturing dpkg-deb stdout separately from warnings on stderr, so valid legacy packages with control warnings no longer fail package-identity verification. "
        "It provides 274 first-class themes: 12 offline animations, 54 pinned CC0 downloads, 48 verified Springy packs, and 160 verified SnowBoard respring themes from seven source-backed packages. "
        "Every source DEB is checked by HTTPS source, byte limit, SHA-256, real package ID, safe archive paths, extracted size, file count, and artwork presence before only the selected animation media is staged; original packages are never installed."
    )
    out = []
    for line in lines:
        if line.startswith("Version:"):
            out.append("Version: 3.5.7")
        elif line.startswith("Description:"):
            out.append(description)
        else:
            out.append(line)
    path.write_text("\n".join(out) + "\n")


def verify() -> None:
    part3 = (ROOT / "gif2aniprefs/G2ThemeGalleryPart3.inc").read_text()
    library = (ROOT / "gif2aniprefs/G2OpenThemeLibrary.inc").read_text()
    root = (ROOT / "gif2aniprefs/Resources/Root.plist").read_text()
    control = (ROOT / "control").read_text()
    assert "posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)" not in part3
    assert "posix_spawn_file_actions_addopen(&actions, STDERR_FILENO" in part3
    assert "gif2ani-stderr-%@.txt" in part3
    assert "Expected %@, received %@" in library
    assert "pack[@\"package\"]" in library
    assert "274-THEME ANIMATION GALLERY" in root
    assert "GIF2ANI 3.5.7" in root
    assert "Version: 3.5.7" in control
    print("gif2ani_357_shared_package_verifier_fix=success")
    print("gallery_theme_count_label=274")


def main() -> None:
    patch_capture()
    patch_package_validation()
    patch_root_plist()
    patch_control()
    verify()


if __name__ == "__main__":
    main()
