#import "gif2ani2RootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <stdio.h>
#import <errno.h>
#import <unistd.h>
#import <math.h>

extern char **environ;

static NSString * const G2PreferencesDomain = @"com.nightvibes33.gif2ani";
static NSString * const G2PreferencesPath = @"/var/mobile/Library/Preferences/com.nightvibes33.gif2ani.plist";
static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2PendingGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Pending.gif";
static NSString * const G2ActiveGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Active.gif";
static NSString * const G2RejectedGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Rejected.gif";
static NSString * const G2LoadSentinelPath = @"/var/mobile/Library/Application Support/Gif2Ani/load-in-progress";
static NSString * const G2PendingMetadataPath = @"/var/mobile/Library/Application Support/Gif2Ani/pending-metadata.plist";
static NSString * const G2RuntimeStatusPath = @"/var/mobile/Library/Application Support/Gif2Ani/runtime-status.plist";
static NSString * const G2ActiveBackupPath = @"/var/mobile/Library/Application Support/Gif2Ani/Active.previous.gif";
static CFStringRef const G2ReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

static const NSUInteger G2MaximumSourceFrames = 240;
static const NSUInteger G2MaximumDecodedFrames = 24;
static const NSUInteger G2MaximumPixelDimension = 640;
static const unsigned long long G2MaximumInputBytes = 25ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumEstimatedDecodedBytes = 48ULL * 1024ULL * 1024ULL;

static NSDictionary *G2DefaultPreferences(void) {
    return @{
        @"isEnabled": @NO,
        @"pendingReady": @NO,
        @"imageTransformation": @"resizeAspect",
        @"customLoop": @(-1.0),
        @"customDuration": @(-1.0),
        @"backgroundColor": @"#000000:1.000",
    };
}

static UIColor *G2ColorFromPreference(NSString *value) {
    NSString *hex = [[value ?: @"#000000" stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    NSArray<NSString *> *parts = [hex componentsSeparatedByString:@":"];
    hex = parts.firstObject;
    CGFloat alpha = parts.count > 1 ? MAX(0.0, MIN(1.0, parts[1].doubleValue)) : 1.0;
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return UIColor.blackColor;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

static NSString *G2PreferenceFromColor(UIColor *color) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 1;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat white = 0;
        [color getWhite:&white alpha:&alpha];
        red = green = blue = white;
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X:%.3f",
            (int)lrint(red * 255.0), (int)lrint(green * 255.0),
            (int)lrint(blue * 255.0), alpha];
}

static id G2NormalizedPreferenceValue(NSString *key, id value) {
    NSDictionary *defaults = G2DefaultPreferences();
    if ([key isEqualToString:@"isEnabled"] || [key isEqualToString:@"pendingReady"]) {
        return @([value boolValue]);
    }
    if ([key isEqualToString:@"imageTransformation"]) {
        NSSet *allowed = [NSSet setWithArray:@[@"resizeAspect", @"resizeAspectFill", @"resize", @"center"]];
        return [allowed containsObject:value] ? value : defaults[key];
    }
    if ([key isEqualToString:@"customLoop"]) {
        double loops = [value doubleValue];
        if (!isfinite(loops) || loops < 0) return @(-1.0);
        return @(MAX(0.0, MIN(10.0, round(loops))));
    }
    if ([key isEqualToString:@"customDuration"]) {
        double duration = [value doubleValue];
        if (!isfinite(duration) || duration < 0) return @(-1.0);
        duration = MAX(0.25, MIN(60.0, round(duration * 4.0) / 4.0));
        return @(duration);
    }
    if ([key isEqualToString:@"backgroundColor"]) {
        return G2PreferenceFromColor(G2ColorFromPreference([value isKindOfClass:NSString.class] ? value : defaults[key]));
    }
    return value ?: defaults[key];
}

static BOOL G2WritePreferences(NSDictionary *updates, NSError **error) {
    NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] mutableCopy];
    if (!preferences) preferences = [NSMutableDictionary dictionary];

    NSDictionary *defaults = G2DefaultPreferences();
    for (NSString *key in defaults) {
        preferences[key] = G2NormalizedPreferenceValue(key, preferences[key] ?: defaults[key]);
    }
    for (NSString *key in updates) {
        preferences[key] = G2NormalizedPreferenceValue(key, updates[key]);
    }

    if (![preferences writeToFile:G2PreferencesPath atomically:YES]) {
        if (error) {
            *error = [NSError errorWithDomain:@"Gif2Ani" code:7 userInfo:@{
                NSLocalizedDescriptionKey: @"The settings could not be written to the real preferences file."
            }];
        }
        return NO;
    }

    chown(G2PreferencesPath.fileSystemRepresentation, 501, 501);
    chmod(G2PreferencesPath.fileSystemRepresentation, 0644);

    for (NSString *key in preferences) {
        id value = preferences[key];
        if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class] ||
            [value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class] ||
            [value isKindOfClass:NSData.class] || [value isKindOfClass:NSDate.class]) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     (__bridge CFPropertyListRef)value,
                                     (__bridge CFStringRef)G2PreferencesDomain);
        }
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);

    NSDictionary *verified = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath];
    for (NSString *key in updates) {
        id expected = preferences[key];
        id actual = verified[key];
        if (![actual isEqual:expected]) {
            if (error) {
                *error = [NSError errorWithDomain:@"Gif2Ani" code:8 userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The %@ setting did not survive verification.", key]
                }];
            }
            return NO;
        }
    }
    return YES;
}

