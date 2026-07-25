#import "DBRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>
#import <sys/stat.h>

extern char **environ;

static NSString * const DBPreferencesDomain = @"com.nightvibes33.darkboot";
static NSString * const DBMediaDirectory = @"/var/mobile/Library/Application Support/DarkBoot";
static NSString * const DBSessionMarkerPath = @"/var/mobile/Library/Application Support/DarkBoot/session-active";
static CFStringRef const DBReloadNotification = CFSTR("com.nightvibes33.darkboot/reload");
static CFStringRef const DBPreviewNotification = CFSTR("com.nightvibes33.darkboot/preview");
static CFStringRef const DBSoundPreviewNotification = CFSTR("com.nightvibes33.darkboot/preview-sound");

typedef NS_ENUM(NSInteger, DBImportKind) {
    DBImportKindVisual,
    DBImportKindSound
};

@interface DBRootListController ()
@property (nonatomic, assign) DBImportKind importKind;
@property (nonatomic, strong) CAGradientLayer *headerGradient;
@property (nonatomic, strong) UILabel *headerStatusLabel;
@property (nonatomic, strong) UILabel *headerMediaLabel;
@end

@implementation DBRootListController

#pragma mark - Lifecycle and header

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Dark Boot";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self installHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshHeader];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.headerGradient.frame = self.table.tableHeaderView.bounds;
}

- (void)installHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 184)];
    header.backgroundColor = UIColor.blackColor;
    header.layer.cornerRadius = 22.0;
    header.layer.masksToBounds = YES;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.04 green:0.06 blue:0.13 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.11 green:0.20 blue:0.34 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.05 alpha:1.0].CGColor
    ];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    [header.layer addSublayer:gradient];
    self.headerGradient = gradient;

    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"power.circle.fill"]];
    symbol.translatesAutoresizingMaskIntoConstraints = NO;
    symbol.tintColor = [UIColor colorWithRed:0.12 green:0.78 blue:1.0 alpha:1.0];
    symbol.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:42 weight:UIImageSymbolWeightBold];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"DARK BOOT";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBlack];

    UILabel *version = [UILabel new];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.text = @"PRODUCTION ENGINE • 2.0";
    version.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    version.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];

    UILabel *status = [UILabel new];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    self.headerStatusLabel = status;

    UILabel *media = [UILabel new];
    media.translatesAutoresizingMaskIntoConstraints = NO;
    media.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    media.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    media.numberOfLines = 2;
    self.headerMediaLabel = media;

    [header addSubview:symbol];
    [header addSubview:title];
    [header addSubview:version];
    [header addSubview:status];
    [header addSubview:media];

    [NSLayoutConstraint activateConstraints:@[
        [symbol.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:22],
        [symbol.topAnchor constraintEqualToAnchor:header.topAnchor constant:24],
        [symbol.widthAnchor constraintEqualToConstant:48],
        [symbol.heightAnchor constraintEqualToConstant:48],
        [title.leadingAnchor constraintEqualToAnchor:symbol.trailingAnchor constant:14],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-18],
        [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:22],
        [version.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [version.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [status.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:22],
        [status.topAnchor constraintEqualToAnchor:symbol.bottomAnchor constant:25],
        [media.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:22],
        [media.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-22],
        [media.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:8]
    ]];

    self.table.tableHeaderView = header;
    [self refreshHeader];
}

- (NSString *)mediaNameWithPrefix:(NSString *)prefix {
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DBMediaDirectory error:nil];
    for (NSString *name in [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        if ([name.lowercaseString hasPrefix:prefix.lowercaseString]) return name;
    }
    return nil;
}

- (void)refreshHeader {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:DBPreferencesDomain];
    BOOL enabled = [defaults objectForKey:@"Enabled"] ? [defaults boolForKey:@"Enabled"] : YES;
    BOOL suppressed = [defaults boolForKey:@"CrashGuardSuppressed"];
    if (suppressed) {
        self.headerStatusLabel.text = @"● SAFETY MODE ACTIVE";
        self.headerStatusLabel.textColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.30 alpha:1.0];
    } else if (enabled) {
        self.headerStatusLabel.text = @"● ENGINE ENABLED";
        self.headerStatusLabel.textColor = [UIColor colorWithRed:0.24 green:0.95 blue:0.55 alpha:1.0];
    } else {
        self.headerStatusLabel.text = @"● ENGINE DISABLED";
        self.headerStatusLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    }

    NSString *visual = [self mediaNameWithPrefix:@"boot-visual."] ?: @"Built-in cinematic visual";
    NSString *sound = [self mediaNameWithPrefix:@"boot-sound."] ?: @"Built-in fallback chime";
    self.headerMediaLabel.text = [NSString stringWithFormat:@"Visual: %@\nAudio: %@", visual, sound];
}

#pragma mark - Preferences

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)DBPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    [self refreshHeader];
}

