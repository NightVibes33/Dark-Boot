#import "gif2ani2RootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <spawn.h>
#import <sys/stat.h>

extern char **environ;

static NSString * const G2PreferencesDomain = @"com.nightvibes33.gif2ani";
static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2GIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Respring.gif";
static CFStringRef const G2ReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

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

- (void)postReload {
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
    NSError *error = nil;
    NSNumber *size = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
    if (!error && size.unsignedLongLongValue > 80ULL * 1024ULL * 1024ULL) {
        error = [NSError errorWithDomain:@"Gif2Ani" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The GIF is larger than 80 MB."}];
    }

    NSData *data = error ? nil : [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    if (data) {
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source || CGImageSourceGetCount(source) == 0) {
            error = [NSError errorWithDomain:@"Gif2Ani" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The selected file is not a readable animated GIF."}];
        }
        if (source) CFRelease(source);
    }

    if (data && !error) {
        [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0755}
                                                        error:&error];
    }
    if (data && !error && ![data writeToFile:G2GIFPath options:NSDataWritingAtomic error:&error]) data = nil;
    if (!error) chmod(G2GIFPath.fileSystemRepresentation, 0644);
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (error || !data) {
        [self showMessage:@"Import failed" body:error.localizedDescription ?: @"The GIF could not be imported."];
        return;
    }
    [self postReload];
    [self showMessage:@"GIF imported" body:@"The animation is ready. Tap Apply and Respring to test it on the real respring screen."];
    (void)controller;
}

- (void)removeGIF {
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:G2GIFPath] && ![[NSFileManager defaultManager] removeItemAtPath:G2GIFPath error:&error]) {
        [self showMessage:@"Remove failed" body:error.localizedDescription ?: @"The GIF could not be removed."];
        return;
    }
    [self postReload];
    [self showMessage:@"GIF removed" body:@"Apple's normal respring animation will be used until another GIF is selected."];
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
    [self postReload];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self colorPickerViewControllerDidSelectColor:viewController];
}

- (void)respring {
    const char *candidates[] = {"/var/jb/usr/bin/sbreload", "/usr/bin/sbreload"};
    for (NSUInteger index = 0; index < 2; index++) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:@(candidates[index])]) {
            pid_t pid = 0;
            char *argv[] = {(char *)candidates[index], NULL};
            if (posix_spawn(&pid, candidates[index], NULL, NULL, argv, environ) == 0) return;
        }
    }
    [self showMessage:@"Unable to respring" body:@"Run sbreload in a terminal. Your Gif2Ani settings were still saved."];
}

@end