static BOOL G2WriteEnabledPreferences(BOOL enabled, NSError **error) {
    NSMutableDictionary *updates = [@{
        @"isEnabled": @(enabled),
        @"pendingReady": @NO,
    } mutableCopy];
    if (enabled) updates[@"lastAppliedAt"] = @([[NSDate date] timeIntervalSince1970]);
    return G2WritePreferences(updates, error);
}

static BOOL G2RestartProcess(NSString *processName) {
    const char *candidates[] = {"/var/jb/usr/bin/killall", "/usr/bin/killall"};
    for (NSUInteger index = 0; index < 2; index++) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:@(candidates[index])]) continue;

        pid_t pid = 0;
        char *argv[] = {(char *)"killall", (char *)"-9", (char *)processName.UTF8String, NULL};
        if (posix_spawn(&pid, candidates[index], NULL, NULL, argv, environ) != 0) continue;

        int status = 0;
        if (waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) return YES;
    }
    return NO;
}

static NSDictionary *G2ValidateGIFData(NSData *data, NSError **error) {
    if (!data.length || data.length > G2MaximumInputBytes) {
        if (error) *error = [NSError errorWithDomain:@"Gif2Ani" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The GIF must be 25 MB or smaller."}];
        return nil;
    }

    NSDictionary *sourceOptions = @{(NSString *)kCGImageSourceShouldCache: @NO};
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,
                                                          (__bridge CFDictionaryRef)sourceOptions);
    if (!source) {
        if (error) *error = [NSError errorWithDomain:@"Gif2Ani" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The selected file is not a readable GIF."}];
        return nil;
    }

    size_t sourceFrames = CGImageSourceGetCount(source);
    NSDictionary *properties = sourceFrames ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
    NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSUInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CFRelease(source);

    if (!gifProperties || sourceFrames < 2 || width == 0 || height == 0) {
        if (error) *error = [NSError errorWithDomain:@"Gif2Ani" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Choose a real animated GIF with at least two readable frames."}];
        return nil;
    }
    if (sourceFrames > G2MaximumSourceFrames) {
        if (error) *error = [NSError errorWithDomain:@"Gif2Ani" code:4 userInfo:@{NSLocalizedDescriptionKey: @"This GIF has more than 240 source frames. Shorten it before importing so BackBoard stays stable."}];
        return nil;
    }

    NSUInteger decodedFrames = MIN((NSUInteger)sourceFrames, G2MaximumDecodedFrames);
    double maxDimension = (double)MAX(width, height);
    double scale = MIN(1.0, (double)G2MaximumPixelDimension / MAX(1.0, maxDimension));
    NSUInteger decodedWidth = MAX((NSUInteger)1, (NSUInteger)ceil(width * scale));
    NSUInteger decodedHeight = MAX((NSUInteger)1, (NSUInteger)ceil(height * scale));
    unsigned long long estimatedBytes = (unsigned long long)decodedWidth *
                                        (unsigned long long)decodedHeight * 4ULL *
                                        (unsigned long long)decodedFrames;
    if (estimatedBytes > G2MaximumEstimatedDecodedBytes) {
        if (error) *error = [NSError errorWithDomain:@"Gif2Ani" code:5 userInfo:@{NSLocalizedDescriptionKey: @"This GIF would use too much decoded memory for the 2 GB iPad. Choose a smaller or shorter animation."}];
        return nil;
    }

    return @{
        @"inputBytes": @(data.length),
        @"sourceFrames": @(sourceFrames),
        @"decodedFrames": @(decodedFrames),
        @"sourceWidth": @(width),
        @"sourceHeight": @(height),
        @"decodedWidth": @(decodedWidth),
        @"decodedHeight": @(decodedHeight),
        @"estimatedDecodedBytes": @(estimatedBytes),
        @"decoder": @"ImageIO-bounded-thumbnail",
    };
}

static NSDictionary *G2ValidateGIFAtPath(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    return data ? G2ValidateGIFData(data, error) : nil;
}

@interface Gif2AniRootListController ()
@property (nonatomic, assign) BOOL g2OperationInProgress;
@property (nonatomic, copy) NSString *g2SelectedColorPreference;
@end

@implementation Gif2AniRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Gif2Ani";
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:body
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)postSafeReload {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         G2ReloadNotification, NULL, NULL, YES);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [super readPreferenceValue:specifier];
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] ?: @{};
    id value = preferences[key] ?: G2DefaultPreferences()[key] ?: [specifier propertyForKey:@"default"];
    return G2NormalizedPreferenceValue(key, value);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) {
        [super setPreferenceValue:value specifier:specifier];
        return;
    }
    NSError *error = nil;
    id normalized = G2NormalizedPreferenceValue(key, value);
    if (!G2WritePreferences(@{key: normalized ?: [NSNull null]}, &error)) {
        [self showMessage:@"Setting not saved" body:error.localizedDescription ?: @"The setting could not be verified on disk."];
    }
}

