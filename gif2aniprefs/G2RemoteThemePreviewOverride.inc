#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>


__attribute__((used)) static const char G2DownloadPreviewFixMarkers[] =
    "curl-backed-gallery-download-v352\0"
    "bundled-real-theme-previews-v352\0"
    "bundled-262-animated-download-previews-v359\0";

static UIImage *G2BundledThemePreview(NSDictionary *pack) {
    NSString *identifier = [pack[@"identifier"] isKindOfClass:NSString.class] ? pack[@"identifier"] : pack[@"package"];
    if (!identifier.length) return nil;
    NSURL *url = [G2ThemeGalleryBundle() URLForResource:identifier withExtension:@"png" subdirectory:@"ThemePreviews"];
    return url.path.length ? [UIImage imageWithContentsOfFile:url.path] : nil;
}

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

static NSString *G2SHA256StringForData(NSData *data) {
    if (!data.length || data.length > UINT32_MAX) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    static const char hex[] = "0123456789abcdef";
    char output[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        output[index * 2] = hex[(digest[index] >> 4) & 0x0F];
        output[index * 2 + 1] = hex[digest[index] & 0x0F];
    }
    output[CC_SHA256_DIGEST_LENGTH * 2] = '\0';
    return [NSString stringWithUTF8String:output];
}

static BOOL G2RemoteDataMatchesManifest(NSData *data, NSDictionary *pack, NSError **error) {
    NSNumber *expectedBytes = pack[@"expectedBytes"];
    NSString *expectedSHA256 = [pack[@"sha256"] lowercaseString];
    if (![expectedBytes isKindOfClass:NSNumber.class] || expectedBytes.unsignedLongLongValue == 0 ||
        ![expectedSHA256 isKindOfClass:NSString.class] || expectedSHA256.length != 64) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:42 userInfo:@{
            NSLocalizedDescriptionKey:@"This downloadable theme is missing its pinned integrity metadata."
        }];
        return NO;
    }
    if (data.length != expectedBytes.unsignedLongLongValue) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:43 userInfo:@{
            NSLocalizedDescriptionKey:@"The downloaded theme byte count does not match the pinned manifest."
        }];
        return NO;
    }
    NSString *actualSHA256 = G2SHA256StringForData(data);
    if (!actualSHA256 || ![actualSHA256 isEqualToString:expectedSHA256]) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:44 userInfo:@{
            NSLocalizedDescriptionKey:@"The downloaded theme SHA-256 does not match the pinned manifest."
        }];
        return NO;
    }
    return YES;
}

static BOOL G2RemoteCachedThemeIsValid(NSDictionary *pack) {
    NSString *path = G2RemoteThemeCachePath(pack);
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || !G2RemoteDataMatchesManifest(data, pack, nil) || !G2ValidateGIFData(data, nil)) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return NO;
    }
    return YES;
}

@implementation G2ThemePreviewController (G2RemoteThemeDownload)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = objc_getClass("G2ThemePreviewController");
        Method originalPreview = class_getInstanceMethod(cls, @selector(loadPreview));
        Method remotePreview = class_getInstanceMethod(cls, @selector(g2_remoteLoadPreview));
        Method originalStage = class_getInstanceMethod(cls, @selector(stageAnimation));
        Method remoteStage = class_getInstanceMethod(cls, @selector(g2_remoteStageAnimation));
        NSCAssert(originalPreview && remotePreview && originalStage && remoteStage, @"Gif2Ani remote preview method routing is incomplete");
        method_exchangeImplementations(originalPreview, remotePreview);
        method_exchangeImplementations(originalStage, remoteStage);
    });
}

