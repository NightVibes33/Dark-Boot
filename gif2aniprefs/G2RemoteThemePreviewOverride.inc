#import <objc/runtime.h>

static BOOL G2RemoteCachedThemeIsValid(NSDictionary *pack) {
    NSString *path = G2RemoteThemeCachePath(pack);
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || !G2ValidateGIFData(data, nil)) {
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
    if ([kind isEqualToString:@"remote"]) {
        if (!G2RemoteCachedThemeIsValid(pack)) {
            [self.activity stopAnimating];
            self.frames = @[];
            self.imageView.contentMode = UIViewContentModeCenter;
            self.imageView.tintColor = self.view.tintColor;
            self.imageView.image = [UIImage systemImageNamed:@"icloud.and.arrow.down.fill"];
            self.statusLabel.text = @"Built-in catalog theme • not downloaded yet\nTap Download & Preview. The GIF is validated before it is cached.";
            [self.stageButton setTitle:@"Download & Preview" forState:UIControlStateNormal];
            self.stageButton.enabled = YES;
            self.stageButton.alpha = 1.0;
            return;
        }
        remotePath = G2RemoteThemeCachePath(pack);
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSArray<UIImage *> *frames = nil;
            NSString *previewPath = nil;
            if ([kind isEqualToString:@"builtin"]) {
                frames = G2BuiltInFrames(pack[@"style"], CGSizeMake(300,300));
            } else if ([kind isEqualToString:@"remote"]) {
                previewPath = remotePath;
                frames = G2FramesFromGIF(previewPath, 400);
            } else if ([kind isEqualToString:@"gif"]) {
                previewPath = pack[@"path"];
                frames = G2FramesFromGIF(previewPath, 400);
            } else if ([kind isEqualToString:@"frames"]) {
                frames = G2FramesFromDirectory(pack[@"path"], 400);
            }
            NSTimeInterval duration = previewPath.length ? G2NaturalGIFDuration(previewPath) : (frames.count * 0.08);
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
                    NSString *source = [kind isEqualToString:@"remote"] ? @"downloaded and validated" : @"ready";
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
    NSString *urlString = self.pack[@"downloadURL"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!G2RemoteThemeURLIsAllowed(url)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download blocked"
            message:@"This theme does not point to the pinned Gif2Ani catalog host."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    self.statusLabel.text = @"Downloading from the pinned Gif2Ani catalog…";
    [self.activity startAnimating];

    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 45.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSDictionary *pack = self.pack;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSError *error = networkError;
        BOOL success = NO;
        NSURL *finalURL = response.URL;
        NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!error && (!G2RemoteThemeURLIsAllowed(finalURL) || statusCode != 200)) {
            error = [NSError errorWithDomain:@"Gif2AniGallery" code:40 userInfo:@{
                NSLocalizedDescriptionKey:@"The catalog server returned an unexpected response or redirect."
            }];
        }
        NSDictionary *metadata = nil;
        if (!error) metadata = G2ValidateGIFData(data, &error);
        if (!error && metadata) {
            NSFileManager *manager = [NSFileManager defaultManager];
            NSString *cachePath = G2RemoteThemeCachePath(pack);
            NSString *temporary = [cachePath stringByAppendingString:@".download"];
            if (![manager createDirectoryAtPath:G2RemoteThemeCacheDirectory
                      withIntermediateDirectories:YES
                                       attributes:@{NSFilePosixPermissions:@0755}
                                            error:&error]) {
                success = NO;
            } else {
                [manager removeItemAtPath:temporary error:nil];
                [manager removeItemAtPath:cachePath error:nil];
                if ([data writeToFile:temporary options:NSDataWritingAtomic error:&error] &&
                    [manager moveItemAtPath:temporary toPath:cachePath error:&error]) {
                    chown(cachePath.fileSystemRepresentation, 501, 501);
                    chmod(cachePath.fileSystemRepresentation, 0644);
                    success = G2RemoteCachedThemeIsValid(pack);
                    if (!success && !error) {
                        error = [NSError errorWithDomain:@"Gif2AniGallery" code:41 userInfo:@{
                            NSLocalizedDescriptionKey:@"The downloaded GIF failed its final cache verification."
                        }];
                    }
                }
                [manager removeItemAtPath:temporary error:nil];
            }
        }
        [session finishTasksAndInvalidate];

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
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download failed"
                    message:error.localizedDescription ?: @"The theme could not be downloaded safely."
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
    [task resume];
}

- (void)g2_remoteStageAnimation {
    NSString *kind = self.pack[@"kind"];
    if ([kind isEqualToString:@"remote"] && !G2RemoteCachedThemeIsValid(self.pack)) {
        [self g2_downloadRemoteTheme];
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