- (void)showStatus {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] ?: @{};
    NSDictionary *runtime = [NSDictionary dictionaryWithContentsOfFile:G2RuntimeStatusPath] ?: @{};
    NSDictionary *pending = [NSDictionary dictionaryWithContentsOfFile:G2PendingMetadataPath];
    NSError *activeError = nil;
    NSDictionary *active = [[NSFileManager defaultManager] fileExistsAtPath:G2ActiveGIFPath]
        ? G2ValidateGIFAtPath(G2ActiveGIFPath, &activeError) : nil;

    NSString *mediaState = @"No GIF selected";
    if (pending) mediaState = @"A validated GIF is staged and waiting for Apply";
    else if (active) mediaState = @"An active GIF is installed";
    else if ([[NSFileManager defaultManager] fileExistsAtPath:G2RejectedGIFPath]) mediaState = @"The last GIF was quarantined after a safety failure";

    NSMutableString *body = [NSMutableString stringWithFormat:
        @"%@\n\nEnabled: %@\nScaling: %@\nRepeat mode: %@\nDuration: %@\nBackground: %@",
        mediaState,
        [prefs[@"isEnabled"] boolValue] ? @"Yes" : @"No",
        prefs[@"imageTransformation"] ?: @"resizeAspect",
        [prefs[@"customLoop"] doubleValue] < 0 ? @"Forever" : [NSString stringWithFormat:@"%.0f", [prefs[@"customLoop"] doubleValue]],
        [prefs[@"customDuration"] doubleValue] < 0 ? @"Original GIF timing" : [NSString stringWithFormat:@"%.2f seconds", [prefs[@"customDuration"] doubleValue]],
        prefs[@"backgroundColor"] ?: @"#000000:1.000"];

    NSDictionary *shown = pending ?: active;
    if (shown) {
        [body appendFormat:@"\n\nGIF: %@×%@\nSource frames: %@\nDecoded frames: %@\nEstimated memory: %.1f MB",
            shown[@"sourceWidth"] ?: @"?", shown[@"sourceHeight"] ?: @"?",
            shown[@"sourceFrames"] ?: @"?", shown[@"decodedFrames"] ?: @"?",
            [shown[@"estimatedDecodedBytes"] doubleValue] / (1024.0 * 1024.0)];
    } else if (activeError) {
        [body appendFormat:@"\n\nActive GIF validation error: %@", activeError.localizedDescription];
    }

    if (runtime.count) {
        [body appendFormat:@"\n\nRuntime: %@\nRuntime frames: %@\nOverlay: %@\nApple loader hidden: %@",
            runtime[@"event"] ?: @"unknown",
            runtime[@"frameCount"] ?: @0,
            runtime[@"attachmentPoint"] ?: @"not attached",
            [runtime[@"appleLoaderHidden"] boolValue] ? @"Yes" : @"No"];
    }
    [self showMessage:@"Gif2Ani Status" body:body];
}

