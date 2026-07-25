#import "gif2ani2RootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <spawn.h>
#import <sys/stat.h>
#import <stdio.h>
#import <errno.h>
#import <unistd.h>

extern char **environ;

static NSString * const G2PreferencesDomain = @"com.nightvibes33.gif2ani";
static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2PendingGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Pending.gif";
static NSString * const G2ActiveGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Active.gif";
static NSString * const G2RejectedGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Rejected.gif";
static NSString * const G2LoadSentinelPath = @"/var/mobile/Library/Application Support/Gif2Ani/load-in-progress";
static NSString * const G2PendingMetadataPath = @"/var/mobile/Library/Application Support/Gif2Ani/pending-metadata.plist";
static CFStringRef const G2ReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

static const NSUInteger G2MaximumSourceFrames = 240;
static const NSUInteger G2MaximumDecodedFrames = 24;
static const NSUInteger G2MaximumPixelDimension = 640;
static const unsigned long long G2MaximumInputBytes = 25ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumEstimatedDecodedBytes = 48ULL * 1024ULL * 1024ULL;

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
            (int)lrint(red * 255.0), (int)lrint(green * 255.0), (int)lrint(blue * 255.0), alpha];
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
    unsigned long long estimatedBytes = (unsigned long long)decodedWidth * (unsigned long long)decodedHeight * 4ULL * (unsigned long long)decodedFrames;

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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)postSafeReload {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), G2ReloadNotification, NULL, NULL, YES);
}

- (void)selectGIF {
    UTType *gifType = [UTType typeWithFilenameExtension:@"gif"] ?: UTTypeImage;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[gifType] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

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

            if (data && metadata && !error) {
                if (![data writeToFile:temporaryGIFPath options:NSDataWritingAtomic error:&error]) data = nil;
            }
            if (!error && data) chmod(temporaryGIFPath.fileSystemRepresentation, 0644);

            if (!error && data && metadata) {
                if (![metadata writeToFile:temporaryMetadataPath atomically:YES]) {
                    error = [NSError errorWithDomain:@"Gif2Ani" code:6 userInfo:@{NSLocalizedDescriptionKey: @"The validated GIF metadata could not be staged."}];
                }
            }

            if (!error && data && metadata) {
                [manager removeItemAtPath:G2PendingGIFPath error:nil];
                [manager removeItemAtPath:G2PendingMetadataPath error:nil];
                if (rename(temporaryGIFPath.fileSystemRepresentation, G2PendingGIFPath.fileSystemRepresentation) != 0 ||
                    rename(temporaryMetadataPath.fileSystemRepresentation, G2PendingMetadataPath.fileSystemRepresentation) != 0) {
                    int savedErrno = errno;
                    error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:@{NSLocalizedDescriptionKey: @"The validated GIF could not be moved into the staging area."}];
                }
            }

            if (error) {
                [manager removeItemAtPath:temporaryGIFPath error:nil];
                [manager removeItemAtPath:temporaryMetadataPath error:nil];
            }
            if (scoped) [url stopAccessingSecurityScopedResource];

            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                if (error || !data || !metadata) {
                    [strongSelf showMessage:@"Import failed" body:error.localizedDescription ?: @"The GIF could not be staged safely."];
                    return;
                }

                CFPreferencesSetAppValue(CFSTR("pendingReady"), kCFBooleanTrue, (__bridge CFStringRef)G2PreferencesDomain);
                CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);

                NSString *summary = [NSString stringWithFormat:@"Staged only — backboardd was not notified.\n\n%lu source frames → %lu bounded frames\n%lux%lu → at most %lux%lu\nEstimated decoded memory: %.1f MB\n\nTap Apply and Respring when ready.",
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

- (void)removeGIF {
    NSError *error = nil;
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in @[G2PendingGIFPath, G2ActiveGIFPath, G2RejectedGIFPath, G2LoadSentinelPath, G2PendingMetadataPath]) {
        if ([manager fileExistsAtPath:path] && ![manager removeItemAtPath:path error:&error]) break;
    }
    if (error) {
        [self showMessage:@"Remove failed" body:error.localizedDescription ?: @"The GIF files could not be removed."];
        return;
    }

    CFPreferencesSetAppValue(CFSTR("isEnabled"), kCFBooleanFalse, (__bridge CFStringRef)G2PreferencesDomain);
    CFPreferencesSetAppValue(CFSTR("pendingReady"), kCFBooleanFalse, (__bridge CFStringRef)G2PreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
    [self postSafeReload];
    [self showMessage:@"GIF removed" body:@"Gif2Ani is disabled. Apple's normal respring animation is active."];
}

- (void)chooseBackgroundColor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.nightvibes33.gif2ani.plist"] ?: @{};
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = YES;
    picker.selectedColor = G2ColorFromPreference(prefs[@"backgroundColor"] ?: @"#000000");
    picker.title = @"Background Color";
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    NSString *value = G2PreferenceFromColor(viewController.selectedColor);
    CFPreferencesSetAppValue(CFSTR("backgroundColor"), (__bridge CFPropertyListRef)value, (__bridge CFStringRef)G2PreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self colorPickerViewControllerDidSelectColor:viewController];
}

