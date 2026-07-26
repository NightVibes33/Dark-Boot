#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
control = root / "control"
remote = root / "gif2aniprefs/G2RemoteThemePreviewOverride.inc"
openlib = root / "gif2aniprefs/G2OpenThemeLibrary.inc"
modern = root / "gif2aniprefs/G2ModernGallery.inc"

text = control.read_text()
text = re.sub(r"(?m)^Version: .+$", "Version: 3.5.2", text, count=1)
control.write_text(text)

r = remote.read_text()
anchor = "#import <CommonCrypto/CommonDigest.h>\n"
helper = r'''

__attribute__((used)) static const char G2DownloadPreviewFixMarkers[] =
    "curl-backed-gallery-download-v352\0"
    "bundled-real-theme-previews-v352\0";

static UIImage *G2BundledThemePreview(NSDictionary *pack) {
    NSString *identifier = [pack[@"identifier"] isKindOfClass:NSString.class] ? pack[@"identifier"] : pack[@"package"];
    if (!identifier.length) return nil;
    NSURL *url = [G2ThemeGalleryBundle() URLForResource:identifier withExtension:@"png" subdirectory:@"ThemePreviews"];
    return url.path.length ? [UIImage imageWithContentsOfFile:url.path] : nil;
}

static NSData *G2CurlDownloadData(NSURL *url, BOOL openTheme, unsigned long long maximumBytes, NSError **error) {
    if (!url || !url.absoluteString.length) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniDownload" code:90 userInfo:@{NSLocalizedDescriptionKey:@"The theme URL is missing."}];
        return nil;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:G2MediaDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    NSString *output = [G2MediaDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".curl-%@.download", NSUUID.UUID.UUIDString]];
    int code = -1;
    NSString *effective = G2RunToolCapture(@[@"/var/jb/usr/bin/curl", @"/usr/bin/curl"], @[
        @"--fail", @"--location", @"--silent", @"--show-error", @"--retry", @"3",
        @"--connect-timeout", @"20", @"--max-time", @"180",
        @"--output", output, @"--write-out", @"%{url_effective}", url.absoluteString
    ], &code);
    NSString *trimmed = [effective stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *finalURL = [NSURL URLWithString:trimmed];
    BOOL allowed = openTheme ? G2OpenThemeURLIsAllowed(finalURL, NO) : G2RemoteThemeURLIsAllowed(finalURL);
    if (code != 0 || !allowed) {
        [manager removeItemAtPath:output error:nil];
        NSString *detail = trimmed.length && code != 0 ? trimmed : @"The verified download command failed or was redirected outside its pinned source.";
        if (error) *error = [NSError errorWithDomain:@"Gif2AniDownload" code:91 userInfo:@{NSLocalizedDescriptionKey:detail}];
        return nil;
    }
    NSDictionary *attributes = [manager attributesOfItemAtPath:output error:nil];
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    if (!size || size > maximumBytes) {
        [manager removeItemAtPath:output error:nil];
        if (error) *error = [NSError errorWithDomain:@"Gif2AniDownload" code:92 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded file is empty or exceeds the safe size limit."}];
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:output options:NSDataReadingMappedIfSafe error:error];
    [manager removeItemAtPath:output error:nil];
    return data;
}
'''
if "curl-backed-gallery-download-v352" not in r:
    if anchor not in r:
        raise SystemExit("remote import anchor missing")
    r = r.replace(anchor, anchor + helper, 1)

r = r.replace('self.imageView.contentMode = UIViewContentModeCenter;\n            self.imageView.tintColor = self.view.tintColor;\n            self.imageView.image = [UIImage systemImageNamed:@"icloud.and.arrow.down.fill"];',
'''UIImage *bundledPreview = G2BundledThemePreview(pack);
            self.imageView.contentMode = bundledPreview ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
            self.imageView.tintColor = self.view.tintColor;
            self.imageView.image = bundledPreview ?: [UIImage systemImageNamed:@"icloud.and.arrow.down.fill"];''', 1)
r = r.replace('self.imageView.contentMode = UIViewContentModeCenter;\n            self.imageView.tintColor = self.view.tintColor;\n            self.imageView.image = [UIImage systemImageNamed:@"shippingbox.and.arrow.backward.fill"];',
'''UIImage *bundledPreview = G2BundledThemePreview(pack);
            self.imageView.contentMode = bundledPreview ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
            self.imageView.tintColor = self.view.tintColor;
            self.imageView.image = bundledPreview ?: [UIImage systemImageNamed:@"shippingbox.and.arrow.backward.fill"];''', 1)