- (void)selectGIF {
    if (self.g2OperationInProgress) {
        [self showMessage:@"Please wait" body:@"A GIF operation is already running."];
        return;
    }
    self.g2OperationInProgress = YES;
    UTType *gifType = [UTType typeWithFilenameExtension:@"gif"] ?: UTTypeImage;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[gifType] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.g2OperationInProgress = NO;
    (void)controller;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        self.g2OperationInProgress = NO;
        return;
    }

    BOOL scoped = [url startAccessingSecurityScopedResource];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
            NSDictionary *metadata = error ? nil : G2ValidateGIFData(data, &error);
            NSFileManager *manager = [NSFileManager defaultManager];
            NSString *temporaryGIFPath = [G2PendingGIFPath stringByAppendingString:@".importing"];
            NSString *temporaryMetadataPath = [G2PendingMetadataPath stringByAppendingString:@".importing"];

            if (data && metadata && !error) {
                [manager createDirectoryAtPath:G2MediaDirectory
                    withIntermediateDirectories:YES
                                     attributes:@{NSFilePosixPermissions: @0755}
                                          error:&error];
            }
            [manager removeItemAtPath:temporaryGIFPath error:nil];
            [manager removeItemAtPath:temporaryMetadataPath error:nil];

            if (data && metadata && !error &&
                ![data writeToFile:temporaryGIFPath options:NSDataWritingAtomic error:&error]) data = nil;
            if (!error && data) chmod(temporaryGIFPath.fileSystemRepresentation, 0644);

            if (!error && data && metadata &&
                ![metadata writeToFile:temporaryMetadataPath atomically:YES]) {
                error = [NSError errorWithDomain:@"Gif2Ani" code:6 userInfo:@{
                    NSLocalizedDescriptionKey: @"The validated GIF metadata could not be staged."
                }];
            }

            if (!error && data && metadata) {
                [manager removeItemAtPath:G2PendingGIFPath error:nil];
                [manager removeItemAtPath:G2PendingMetadataPath error:nil];
                BOOL gifMoved = rename(temporaryGIFPath.fileSystemRepresentation, G2PendingGIFPath.fileSystemRepresentation) == 0;
                BOOL metadataMoved = gifMoved && rename(temporaryMetadataPath.fileSystemRepresentation, G2PendingMetadataPath.fileSystemRepresentation) == 0;
                if (!gifMoved || !metadataMoved) {
                    int savedErrno = errno;
                    [manager removeItemAtPath:G2PendingGIFPath error:nil];
                    [manager removeItemAtPath:G2PendingMetadataPath error:nil];
                    error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:@{
                        NSLocalizedDescriptionKey: @"The validated GIF could not be moved into the staging area."
                    }];
                }
            }

            if (!error && data && metadata && !G2WritePreferences(@{@"pendingReady": @YES}, &error)) {
                [manager removeItemAtPath:G2PendingGIFPath error:nil];
                [manager removeItemAtPath:G2PendingMetadataPath error:nil];
            }
            if (error) {
                [manager removeItemAtPath:temporaryGIFPath error:nil];
                [manager removeItemAtPath:temporaryMetadataPath error:nil];
            }
            if (scoped) [url stopAccessingSecurityScopedResource];

            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.g2OperationInProgress = NO;
                if (error || !data || !metadata) {
                    [strongSelf showMessage:@"Import failed" body:error.localizedDescription ?: @"The GIF could not be staged safely."];
                    return;
                }

                NSString *summary = [NSString stringWithFormat:
                    @"Staged only — BackBoard was not restarted.\n\n%lu source frames → %lu bounded frames\n%lu×%lu → at most %lu×%lu\nEstimated decoded memory: %.1f MB\n\nTap Apply and Respring when ready.",
                    (unsigned long)[metadata[@"sourceFrames"] unsignedIntegerValue],
                    (unsigned long)[metadata[@"decodedFrames"] unsignedIntegerValue],
                    (unsigned long)[metadata[@"sourceWidth"] unsignedIntegerValue],
                    (unsigned long)[metadata[@"sourceHeight"] unsignedIntegerValue],
                    (unsigned long)[metadata[@"decodedWidth"] unsignedIntegerValue],
                    (unsigned long)[metadata[@"decodedHeight"] unsignedIntegerValue],
                    [metadata[@"estimatedDecodedBytes"] doubleValue] / (1024.0 * 1024.0)];
                [strongSelf showMessage:@"GIF staged safely" body:summary];
            });
        }
    });
    (void)controller;
}