- (void)ensureMediaDirectory {
    [[NSFileManager defaultManager] createDirectoryAtPath:DBMediaDirectory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:nil];
}

- (void)removeFilesWithPrefix:(NSString *)prefix {
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DBMediaDirectory error:nil]) {
        if ([name.lowercaseString hasPrefix:prefix.lowercaseString]) {
            [[NSFileManager defaultManager] removeItemAtPath:[DBMediaDirectory stringByAppendingPathComponent:name] error:nil];
        }
    }
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showConfirmation:(NSString *)title body:(NSString *)body destructiveTitle:(NSString *)destructiveTitle action:(dispatch_block_t)action {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:destructiveTitle style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *selected) {
        if (action) action();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Importing

- (void)importVisual {
    self.importKind = DBImportKindVisual;
    NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObjects:UTTypeImage, UTTypeMovie, nil];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importSound {
    self.importKind = DBImportKindSound;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)validateFileSizeAtURL:(NSURL *)url maximumBytes:(unsigned long long)maximum error:(NSError **)error {
    NSNumber *size = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:error];
    if (*error) return NO;
    if (size.unsignedLongLongValue > maximum) {
        if (error) *error = [NSError errorWithDomain:@"DarkBoot" code:10 userInfo:@{NSLocalizedDescriptionKey: @"The selected file is too large for a safe SpringBoard startup overlay."}];
        return NO;
    }
    return YES;
}

- (BOOL)importStaticImageFromURL:(NSURL *)url error:(NSError **)error {
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceShouldCacheImmediately: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @2732
    };
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    CGImageRef thumbnail = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
    UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
    NSData *png = image ? UIImagePNGRepresentation(image) : nil;
    if (thumbnail) CGImageRelease(thumbnail);
    if (source) CFRelease(source);
    if (!png) {
        if (error) *error = [NSError errorWithDomain:@"DarkBoot" code:11 userInfo:@{NSLocalizedDescriptionKey: @"The selected image could not be decoded."}];
        return NO;
    }
    NSString *temporary = [DBMediaDirectory stringByAppendingPathComponent:@"visual-import.tmp"];
    if (![png writeToFile:temporary options:NSDataWritingAtomic error:error]) return NO;
    [self removeFilesWithPrefix:@"boot-visual."];
    NSString *destination = [DBMediaDirectory stringByAppendingPathComponent:@"boot-visual.png"];
    return [[NSFileManager defaultManager] moveItemAtPath:temporary toPath:destination error:error];
}

- (BOOL)importAnimatedImageFromURL:(NSURL *)url extension:(NSString *)extension error:(NSError **)error {
    if (![self validateFileSizeAtURL:url maximumBytes:30ULL * 1024ULL * 1024ULL error:error]) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    size_t count = source ? CGImageSourceGetCount(source) : 0;
    if (source) CFRelease(source);
    if (count < 2) return [self importStaticImageFromURL:url error:error];

    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    NSString *temporary = [DBMediaDirectory stringByAppendingPathComponent:@"visual-import.tmp"];
    if (![data writeToFile:temporary options:NSDataWritingAtomic error:error]) return NO;
    [self removeFilesWithPrefix:@"boot-visual."];
    NSString *destination = [DBMediaDirectory stringByAppendingPathComponent:[@"boot-visual" stringByAppendingPathExtension:extension.length ? extension : @"gif"]];
    return [[NSFileManager defaultManager] moveItemAtPath:temporary toPath:destination error:error];
}