remote_method = r'''- (void)g2_downloadRemoteTheme {
    NSDictionary *pack = self.pack;
    NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
    if (!G2RemoteThemeURLIsAllowed(url)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download blocked" message:@"This theme does not point to the pinned Gif2Ani catalog host." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    self.statusLabel.text = @"Downloading through the verified jailbreak network path…";
    [self.activity startAnimating];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL success = NO;
        NSData *data = G2CurlDownloadData(url, NO, G2MaximumInputBytes, &error);
        NSDictionary *metadata = data ? (G2RemoteDataMatchesManifest(data, pack, &error) ? G2ValidateGIFData(data, &error) : nil) : nil;
        if (metadata && !error) {
            NSFileManager *manager = NSFileManager.defaultManager;
            NSString *cachePath = G2RemoteThemeCachePath(pack);
            NSString *temporary = [cachePath stringByAppendingString:@".download"];
            if ([manager createDirectoryAtPath:G2RemoteThemeCacheDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) {
                [manager removeItemAtPath:temporary error:nil];
                if ([data writeToFile:temporary options:NSDataWritingAtomic error:&error]) {
                    chmod(temporary.fileSystemRepresentation, 0644);
                    chown(temporary.fileSystemRepresentation, 501, 501);
                    [manager removeItemAtPath:cachePath error:nil];
                    if ([manager moveItemAtPath:temporary toPath:cachePath error:&error]) success = G2RemoteCachedThemeIsValid(pack);
                }
                [manager removeItemAtPath:temporary error:nil];
            }
        }
        if (!success && !error) error = [NSError errorWithDomain:@"Gif2AniGallery" code:93 userInfo:@{NSLocalizedDescriptionKey:@"The verified GIF could not be saved to the theme cache."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.activity stopAnimating];
            if (success) {
                [strongSelf loadPreview];
            } else {
                strongSelf.statusLabel.text = error.localizedDescription ?: @"The theme could not be downloaded safely.";
                [strongSelf.stageButton setTitle:@"Retry Download" forState:UIControlStateNormal];
                strongSelf.stageButton.enabled = YES;
                strongSelf.stageButton.alpha = 1.0;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download failed" message:error.localizedDescription ?: @"The theme could not be downloaded safely." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}
'''
pattern = re.compile(r'- \(void\)g2_downloadRemoteTheme \{.*?\n\}\n\n- \(void\)g2_remoteStageAnimation', re.S)
if not pattern.search(r):
    raise SystemExit("remote download method not found")
r = pattern.sub(remote_method + '\n- (void)g2_remoteStageAnimation', r, count=1)
remote.write_text(r)

o = openlib.read_text()
open_method = r'''- (void)g2_downloadOpenTheme {
    NSDictionary *pack = self.pack;
    NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
    if (!G2OpenThemeURLIsAllowed(url, NO)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download blocked" message:@"This pack does not point to the verified original theme repository." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    self.statusLabel.text = @"Downloading the original pack through the verified jailbreak network path…";
    [self.activity startAnimating];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL success = NO;
        unsigned long long expectedMaximum = MIN(G2MaximumArchiveBytes, [pack[@"downloadBytes"] unsignedLongLongValue] + 65536ULL);
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
            NSString *packageID = [G2RunToolCapture(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-f", debPath, @"Package"], &code) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (code != 0 || ![packageID isEqualToString:pack[@"package"]]) error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:76 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded DEB package identifier does not match the selected theme."}];
        }
        if (!error && !G2PreflightArchive(debPath, @"deb", &error)) success = NO;
        if (!error && G2RunTool(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-x", debPath, extractRoot]) != 0) error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:77 userInfo:@{NSLocalizedDescriptionKey:@"The verified theme package could not be extracted."}];
        if (!error && !G2ValidateExtractedTree(extractRoot, &error)) success = NO;
        NSDictionary *candidate = !error ? G2BestAnimationCandidateInTree(extractRoot) : nil;
        if (!error && !candidate) error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:78 userInfo:@{NSLocalizedDescriptionKey:@"The package did not contain a compatible animated GIF or frame sequence."}];
        if (!error) success = G2NormalizeOpenThemeCandidate(candidate, pack, &error);
        [manager removeItemAtPath:work error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.activity stopAnimating];
            if (success) {
                [strongSelf loadPreview];
            } else {
                strongSelf.statusLabel.text = error.localizedDescription ?: @"The source-backed theme could not be downloaded safely.";
                [strongSelf.stageButton setTitle:@"Retry Download" forState:UIControlStateNormal];
                strongSelf.stageButton.enabled = YES;
                strongSelf.stageButton.alpha = 1.0;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download failed" message:error.localizedDescription ?: @"The source-backed theme could not be downloaded safely." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}
'''
pattern2 = re.compile(r'- \(void\)g2_downloadOpenTheme \{.*?\n\}\n\n@end', re.S)
if not pattern2.search(o):
    raise SystemExit("open-theme download method not found")
o = pattern2.sub(open_method + '\n@end', o, count=1)
openlib.write_text(o)

m = modern.read_text()
old = '''else if (([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"]) && state != 1) cell.themeImageView.image = [UIImage systemImageNamed:state == 2 ? @"arrow.triangle.2.circlepath.icloud" : @"icloud.and.arrow.down"];'''
new = '''else if (([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"]) && state != 1) {
            UIImage *bundledPreview = G2BundledThemePreview(pack);
            cell.themeImageView.contentMode = bundledPreview ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
            cell.themeImageView.image = bundledPreview ?: [UIImage systemImageNamed:state == 2 ? @"arrow.triangle.2.circlepath.icloud" : @"icloud.and.arrow.down"];
        }'''
if old not in m:
    raise SystemExit("modern card placeholder branch not found")
m = m.replace(old, new, 1)
modern.write_text(m)

print("Gif2Ani 3.5.2 curl download and real preview source fix applied")