- (void)applyAndRespring {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;

    if ([manager fileExistsAtPath:G2PendingGIFPath]) {
        NSString *temporaryPath = [G2ActiveGIFPath stringByAppendingString:@".new"];
        [manager removeItemAtPath:temporaryPath error:nil];
        if (![manager copyItemAtPath:G2PendingGIFPath toPath:temporaryPath error:&error]) {
            [self showMessage:@"Apply failed" body:error.localizedDescription ?: @"The staged GIF could not be prepared."];
            return;
        }
        chmod(temporaryPath.fileSystemRepresentation, 0644);
        if (rename(temporaryPath.fileSystemRepresentation, G2ActiveGIFPath.fileSystemRepresentation) != 0) {
            int savedErrno = errno;
            [manager removeItemAtPath:temporaryPath error:nil];
            NSString *message = [NSString stringWithFormat:@"The staged GIF could not be activated (errno %d).", savedErrno];
            [self showMessage:@"Apply failed" body:message];
            return;
        }
        [manager removeItemAtPath:G2PendingGIFPath error:nil];
        [manager removeItemAtPath:G2PendingMetadataPath error:nil];
    }

    if (![manager fileExistsAtPath:G2ActiveGIFPath]) {
        CFPreferencesSetAppValue(CFSTR("isEnabled"), kCFBooleanFalse, (__bridge CFStringRef)G2PreferencesDomain);
        CFPreferencesSetAppValue(CFSTR("pendingReady"), kCFBooleanFalse, (__bridge CFStringRef)G2PreferencesDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
    } else {
        [manager removeItemAtPath:G2RejectedGIFPath error:nil];
        [manager removeItemAtPath:G2LoadSentinelPath error:nil];
        CFPreferencesSetAppValue(CFSTR("isEnabled"), kCFBooleanTrue, (__bridge CFStringRef)G2PreferencesDomain);
        CFPreferencesSetAppValue(CFSTR("pendingReady"), kCFBooleanFalse, (__bridge CFStringRef)G2PreferencesDomain);
        CFPreferencesSetAppValue(CFSTR("lastAppliedAt"), (__bridge CFPropertyListRef)@([[NSDate date] timeIntervalSince1970]), (__bridge CFStringRef)G2PreferencesDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
    }

    [self postSafeReload];
    usleep(150000);

    const char *candidates[] = {"/var/jb/usr/bin/sbreload", "/usr/bin/sbreload"};
    for (NSUInteger index = 0; index < 2; index++) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:@(candidates[index])]) {
            pid_t pid = 0;
            char *argv[] = {(char *)candidates[index], NULL};
            if (posix_spawn(&pid, candidates[index], NULL, NULL, argv, environ) == 0) return;
        }
    }
    [self showMessage:@"Unable to respring" body:@"Run sbreload in a terminal. The staged settings were saved safely."];
}

- (void)respring {
    [self applyAndRespring];
}

@end