- (void)confirmRemoveGIF {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Gif2Ani GIF?"
                                                                   message:@"This removes the staged, active, and quarantined GIF files and disables Gif2Ani. Your Settings choices will remain."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove GIF" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [weakSelf removeGIFNow];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)removeGIFNow {
    NSError *error = nil;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *paths = @[
        G2PendingGIFPath, G2ActiveGIFPath, G2RejectedGIFPath, G2LoadSentinelPath,
        G2PendingMetadataPath, G2ActiveBackupPath,
        [G2PendingGIFPath stringByAppendingString:@".importing"],
        [G2PendingMetadataPath stringByAppendingString:@".importing"],
        [G2ActiveGIFPath stringByAppendingString:@".new"]
    ];
    for (NSString *path in paths) {
        if ([manager fileExistsAtPath:path] && ![manager removeItemAtPath:path error:&error]) break;
    }
    if (error) {
        [self showMessage:@"Remove failed" body:error.localizedDescription ?: @"The GIF files could not be removed."];
        return;
    }

    if (!G2WriteEnabledPreferences(NO, &error)) {
        [self showMessage:@"Remove incomplete" body:error.localizedDescription ?: @"The files were removed, but the disabled state could not be verified."];
        return;
    }
    [self postSafeReload];
    [self showMessage:@"GIF removed" body:@"Gif2Ani is disabled. Apple’s normal respring animation is active."];
}

- (void)chooseBackgroundColor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] ?: @{};
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = YES;
    picker.selectedColor = G2ColorFromPreference(prefs[@"backgroundColor"] ?: @"#000000:1.000");
    self.g2SelectedColorPreference = G2PreferenceFromColor(picker.selectedColor);
    picker.title = @"Background Color";
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    self.g2SelectedColorPreference = G2PreferenceFromColor(viewController.selectedColor);
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    NSString *value = self.g2SelectedColorPreference ?: G2PreferenceFromColor(viewController.selectedColor);
    NSError *error = nil;
    if (!G2WritePreferences(@{@"backgroundColor": value}, &error)) {
        [self showMessage:@"Color not saved" body:error.localizedDescription ?: @"The background color could not be verified on disk."];
    }
    self.g2SelectedColorPreference = nil;
}

- (void)resetVisualAndPlaybackSettings {
    NSError *error = nil;
    NSDictionary *defaults = G2DefaultPreferences();
    NSDictionary *updates = @{
        @"imageTransformation": defaults[@"imageTransformation"],
        @"customLoop": defaults[@"customLoop"],
        @"customDuration": defaults[@"customDuration"],
        @"backgroundColor": defaults[@"backgroundColor"],
    };
    if (!G2WritePreferences(updates, &error)) {
        [self showMessage:@"Reset failed" body:error.localizedDescription ?: @"The default settings could not be verified."];
        return;
    }
    [self reloadSpecifiers];
    [self showMessage:@"Settings reset" body:@"Scaling, playback, and background color were reset. Tap Apply and Respring to use them."];
}