- (BOOL)g2_showBundledAnimatedDownloadPreview {
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

- (void)g2_remoteLoadPreview {
    NSUInteger generation = ++self.previewGeneration;
    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    [self.stageButton setTitle:@"Stage This Animation" forState:UIControlStateNormal];
    self.statusLabel.text = @"Preparing bounded preview…";
    self.imageView.animationImages = nil;
    [self.imageView stopAnimating];
    [self.activity startAnimating];

    NSDictionary *pack = self.pack;
    NSString *kind = pack[@"kind"];
    NSString *remotePath = nil;
    NSDictionary *openInfo = nil;
    if ([kind isEqualToString:@"remote"]) {
        if (!G2RemoteCachedThemeIsValid(pack)) {
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
                ? @"Animated bounded preview • full CC0 theme not downloaded yet\nTap Download & Preview. The original GIF byte count, SHA-256, and animation structure are verified before it is cached."
                : @"Built-in catalog theme • not downloaded yet\nTap Download & Preview. The GIF byte count, SHA-256, and animation structure are verified before it is cached.";
            [self.stageButton setTitle:@"Download & Preview" forState:UIControlStateNormal];
            self.stageButton.enabled = YES;
            self.stageButton.alpha = 1.0;
            return;
        }
        remotePath = G2RemoteThemeCachePath(pack);
    } else if ([kind isEqualToString:@"sourceDeb"]) {
        openInfo = G2OpenThemeCachedInfo(pack);
        if (!openInfo) {
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
                ? [NSString stringWithFormat:@"Animated bounded preview • original pack not downloaded yet\n%@\nTap Download & Preview. Gif2Ani verifies bytes, SHA-256, package identity, archive paths, and artwork before caching only this animation.", pack[@"license"] ?: @"Original credits are preserved."]
                : [NSString stringWithFormat:@"Original source pack • not downloaded yet\n%@\nTap Download & Preview. Gif2Ani verifies SHA-256 and package identity before extracting only the animation files.", pack[@"license"] ?: @"Original credits are preserved."];
            [self.stageButton setTitle:@"Download & Preview" forState:UIControlStateNormal];
            self.stageButton.enabled = YES;
            self.stageButton.alpha = 1.0;
            return;
        }
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSArray<UIImage *> *frames = nil;
            NSString *previewPath = nil;
            BOOL previewIsGIF = NO;
            if ([kind isEqualToString:@"builtin"]) {
                frames = G2BuiltInFrames(pack[@"style"], CGSizeMake(300,300));
            } else if ([kind isEqualToString:@"remote"]) {
                previewPath = remotePath;
                previewIsGIF = YES;
                frames = G2FramesFromGIF(previewPath, 400);
            } else if ([kind isEqualToString:@"sourceDeb"]) {
                previewPath = openInfo[@"path"];
                previewIsGIF = [openInfo[@"kind"] isEqualToString:@"gif"];
                frames = previewIsGIF ? G2FramesFromGIF(previewPath, 400) : G2FramesFromDirectory(previewPath, 400);
            } else if ([kind isEqualToString:@"gif"]) {
                previewPath = pack[@"path"];
                previewIsGIF = YES;
                frames = G2FramesFromGIF(previewPath, 400);
            } else if ([kind isEqualToString:@"frames"]) {
                previewPath = pack[@"path"];
                frames = G2FramesFromDirectory(previewPath, 400);
            }
            NSTimeInterval duration = previewIsGIF && previewPath.length ? G2NaturalGIFDuration(previewPath) : (frames.count * 0.08);
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf || generation != strongSelf.previewGeneration) return;
                [strongSelf.activity stopAnimating];
                strongSelf.frames = frames ?: @[];
                strongSelf.imageView.contentMode = UIViewContentModeScaleAspectFit;
                if (strongSelf.frames.count > 1) {
                    strongSelf.imageView.animationImages = strongSelf.frames;
                    strongSelf.imageView.animationDuration = MAX(0.8, duration);
                    strongSelf.imageView.animationRepeatCount = 0;
                    strongSelf.imageView.image = strongSelf.frames.firstObject;
                    [strongSelf.imageView startAnimating];
                    NSString *source = @"ready";
                    if ([kind isEqualToString:@"remote"]) source = @"downloaded CC0 theme verified";
                    else if ([kind isEqualToString:@"sourceDeb"]) source = @"original DEB verified and safely extracted";
                    strongSelf.statusLabel.text = [NSString stringWithFormat:
                        @"%lu bounded preview frames • %@\nStage it, then choose scaling, background, repeat, and duration on the main Gif2Ani page before Apply.",
                        (unsigned long)strongSelf.frames.count, source];
                    [strongSelf.stageButton setTitle:@"Stage This Animation" forState:UIControlStateNormal];
                    strongSelf.stageButton.enabled = YES;
                    strongSelf.stageButton.alpha = 1.0;
                } else {
                    strongSelf.imageView.animationImages = nil;
                    strongSelf.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
                    strongSelf.statusLabel.text = @"No safe animation frames were decoded.";
                    if ([kind isEqualToString:@"remote"] && remotePath.length) {
                        [[NSFileManager defaultManager] removeItemAtPath:remotePath error:nil];
                        [strongSelf.stageButton setTitle:@"Download Again" forState:UIControlStateNormal];
                        strongSelf.stageButton.enabled = YES;
                        strongSelf.stageButton.alpha = 1.0;
                    } else if ([kind isEqualToString:@"sourceDeb"]) {
                        [[NSFileManager defaultManager] removeItemAtPath:G2OpenThemePackageDirectory(pack) error:nil];
                        [strongSelf.stageButton setTitle:@"Download Again" forState:UIControlStateNormal];
                        strongSelf.stageButton.enabled = YES;
                        strongSelf.stageButton.alpha = 1.0;
                    } else {
                        strongSelf.stageButton.enabled = NO;
                        strongSelf.stageButton.alpha = 0.45;
                    }
                }
            });
        }
    });
}