- (BOOL)importVideoFromURL:(NSURL *)url extension:(NSString *)extension error:(NSError **)error {
    if (![self validateFileSizeAtURL:url maximumBytes:150ULL * 1024ULL * 1024ULL error:error]) return NO;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
    if (!isfinite(duration) || duration <= 0.0 || duration > 60.0) {
        if (error) *error = [NSError errorWithDomain:@"DarkBoot" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Choose a playable video no longer than 60 seconds."}];
        return NO;
    }
    NSString *temporary = [DBMediaDirectory stringByAppendingPathComponent:@"visual-import.tmp"];
    [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
    if (![[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:temporary] error:error]) return NO;
    [self removeFilesWithPrefix:@"boot-visual."];
    NSString *destination = [DBMediaDirectory stringByAppendingPathComponent:[@"boot-visual" stringByAppendingPathExtension:extension.length ? extension : @"mp4"]];
    return [[NSFileManager defaultManager] moveItemAtPath:temporary toPath:destination error:error];
}

- (BOOL)importVisualFromURL:(NSURL *)url error:(NSError **)error {
    NSString *extension = url.pathExtension.lowercaseString;
    UTType *type = extension.length ? [UTType typeWithFilenameExtension:extension] : nil;
    if ([type conformsToType:UTTypeMovie] || [@[@"mp4", @"mov", @"m4v"] containsObject:extension]) {
        return [self importVideoFromURL:url extension:extension error:error];
    }
    if ([type conformsToType:UTTypeGIF] || [extension isEqualToString:@"gif"] || [extension isEqualToString:@"apng"]) {
        return [self importAnimatedImageFromURL:url extension:extension error:error];
    }
    if (![self validateFileSizeAtURL:url maximumBytes:60ULL * 1024ULL * 1024ULL error:error]) return NO;
    return [self importStaticImageFromURL:url error:error];
}

- (BOOL)importSoundFromURL:(NSURL *)url error:(NSError **)error {
    if (![self validateFileSizeAtURL:url maximumBytes:30ULL * 1024ULL * 1024ULL error:error]) return NO;
    AVAudioPlayer *validator = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:error];
    if (!validator || *error) return NO;
    NSString *extension = url.pathExtension.lowercaseString;
    if (!extension.length) extension = @"audio";
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    NSString *temporary = [DBMediaDirectory stringByAppendingPathComponent:@"sound-import.tmp"];
    if (![data writeToFile:temporary options:NSDataWritingAtomic error:error]) return NO;
    [self removeFilesWithPrefix:@"boot-sound."];
    NSString *destination = [DBMediaDirectory stringByAppendingPathComponent:[@"boot-sound" stringByAppendingPathExtension:extension]];
    return [[NSFileManager defaultManager] moveItemAtPath:temporary toPath:destination error:error];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    [self ensureMediaDirectory];

    NSError *error = nil;
    BOOL success = self.importKind == DBImportKindVisual
        ? [self importVisualFromURL:url error:&error]
        : [self importSoundFromURL:url error:&error];

    if (accessed) [url stopAccessingSecurityScopedResource];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    [self refreshHeader];

    if (!success || error) {
        [self showMessage:@"Import failed" body:error.localizedDescription ?: @"The selected media could not be imported."];
    } else {
        NSString *message = self.importKind == DBImportKindVisual
            ? @"Your image, animated GIF, or video is ready. Tap Preview Full Experience to test it."
            : @"Your startup sound is ready. Tap Preview Sound or Preview Full Experience to test it.";
        [self showMessage:@"Import complete" body:message];
    }
    (void)controller;
}

#pragma mark - Actions

- (void)preview {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBPreviewNotification, NULL, NULL, YES);
}

- (void)previewSound {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBSoundPreviewNotification, NULL, NULL, YES);
}

- (void)resetMedia {
    __weak typeof(self) weakSelf = self;
    [self showConfirmation:@"Reset imported media?" body:@"Dark Boot will return to its built-in cinematic visual and fallback chime." destructiveTitle:@"Reset Media" action:^{
        [weakSelf removeFilesWithPrefix:@"boot-visual."];
        [weakSelf removeFilesWithPrefix:@"boot-sound."];
        [[NSFileManager defaultManager] removeItemAtPath:[DBMediaDirectory stringByAppendingPathComponent:@"visual-import.tmp"] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[DBMediaDirectory stringByAppendingPathComponent:@"sound-import.tmp"] error:nil];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
        [weakSelf refreshHeader];
        [weakSelf showMessage:@"Media reset" body:@"Built-in Dark Boot visuals and audio are active again."];
    }];
}

- (void)resetCrashGuard {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:DBPreferencesDomain];
    [defaults setInteger:0 forKey:@"CrashGuardCount"];
    [defaults setBool:NO forKey:@"CrashGuardSuppressed"];
    [defaults synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:DBSessionMarkerPath error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    [self refreshHeader];
    [self showMessage:@"Safety mode cleared" body:@"Dark Boot is allowed to run on the next SpringBoard launch."];
}

- (void)restoreDefaults {
    __weak typeof(self) weakSelf = self;
    [self showConfirmation:@"Restore every setting?" body:@"This keeps imported media but resets animation, audio, interaction, and safety options." destructiveTitle:@"Restore Defaults" action:^{
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:DBPreferencesDomain];
        for (NSString *key in defaults.dictionaryRepresentation.allKeys) [defaults removeObjectForKey:key];
        [defaults synchronize];
        [[NSFileManager defaultManager] removeItemAtPath:DBSessionMarkerPath error:nil];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
        [weakSelf reloadSpecifiers];
        [weakSelf refreshHeader];
        [weakSelf showMessage:@"Defaults restored" body:@"Dark Boot is back to its production default configuration."];
    }];
}

- (void)openProject {
    NSURL *url = [NSURL URLWithString:@"https://github.com/NightVibes33/Dark-Boot"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)respring {
    const char *paths[] = {"/var/jb/usr/bin/sbreload", "/usr/bin/sbreload"};
    for (NSUInteger index = 0; index < 2; index++) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:@(paths[index])]) {
            pid_t pid = 0;
            char *argv[] = {(char *)paths[index], NULL};
            if (posix_spawn(&pid, paths[index], NULL, NULL, argv, environ) == 0) return;
        }
    }
    [self showMessage:@"Unable to respring" body:@"Run sbreload from a terminal or respring through your package manager."];
}

@end