- (void)applyAndRespring {
    if (self.g2OperationInProgress) {
        [self showMessage:@"Please wait" body:@"A GIF operation is already running."];
        return;
    }
    self.g2OperationInProgress = YES;

    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL promotedPending = NO;
    BOOL hadPreviousActive = [manager fileExistsAtPath:G2ActiveGIFPath];

    if ([manager fileExistsAtPath:G2PendingGIFPath]) {
        if (!G2ValidateGIFAtPath(G2PendingGIFPath, &error)) {
            self.g2OperationInProgress = NO;
            [self showMessage:@"Apply failed" body:error.localizedDescription ?: @"The staged GIF no longer passes validation."];
            return;
        }

        NSString *temporaryPath = [G2ActiveGIFPath stringByAppendingString:@".new"];
        [manager removeItemAtPath:temporaryPath error:nil];
        [manager removeItemAtPath:G2ActiveBackupPath error:nil];
        if (![manager copyItemAtPath:G2PendingGIFPath toPath:temporaryPath error:&error]) {
            self.g2OperationInProgress = NO;
            [self showMessage:@"Apply failed" body:error.localizedDescription ?: @"The staged GIF could not be prepared."];
            return;
        }
        chmod(temporaryPath.fileSystemRepresentation, 0644);

        if (hadPreviousActive && ![manager moveItemAtPath:G2ActiveGIFPath toPath:G2ActiveBackupPath error:&error]) {
            [manager removeItemAtPath:temporaryPath error:nil];
            self.g2OperationInProgress = NO;
            [self showMessage:@"Apply failed" body:error.localizedDescription ?: @"The previous active GIF could not be backed up safely."];
            return;
        }
        if (rename(temporaryPath.fileSystemRepresentation, G2ActiveGIFPath.fileSystemRepresentation) != 0) {
            int savedErrno = errno;
            [manager removeItemAtPath:temporaryPath error:nil];
            if (hadPreviousActive) [manager moveItemAtPath:G2ActiveBackupPath toPath:G2ActiveGIFPath error:nil];
            self.g2OperationInProgress = NO;
            [self showMessage:@"Apply failed" body:[NSString stringWithFormat:@"The staged GIF could not be activated (errno %d).", savedErrno]];
            return;
        }
        promotedPending = YES;
    }

    if (![manager fileExistsAtPath:G2ActiveGIFPath] || !G2ValidateGIFAtPath(G2ActiveGIFPath, &error)) {
        if (promotedPending) {
            [manager removeItemAtPath:G2ActiveGIFPath error:nil];
            if (hadPreviousActive) [manager moveItemAtPath:G2ActiveBackupPath toPath:G2ActiveGIFPath error:nil];
        }
        G2WriteEnabledPreferences(NO, nil);
        self.g2OperationInProgress = NO;
        [self showMessage:@"Apply failed" body:error.localizedDescription ?: @"No valid active GIF exists. Select and stage a GIF first."];
        return;
    }

    NSDictionary *current = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] ?: @{};
    NSDictionary *defaults = G2DefaultPreferences();
    NSDictionary *normalizedSettings = @{
        @"imageTransformation": current[@"imageTransformation"] ?: defaults[@"imageTransformation"],
        @"customLoop": current[@"customLoop"] ?: defaults[@"customLoop"],
        @"customDuration": current[@"customDuration"] ?: defaults[@"customDuration"],
        @"backgroundColor": current[@"backgroundColor"] ?: defaults[@"backgroundColor"],
    };
    if (!G2WritePreferences(normalizedSettings, &error) || !G2WriteEnabledPreferences(YES, &error)) {
        if (promotedPending) {
            [manager removeItemAtPath:G2ActiveGIFPath error:nil];
            if (hadPreviousActive) [manager moveItemAtPath:G2ActiveBackupPath toPath:G2ActiveGIFPath error:nil];
        }
        self.g2OperationInProgress = NO;
        [self showMessage:@"Apply failed" body:error.localizedDescription ?: @"The settings could not be saved and verified safely."];
        return;
    }

    [manager removeItemAtPath:G2ActiveBackupPath error:nil];
    if (promotedPending) {
        [manager removeItemAtPath:G2PendingGIFPath error:nil];
        [manager removeItemAtPath:G2PendingMetadataPath error:nil];
    }
    [manager removeItemAtPath:G2RejectedGIFPath error:nil];
    [manager removeItemAtPath:G2LoadSentinelPath error:nil];

    [self postSafeReload];
    usleep(250000);

    if (G2RestartProcess(@"backboardd")) return;
    if (G2RestartProcess(@"SpringBoard")) return;

    self.g2OperationInProgress = NO;
    [self showMessage:@"Unable to restart BackBoard"
                 body:@"The GIF and settings are enabled and verified, but the system restart command was unavailable."];
}

- (void)respring {
    [self applyAndRespring];
}

@end