- (void)g2_downloadRemoteTheme {
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

- (void)g2_remoteStageAnimation {
    NSString *kind = self.pack[@"kind"];
    if ([kind isEqualToString:@"remote"] && !G2RemoteCachedThemeIsValid(self.pack)) {
        [self g2_downloadRemoteTheme];
        return;
    }
    if ([kind isEqualToString:@"sourceDeb"] && !G2OpenThemeCachedInfo(self.pack)) {
        [self g2_downloadOpenTheme];
        return;
    }

    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    [self.activity startAnimating];
    NSDictionary *pack = self.pack;
    NSArray<UIImage *> *frames = self.frames;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *temporary = [G2MediaDirectory stringByAppendingPathComponent:@"Gallery-generated.gif"];
        [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions:@0755}
                                                        error:&error];
        [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
        BOOL ready = NO;
        NSString *sourcePath = nil;
        if ([kind isEqualToString:@"remote"]) sourcePath = G2RemoteThemeCachePath(pack);
        else if ([kind isEqualToString:@"gif"]) sourcePath = pack[@"path"];
        else if ([kind isEqualToString:@"sourceDeb"]) {
            NSDictionary *info = G2OpenThemeCachedInfo(pack);
            if ([info[@"kind"] isEqualToString:@"gif"]) sourcePath = info[@"path"];
        }

        if (!error && sourcePath.length) {
            ready = G2StageGIFAtPath(sourcePath, pack, &error);
        } else if (!error && frames.count > 1) {
            ready = G2WriteGIF(frames, [NSURL fileURLWithPath:temporary], 0.08, &error);
            if (ready) ready = G2StageGIFAtPath(temporary, pack, &error);
        }
        [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.activity stopAnimating];
            [strongSelf.stageButton setTitle:@"Stage This Animation" forState:UIControlStateNormal];
            strongSelf.stageButton.enabled = YES;
            strongSelf.stageButton.alpha = 1.0;
            NSString *message = ready
                ? @"The animation is staged. Go back, choose scaling, background color, repeat mode, and duration, then tap Apply and Respring."
                : (error.localizedDescription ?: @"The selected theme could not be staged safely.");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:ready ? @"Animation staged" : @"Could not stage animation"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
        });
    });
}

@end
