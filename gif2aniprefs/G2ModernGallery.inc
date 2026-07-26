
#import <objc/runtime.h>

static NSString * const G2MActiveGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Active.gif";
static NSString * const G2MRejectedGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Rejected.gif";
static NSString * const G2MRollbackDirectory = @"/var/mobile/Library/Application Support/Gif2Ani/Rollbacks";
static NSString * const G2MRuntimeStatusPath = @"/var/mobile/Library/Application Support/Gif2Ani/runtime-status.plist";
static CFStringRef const G2MReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

static NSString *G2MThemeIdentifier(NSDictionary *pack) {
    for (NSString *key in @[@"identifier", @"package", @"path", @"name"]) {
        NSString *value = [pack[key] isKindOfClass:NSString.class] ? pack[key] : nil;
        if (value.length) return value;
    }
    return @"unknown-theme";
}

static NSMutableDictionary *G2MPreferences(void) {
    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] mutableCopy];
    return prefs ?: [NSMutableDictionary dictionary];
}

static BOOL G2MWritePreferences(NSDictionary *updates, NSError **error) {
    NSMutableDictionary *prefs = G2MPreferences();
    [prefs addEntriesFromDictionary:updates ?: @{}];
    if (![prefs writeToFile:G2PreferencesPath atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniModern" code:100 userInfo:@{NSLocalizedDescriptionKey:@"Gif2Ani preferences could not be written."}];
        return NO;
    }
    chown(G2PreferencesPath.fileSystemRepresentation, 501, 501);
    chmod(G2PreferencesPath.fileSystemRepresentation, 0644);
    CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
    return YES;
}

static UIColor *G2MColorFromPreference(NSString *value) {
    NSString *raw = [value isKindOfClass:NSString.class] ? value : @"#000000:1.000";
    NSArray<NSString *> *parts = [[raw stringByReplacingOccurrencesOfString:@"#" withString:@""] componentsSeparatedByString:@":"];
    NSString *hex = parts.firstObject ?: @"000000";
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) rgb = 0;
    CGFloat alpha = parts.count > 1 ? MAX(0.0, MIN(1.0, parts[1].doubleValue)) : 1.0;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                           green:((rgb >> 8) & 255) / 255.0
                            blue:(rgb & 255) / 255.0
                           alpha:alpha];
}

static NSString *G2MPreferenceFromColor(UIColor *color) {
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

static UIViewContentMode G2MContentMode(NSString *value) {
    if ([value isEqualToString:@"resizeAspectFill"]) return UIViewContentModeScaleAspectFill;
    if ([value isEqualToString:@"resize"]) return UIViewContentModeScaleToFill;
    if ([value isEqualToString:@"center"]) return UIViewContentModeCenter;
    return UIViewContentModeScaleAspectFit;
}

static NSString *G2MScalingPreferenceForIndex(NSInteger index) {
    return @[@"resizeAspect", @"resizeAspectFill", @"resize", @"center"][MAX(0, MIN(3, index))];
}

static unsigned long long G2MDirectoryBytes(NSString *root) {
    NSFileManager *manager = NSFileManager.defaultManager;
    BOOL directory = NO;
    if (![manager fileExistsAtPath:root isDirectory:&directory]) return 0;
    if (!directory) {
        return [[manager attributesOfItemAtPath:root error:nil][NSFileSize] unsignedLongLongValue];
    }
    unsigned long long total = 0;
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:root]
                                      includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    errorHandler:^BOOL(__unused NSURL *url, __unused NSError *scanError) { return YES; }];
    for (NSURL *url in enumerator) {
        NSNumber *regular = nil;
        NSNumber *bytes = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
        if (regular.boolValue) total += bytes.unsignedLongLongValue;
    }
    return total;
}

static unsigned long long G2MThemeStorageBytes(void) {
    return G2MDirectoryBytes(G2RemoteThemeCacheDirectory) +
           G2MDirectoryBytes(G2OpenThemeLibraryRoot) +
           G2MDirectoryBytes(G2ImportedPacksDirectory) +
           G2MDirectoryBytes(G2MRollbackDirectory);
}

static NSInteger G2MCacheState(NSDictionary *pack) {
    NSString *kind = pack[@"kind"];
    if ([kind isEqualToString:@"builtin"] || [kind isEqualToString:@"gif"] || [kind isEqualToString:@"frames"]) return 1;
    if ([kind isEqualToString:@"remote"]) {
        NSString *path = G2RemoteThemeCachePath(pack);
        if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) return 0;
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        NSString *actual = G2SHA256StringForData(data);
        return data.length == [pack[@"expectedBytes"] unsignedLongLongValue] &&
               [actual isEqualToString:[pack[@"sha256"] lowercaseString]] ? 1 : 2;
    }
    if ([kind isEqualToString:@"sourceDeb"]) {
        NSString *directory = G2OpenThemePackageDirectory(pack);
        if (!directory.length || ![NSFileManager.defaultManager fileExistsAtPath:directory]) return 0;
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:@"metadata.plist"]];
        return [metadata[@"sha256"] isEqualToString:pack[@"sha256"]] ? 1 : 2;
    }
    return 0;
}

static NSString *G2MCategoryForPack(NSDictionary *pack) {
    NSString *text = [[[NSString stringWithFormat:@"%@ %@ %@",
                        pack[@"name"] ?: @"", pack[@"identifier"] ?: @"", pack[@"subtitle"] ?: @""]
                       lowercaseString] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:NSLocale.currentLocale];
    NSArray *anime = @[@"anime", @"pokemon", @"pokémon", @"naruto", @"goku", @"dragon ball", @"one piece", @"manga"];
    NSArray *gaming = @[@"game", @"mario", @"gamecube", @"game boy", @"playstation", @"xbox", @"nintendo", @"controller", @"pixel"];
    NSArray *retro = @[@"retro", @"windows", @"xp", @"classic", @"vhs", @"crt", @"8-bit", @"16-bit", @"boot", @"old"];
    NSArray *minimal = @[@"minimal", @"line", @"ring", @"dot", @"spinner", @"square", @"circle", @"wave", @"simple"];
    NSArray *colorful = @[@"color", @"rainbow", @"neon", @"prismatic", @"star", @"spark", @"gradient", @"glow"];
    for (NSString *token in anime) if ([text containsString:token]) return @"Anime";
    for (NSString *token in gaming) if ([text containsString:token]) return @"Gaming";
    for (NSString *token in retro) if ([text containsString:token]) return @"Retro";
    for (NSString *token in minimal) if ([text containsString:token]) return @"Minimal";
    for (NSString *token in colorful) if ([text containsString:token]) return @"Colorful";
    return @"Abstract";
}

static NSString *G2MSourceText(NSDictionary *pack) {
    NSString *kind = pack[@"kind"];
    if ([kind isEqualToString:@"builtin"]) return @"Offline • Included";
    if ([kind isEqualToString:@"remote"]) {
        NSString *bytes = [NSByteCountFormatter stringFromByteCount:[pack[@"expectedBytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        return [NSString stringWithFormat:@"CC0 built-in • %@", bytes];
    }
    if ([kind isEqualToString:@"sourceDeb"]) {
        NSString *bytes = [NSByteCountFormatter stringFromByteCount:[pack[@"downloadBytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        return [NSString stringWithFormat:@"%@ • %@", pack[@"source"] ?: @"Original Springy repository", bytes];
    }
    if ([kind isEqualToString:@"gif"] || [kind isEqualToString:@"frames"]) return @"Installed / Imported";
    return @"Historical compatibility";
}

static NSArray<NSString *> *G2MFavorites(void) {
    NSArray *value = G2MPreferences()[@"galleryFavorites"];
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static void G2MSetFavorite(NSDictionary *pack, BOOL favorite) {
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:G2MFavorites()];
    NSString *identifier = G2MThemeIdentifier(pack);
    if (favorite) [set addObject:identifier]; else [set removeObject:identifier];
    G2MWritePreferences(@{@"galleryFavorites":set.array}, nil);
}

static void G2MRecordRecent(NSDictionary *pack) {
    NSString *identifier = G2MThemeIdentifier(pack);
    id stored = G2MPreferences()[@"galleryRecent"];
    NSArray *storedRecent = [stored isKindOfClass:NSArray.class] ? stored : @[];
    NSMutableArray *recent = [storedRecent mutableCopy];
    [recent removeObject:identifier];
    [recent insertObject:identifier atIndex:0];
    if (recent.count > 12) [recent removeObjectsInRange:NSMakeRange(12, recent.count - 12)];
    G2MWritePreferences(@{@"galleryRecent":recent,
                         @"lastSelectedTheme":identifier,
                         @"lastSelectedThemeAt":@([[NSDate date] timeIntervalSince1970])}, nil);
}

static BOOL G2MCreateRollbackSnapshot(NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager fileExistsAtPath:G2MActiveGIFPath]) return YES;
    if (![manager createDirectoryAtPath:G2MRollbackDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error]) return NO;
    NSString *stamp = [NSString stringWithFormat:@"%.0f-%@", NSDate.date.timeIntervalSince1970, NSUUID.UUID.UUIDString];
    NSString *gifPath = [G2MRollbackDirectory stringByAppendingPathComponent:[stamp stringByAppendingPathExtension:@"gif"]];
    if (![manager copyItemAtPath:G2MActiveGIFPath toPath:gifPath error:error]) return NO;
    chmod(gifPath.fileSystemRepresentation, 0644);
    NSDictionary *metadata = @{
        @"createdAt":@(NSDate.date.timeIntervalSince1970),
        @"preferences":G2MPreferences(),
        @"source":@"Active.gif"
    };
    [metadata writeToFile:[[gifPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"] atomically:YES];

    NSArray<NSString *> *files = [[manager contentsOfDirectoryAtPath:G2MRollbackDirectory error:nil] filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSString *name, __unused NSDictionary *bindings) {
            return [name.pathExtension.lowercaseString isEqualToString:@"gif"];
        }]];
    files = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *aa = [manager attributesOfItemAtPath:[G2MRollbackDirectory stringByAppendingPathComponent:a] error:nil];
        NSDictionary *bb = [manager attributesOfItemAtPath:[G2MRollbackDirectory stringByAppendingPathComponent:b] error:nil];
        return [bb[NSFileModificationDate] compare:aa[NSFileModificationDate]];
    }];
    for (NSUInteger index = 5; index < files.count; index++) {
        NSString *gif = [G2MRollbackDirectory stringByAppendingPathComponent:files[index]];
        [manager removeItemAtPath:gif error:nil];
        [manager removeItemAtPath:[[gif stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"] error:nil];
    }
    return YES;
}

static BOOL G2MPromotePending(NSDictionary *settings, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSData *data = [NSData dataWithContentsOfFile:G2PendingGIFPath options:NSDataReadingMappedIfSafe error:error];
    if (!data || !G2ValidateGIFData(data, error)) return NO;
    if (!G2MCreateRollbackSnapshot(error)) return NO;

    NSString *newPath = [G2MActiveGIFPath stringByAppendingString:@".modern-new"];
    NSString *oldPath = [G2MActiveGIFPath stringByAppendingString:@".modern-old"];
    [manager removeItemAtPath:newPath error:nil];
    [manager removeItemAtPath:oldPath error:nil];
    if (![data writeToFile:newPath options:NSDataWritingAtomic error:error]) return NO;
    chmod(newPath.fileSystemRepresentation, 0644);
    BOOL hadActive = [manager fileExistsAtPath:G2MActiveGIFPath];
    if (hadActive && ![manager moveItemAtPath:G2MActiveGIFPath toPath:oldPath error:error]) {
        [manager removeItemAtPath:newPath error:nil];
        return NO;
    }
    if (![manager moveItemAtPath:newPath toPath:G2MActiveGIFPath error:error]) {
        if (hadActive) [manager moveItemAtPath:oldPath toPath:G2MActiveGIFPath error:nil];
        return NO;
    }
    [manager removeItemAtPath:oldPath error:nil];
    [manager removeItemAtPath:G2PendingGIFPath error:nil];
    [manager removeItemAtPath:G2PendingMetadataPath error:nil];
    [manager removeItemAtPath:G2MRejectedGIFPath error:nil];

    NSMutableDictionary *updates = [@{@"isEnabled":@YES,
                                      @"pendingReady":@NO,
                                      @"lastAppliedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
    [updates addEntriesFromDictionary:settings ?: @{}];
    if (!G2MWritePreferences(updates, error)) return NO;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), G2MReloadNotification, NULL, NULL, YES);
    return YES;
}

static BOOL G2MRestartProcess(NSString *processName) {
    NSArray<NSString *> *tools = @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"];
    for (NSString *tool in tools) {
        if (![NSFileManager.defaultManager isExecutableFileAtPath:tool]) continue;
        pid_t pid = 0;
        char *argv[] = {(char *)"killall", (char *)"-9", (char *)processName.UTF8String, NULL};
        if (posix_spawn(&pid, tool.fileSystemRepresentation, NULL, NULL, argv, environ) != 0) continue;
        int status = 0;
        if (waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) return YES;
    }
    return NO;
}

@interface G2ModernThemeCell : UITableViewCell
@property (nonatomic, strong) UIImageView *themeImageView;
@property (nonatomic, strong) UILabel *themeTitleLabel;
@property (nonatomic, strong) UILabel *themeSubtitleLabel;
@property (nonatomic, strong) UILabel *themeMetadataLabel;
@property (nonatomic, strong) UILabel *themeBadgeLabel;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, copy) void (^favoriteHandler)(void);
@end

@implementation G2ModernThemeCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.layer.cornerRadius = 16.0;
    self.layer.masksToBounds = YES;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    self.themeImageView = [UIImageView new];
    self.themeImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.themeImageView.backgroundColor = UIColor.blackColor;
    self.themeImageView.layer.cornerRadius = 13.0;
    self.themeImageView.layer.masksToBounds = YES;

    self.themeTitleLabel = [UILabel new];
    self.themeTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.themeTitleLabel.numberOfLines = 1;

    self.themeSubtitleLabel = [UILabel new];
    self.themeSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeSubtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.themeSubtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.themeSubtitleLabel.numberOfLines = 2;

    self.themeMetadataLabel = [UILabel new];
    self.themeMetadataLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeMetadataLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.themeMetadataLabel.textColor = UIColor.tertiaryLabelColor;

    self.themeBadgeLabel = [UILabel new];
    self.themeBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeBadgeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.themeBadgeLabel.textAlignment = NSTextAlignmentCenter;
    self.themeBadgeLabel.layer.cornerRadius = 8.0;
    self.themeBadgeLabel.layer.masksToBounds = YES;

    self.favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.favoriteButton addTarget:self action:@selector(g2m_favoriteTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.contentView addSubview:self.themeImageView];
    [self.contentView addSubview:self.themeTitleLabel];
    [self.contentView addSubview:self.themeSubtitleLabel];
    [self.contentView addSubview:self.themeMetadataLabel];
    [self.contentView addSubview:self.themeBadgeLabel];
    [self.contentView addSubview:self.favoriteButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.themeImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.themeImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.themeImageView.widthAnchor constraintEqualToConstant:94],
        [self.themeImageView.heightAnchor constraintEqualToConstant:94],

        [self.favoriteButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.favoriteButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.favoriteButton.widthAnchor constraintEqualToConstant:34],
        [self.favoriteButton.heightAnchor constraintEqualToConstant:34],

        [self.themeTitleLabel.leadingAnchor constraintEqualToAnchor:self.themeImageView.trailingAnchor constant:13],
        [self.themeTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.favoriteButton.leadingAnchor constant:-6],
        [self.themeTitleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:13],

        [self.themeSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.themeTitleLabel.leadingAnchor],
        [self.themeSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.themeSubtitleLabel.topAnchor constraintEqualToAnchor:self.themeTitleLabel.bottomAnchor constant:4],

        [self.themeMetadataLabel.leadingAnchor constraintEqualToAnchor:self.themeTitleLabel.leadingAnchor],
        [self.themeMetadataLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.themeMetadataLabel.topAnchor constraintEqualToAnchor:self.themeSubtitleLabel.bottomAnchor constant:5],

        [self.themeBadgeLabel.leadingAnchor constraintEqualToAnchor:self.themeTitleLabel.leadingAnchor],
        [self.themeBadgeLabel.topAnchor constraintEqualToAnchor:self.themeMetadataLabel.bottomAnchor constant:6],
        [self.themeBadgeLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        [self.themeBadgeLabel.heightAnchor constraintEqualToConstant:20],
        [self.themeBadgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:72]
    ]];
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.favoriteHandler = nil;
    self.themeImageView.image = nil;
}

- (void)g2m_favoriteTapped {
    if (self.favoriteHandler) self.favoriteHandler();
}

@end

@interface G2MFullscreenPreviewController : UIViewController
@property (nonatomic, strong) NSArray<UIImage *> *frames;
@property (nonatomic, strong) UIColor *previewBackground;
@property (nonatomic, assign) UIViewContentMode previewContentMode;
@property (nonatomic, strong) UIView *deviceFrame;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *phoneConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *tabletConstraints;
@end

@implementation G2MFullscreenPreviewController

- (instancetype)initWithFrames:(NSArray<UIImage *> *)frames background:(UIColor *)background contentMode:(UIViewContentMode)contentMode {
    if ((self = [super init])) {
        _frames = frames;
        _previewBackground = background;
        _previewContentMode = contentMode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Full-Screen Preview";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(g2m_close)];

    UISegmentedControl *device = [[UISegmentedControl alloc] initWithItems:@[@"iPad", @"iPhone"]];
    device.selectedSegmentIndex = 0;
    [device addTarget:self action:@selector(g2m_deviceChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = device;

    self.deviceFrame = [UIView new];
    self.deviceFrame.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceFrame.backgroundColor = UIColor.blackColor;
    self.deviceFrame.layer.cornerRadius = 26.0;
    self.deviceFrame.layer.borderWidth = 6.0;
    self.deviceFrame.layer.borderColor = UIColor.labelColor.CGColor;
    self.deviceFrame.layer.shadowOpacity = 0.25;
    self.deviceFrame.layer.shadowRadius = 18.0;
    [self.view addSubview:self.deviceFrame];

    self.imageView = [UIImageView new];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.backgroundColor = self.previewBackground;
    self.imageView.contentMode = self.previewContentMode;
    self.imageView.clipsToBounds = YES;
    self.imageView.animationImages = self.frames;
    self.imageView.animationDuration = MAX(0.8, self.frames.count * 0.08);
    self.imageView.animationRepeatCount = 0;
    self.imageView.image = self.frames.firstObject;
    [self.deviceFrame addSubview:self.imageView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.deviceFrame.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.deviceFrame.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [self.imageView.leadingAnchor constraintEqualToAnchor:self.deviceFrame.leadingAnchor constant:7],
        [self.imageView.trailingAnchor constraintEqualToAnchor:self.deviceFrame.trailingAnchor constant:-7],
        [self.imageView.topAnchor constraintEqualToAnchor:self.deviceFrame.topAnchor constant:7],
        [self.imageView.bottomAnchor constraintEqualToAnchor:self.deviceFrame.bottomAnchor constant:-7]
    ]];
    self.tabletConstraints = @[
        [self.deviceFrame.widthAnchor constraintEqualToAnchor:safe.widthAnchor multiplier:0.76],
        [self.deviceFrame.heightAnchor constraintEqualToAnchor:self.deviceFrame.widthAnchor multiplier:1.333]
    ];
    self.phoneConstraints = @[
        [self.deviceFrame.widthAnchor constraintEqualToAnchor:safe.widthAnchor multiplier:0.50],
        [self.deviceFrame.heightAnchor constraintEqualToAnchor:self.deviceFrame.widthAnchor multiplier:2.05]
    ];
    [NSLayoutConstraint activateConstraints:self.tabletConstraints];
    [self.imageView startAnimating];
}

- (void)g2m_deviceChanged:(UISegmentedControl *)sender {
    [NSLayoutConstraint deactivateConstraints:self.phoneConstraints];
    [NSLayoutConstraint deactivateConstraints:self.tabletConstraints];
    [NSLayoutConstraint activateConstraints:sender.selectedSegmentIndex == 0 ? self.tabletConstraints : self.phoneConstraints];
    [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)g2m_close { [self dismissViewControllerAnimated:YES completion:nil]; }

@end

@interface G2MComparisonController : UIViewController
@property (nonatomic, strong) NSArray<UIImage *> *frames;
@property (nonatomic, strong) UIColor *previewBackground;
@property (nonatomic, assign) UIViewContentMode previewContentMode;
@end

@implementation G2MComparisonController

- (instancetype)initWithFrames:(NSArray<UIImage *> *)frames background:(UIColor *)background contentMode:(UIViewContentMode)contentMode {
    if ((self = [super init])) {
        _frames = frames;
        _previewBackground = background;
        _previewContentMode = contentMode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Before / After";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(g2m_close)];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 12;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.view addSubview:stack];

    for (NSInteger index = 0; index < 2; index++) {
        UIView *panel = [UIView new];
        panel.backgroundColor = index == 0 ? UIColor.blackColor : self.previewBackground;
        panel.layer.cornerRadius = 20.0;
        panel.clipsToBounds = YES;
        UILabel *label = [UILabel new];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = index == 0 ? @"Apple original" : @"Gif2Ani theme";
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        label.textAlignment = NSTextAlignmentCenter;
        [panel addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
            [label.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
            [label.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16]
        ]];
        if (index == 0) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
            spinner.translatesAutoresizingMaskIntoConstraints = NO;
            spinner.color = UIColor.whiteColor;
            [panel addSubview:spinner];
            [NSLayoutConstraint activateConstraints:@[
                [spinner.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
                [spinner.centerYAnchor constraintEqualToAnchor:panel.centerYAnchor]
            ]];
            [spinner startAnimating];
        } else {
            UIImageView *image = [UIImageView new];
            image.translatesAutoresizingMaskIntoConstraints = NO;
            image.contentMode = self.previewContentMode;
            image.animationImages = self.frames;
            image.animationDuration = MAX(0.8, self.frames.count * 0.08);
            image.animationRepeatCount = 0;
            image.image = self.frames.firstObject;
            [panel addSubview:image];
            [NSLayoutConstraint activateConstraints:@[
                [image.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
                [image.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
                [image.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
                [image.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor]
            ]];
            [image startAnimating];
        }
        [stack addArrangedSubview:panel];
    }

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-20]
    ]];
}

- (void)g2m_close { [self dismissViewControllerAnimated:YES completion:nil]; }

@end

@interface G2ModernApplyReviewController : UIViewController <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) NSDictionary *pack;
@property (nonatomic, strong) NSArray<UIImage *> *frames;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UISegmentedControl *scalingControl;
@property (nonatomic, strong) UISegmentedControl *loopControl;
@property (nonatomic, strong) UISlider *durationSlider;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIButton *backgroundButton;
@property (nonatomic, strong) UIColor *selectedBackground;
@end

@implementation G2ModernApplyReviewController

- (instancetype)initWithPack:(NSDictionary *)pack frames:(NSArray<UIImage *> *)frames {
    if ((self = [super init])) {
        _pack = pack;
        _frames = frames;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Review & Apply";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    NSDictionary *prefs = G2MPreferences();
    NSString *background = self.pack[@"background"] ?: prefs[@"backgroundColor"] ?: @"#000000:1.000";
    NSString *scaling = self.pack[@"scaling"] ?: prefs[@"imageTransformation"] ?: @"resizeAspect";
    self.selectedBackground = G2MColorFromPreference(background);

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];

    UILabel *staged = [UILabel new];
    staged.numberOfLines = 0;
    staged.textAlignment = NSTextAlignmentCenter;
    staged.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    staged.text = [NSString stringWithFormat:@"Staged theme\n%@", self.pack[@"name"] ?: @"Animation"];

    self.imageView = [UIImageView new];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.backgroundColor = self.selectedBackground;
    self.imageView.contentMode = G2MContentMode(scaling);
    self.imageView.clipsToBounds = YES;
    self.imageView.layer.cornerRadius = 20.0;
    self.imageView.animationImages = self.frames;
    self.imageView.animationDuration = MAX(0.8, self.frames.count * 0.08);
    self.imageView.animationRepeatCount = 0;
    self.imageView.image = self.frames.firstObject;
    [self.imageView startAnimating];

    UILabel *scalingLabel = [self g2m_label:@"Scaling"];
    self.scalingControl = [[UISegmentedControl alloc] initWithItems:@[@"Fit", @"Fill", @"Stretch", @"Center"]];
    NSArray *scales = @[@"resizeAspect", @"resizeAspectFill", @"resize", @"center"];
    NSInteger scaleIndex = [scales indexOfObject:scaling];
    self.scalingControl.selectedSegmentIndex = scaleIndex == NSNotFound ? 0 : scaleIndex;
    [self.scalingControl addTarget:self action:@selector(g2m_scalingChanged) forControlEvents:UIControlEventValueChanged];

    self.backgroundButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backgroundButton setTitle:@"Choose Background Color" forState:UIControlStateNormal];
    self.backgroundButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.backgroundButton.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.backgroundButton.layer.cornerRadius = 12.0;
    [self.backgroundButton addTarget:self action:@selector(g2m_chooseBackground) forControlEvents:UIControlEventTouchUpInside];
    [self.backgroundButton.heightAnchor constraintEqualToConstant:48].active = YES;

    UILabel *durationTitle = [self g2m_label:@"Duration"];
    self.durationLabel = [UILabel new];
    self.durationLabel.textAlignment = NSTextAlignmentCenter;
    self.durationLabel.textColor = UIColor.secondaryLabelColor;
    self.durationSlider = [UISlider new];
    self.durationSlider.minimumValue = 0;
    self.durationSlider.maximumValue = 30;
    self.durationSlider.value = MAX(0, [self.pack[@"customDuration"] ?: prefs[@"customDuration"] floatValue]);
    [self.durationSlider addTarget:self action:@selector(g2m_durationChanged) forControlEvents:UIControlEventValueChanged];
    [self g2m_durationChanged];

    UILabel *loopTitle = [self g2m_label:@"Loop"];
    self.loopControl = [[UISegmentedControl alloc] initWithItems:@[@"Forever", @"1×", @"2×", @"3×", @"5×"]];
    double loop = [self.pack[@"customLoop"] ?: prefs[@"customLoop"] doubleValue];
    self.loopControl.selectedSegmentIndex = loop < 0 ? 0 : (loop <= 1 ? 1 : loop <= 2 ? 2 : loop <= 3 ? 3 : 4);

    UIButton *applyOnly = [self g2m_actionButton:@"Apply Without Respring" selector:@selector(g2m_applyOnly) destructive:NO];
    UIButton *applyRespring = [self g2m_actionButton:@"Apply and Respring" selector:@selector(g2m_applyAndRespring) destructive:NO];
    UIButton *disable = [self g2m_actionButton:@"Emergency Disable (No Respring)" selector:@selector(g2m_emergencyDisable) destructive:YES];

    UILabel *rollback = [UILabel new];
    rollback.numberOfLines = 0;
    rollback.textAlignment = NSTextAlignmentCenter;
    rollback.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    rollback.textColor = UIColor.secondaryLabelColor;
    rollback.text = @"Up to five rollback snapshots are retained automatically before activation.";

    [stack addArrangedSubview:staged];
    [stack addArrangedSubview:self.imageView];
    [stack addArrangedSubview:scalingLabel];
    [stack addArrangedSubview:self.scalingControl];
    [stack addArrangedSubview:self.backgroundButton];
    [stack addArrangedSubview:durationTitle];
    [stack addArrangedSubview:self.durationLabel];
    [stack addArrangedSubview:self.durationSlider];
    [stack addArrangedSubview:loopTitle];
    [stack addArrangedSubview:self.loopControl];
    [stack addArrangedSubview:applyOnly];
    [stack addArrangedSubview:applyRespring];
    [stack addArrangedSubview:disable];
    [stack addArrangedSubview:rollback];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],
        [self.imageView.heightAnchor constraintEqualToConstant:280]
    ]];
}

- (UILabel *)g2m_label:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    return label;
}

- (UIButton *)g2m_actionButton:(NSString *)title selector:(SEL)selector destructive:(BOOL)destructive {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    button.backgroundColor = destructive ? UIColor.systemRedColor : self.view.tintColor;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.layer.cornerRadius = 13.0;
    [button.heightAnchor constraintEqualToConstant:52].active = YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (NSDictionary *)g2m_settings {
    NSArray *loops = @[@(-1), @1, @2, @3, @5];
    return @{
        @"imageTransformation":G2MScalingPreferenceForIndex(self.scalingControl.selectedSegmentIndex),
        @"backgroundColor":G2MPreferenceFromColor(self.selectedBackground),
        @"customDuration":self.durationSlider.value < 0.25 ? @(-1) : @(round(self.durationSlider.value * 4.0) / 4.0),
        @"customLoop":loops[MAX(0, MIN(4, self.loopControl.selectedSegmentIndex))],
        @"lastAppliedTheme":G2MThemeIdentifier(self.pack)
    };
}

- (void)g2m_scalingChanged {
    self.imageView.contentMode = G2MContentMode(G2MScalingPreferenceForIndex(self.scalingControl.selectedSegmentIndex));
}

- (void)g2m_durationChanged {
    self.durationLabel.text = self.durationSlider.value < 0.25 ? @"Original animation timing" :
        [NSString stringWithFormat:@"%.2f seconds", round(self.durationSlider.value * 4.0) / 4.0];
}

- (void)g2m_chooseBackground {
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = YES;
    picker.selectedColor = self.selectedBackground;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    self.selectedBackground = viewController.selectedColor;
    self.imageView.backgroundColor = self.selectedBackground;
}

- (void)g2m_applyOnly { [self g2m_applyAndRestart:NO]; }
- (void)g2m_applyAndRespring { [self g2m_applyAndRestart:YES]; }

- (void)g2m_applyAndRestart:(BOOL)restart {
    NSError *error = nil;
    if (!G2MPromotePending([self g2m_settings], &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apply failed" message:error.localizedDescription ?: @"The staged animation could not be activated." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    G2MRecordRecent(self.pack);
    if (!restart) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Applied without respring" message:@"The animation and settings are active. They will appear on the next respring." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self.navigationController popToRootViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (G2MRestartProcess(@"backboardd")) return;
    if (G2MRestartProcess(@"SpringBoard")) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Applied" message:@"The animation is active, but the restart command was unavailable." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)g2m_emergencyDisable {
    NSError *error = nil;
    if (!G2MWritePreferences(@{@"isEnabled":@NO, @"pendingReady":@NO, @"emergencyDisabledAt":@(NSDate.date.timeIntervalSince1970)}, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Disable failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), G2MReloadNotification, NULL, NULL, YES);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Gif2Ani disabled" message:@"Apple’s normal animation remains in control. No respring was performed." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface G2ModernThemePreviewController : G2ThemePreviewController
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, assign) NSTimeInterval g2mBaseDuration;
@end

@implementation G2ModernThemePreviewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"rectangle.split.2x1"] style:UIBarButtonItemStylePlain target:self action:@selector(g2m_compare)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"] style:UIBarButtonItemStylePlain target:self action:@selector(g2m_fullscreen)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(g2m_restartPreview)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"pause.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(g2m_togglePlayback:)]
    ];

    UIVisualEffectView *controls = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    controls.layer.cornerRadius = 12.0;
    controls.clipsToBounds = YES;
    [self.imageView addSubview:controls];

    self.speedLabel = [UILabel new];
    self.speedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedLabel.textColor = UIColor.whiteColor;
    self.speedLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.speedLabel.text = @"1.0×";
    [controls.contentView addSubview:self.speedLabel];

    self.speedSlider = [UISlider new];
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedSlider.minimumValue = 0.25;
    self.speedSlider.maximumValue = 2.0;
    self.speedSlider.value = 1.0;
    [self.speedSlider addTarget:self action:@selector(g2m_speedChanged) forControlEvents:UIControlEventValueChanged];
    [controls.contentView addSubview:self.speedSlider];

    [NSLayoutConstraint activateConstraints:@[
        [controls.leadingAnchor constraintEqualToAnchor:self.imageView.leadingAnchor constant:12],
        [controls.trailingAnchor constraintEqualToAnchor:self.imageView.trailingAnchor constant:-12],
        [controls.bottomAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:-12],
        [controls.heightAnchor constraintEqualToConstant:42],
        [self.speedLabel.leadingAnchor constraintEqualToAnchor:controls.contentView.leadingAnchor constant:10],
        [self.speedLabel.centerYAnchor constraintEqualToAnchor:controls.contentView.centerYAnchor],
        [self.speedLabel.widthAnchor constraintEqualToConstant:42],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.speedLabel.trailingAnchor constant:5],
        [self.speedSlider.trailingAnchor constraintEqualToAnchor:controls.contentView.trailingAnchor constant:-10],
        [self.speedSlider.centerYAnchor constraintEqualToAnchor:controls.contentView.centerYAnchor]
    ]];
    [self g2m_applyAppearance];
}

- (void)loadPreview {
    [super loadPreview];
    [self g2m_schedulePreviewPolish];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self g2m_schedulePreviewPolish];
}

- (void)g2m_schedulePreviewPolish {
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in @[@0.15, @0.6, @1.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf g2m_applyAppearance];
            if (strongSelf.frames.count > 1) {
                strongSelf.g2mBaseDuration = MAX(0.8, strongSelf.imageView.animationDuration);
                [strongSelf.stageButton setTitle:@"Review & Apply" forState:UIControlStateNormal];
            }
        });
    }
}

- (void)g2m_applyAppearance {
    NSDictionary *prefs = G2MPreferences();
    NSString *background = self.pack[@"background"] ?: prefs[@"backgroundColor"] ?: @"#000000:1.000";
    NSString *scaling = self.pack[@"scaling"] ?: prefs[@"imageTransformation"] ?: @"resizeAspect";
    self.imageView.backgroundColor = G2MColorFromPreference(background);
    self.imageView.contentMode = G2MContentMode(scaling);
}

- (void)g2m_togglePlayback:(UIBarButtonItem *)sender {
    if (self.imageView.isAnimating) {
        [self.imageView stopAnimating];
        sender.image = [UIImage systemImageNamed:@"play.fill"];
    } else {
        [self.imageView startAnimating];
        sender.image = [UIImage systemImageNamed:@"pause.fill"];
    }
}

- (void)g2m_restartPreview {
    [self.imageView stopAnimating];
    self.imageView.image = self.frames.firstObject;
    [self.imageView startAnimating];
}

- (void)g2m_speedChanged {
    CGFloat speed = self.speedSlider.value;
    self.speedLabel.text = [NSString stringWithFormat:@"%.2g×", speed];
    NSTimeInterval base = self.g2mBaseDuration > 0 ? self.g2mBaseDuration : MAX(0.8, self.frames.count * 0.08);
    self.imageView.animationDuration = base / MAX(0.25, speed);
    [self g2m_restartPreview];
}

- (void)g2m_fullscreen {
    if (self.frames.count < 2) return;
    G2MFullscreenPreviewController *controller = [[G2MFullscreenPreviewController alloc] initWithFrames:self.frames background:self.imageView.backgroundColor contentMode:self.imageView.contentMode];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)g2m_compare {
    if (self.frames.count < 2) return;
    G2MComparisonController *controller = [[G2MComparisonController alloc] initWithFrames:self.frames background:self.imageView.backgroundColor contentMode:self.imageView.contentMode];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)stageAnimation {
    NSString *kind = self.pack[@"kind"];
    if (([kind isEqualToString:@"remote"] && G2MCacheState(self.pack) != 1) ||
        ([kind isEqualToString:@"sourceDeb"] && !G2OpenThemeCachedInfo(self.pack))) {
        [super stageAnimation];
        [self g2m_schedulePreviewPolish];
        return;
    }
    if (self.frames.count < 2) {
        [super stageAnimation];
        return;
    }

    self.stageButton.enabled = NO;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    [self.activity startAnimating];
    NSDictionary *pack = self.pack;
    NSArray<UIImage *> *frames = self.frames;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ready = NO;
        NSString *sourcePath = nil;
        NSDictionary *sourceInfo = nil;
        if ([kind isEqualToString:@"gif"]) sourcePath = pack[@"path"];
        else if ([kind isEqualToString:@"remote"]) sourcePath = G2RemoteThemeCachePath(pack);
        else if ([kind isEqualToString:@"sourceDeb"]) {
            sourceInfo = G2OpenThemeCachedInfo(pack);
            if ([sourceInfo[@"kind"] isEqualToString:@"gif"]) sourcePath = sourceInfo[@"path"];
        }
        if (sourcePath.length) {
            ready = G2StageGIFAtPath(sourcePath, pack, &error);
        } else {
            NSString *temporary = [G2MediaDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"Modern-%@.gif", NSUUID.UUID.UUIDString]];
            ready = G2WriteGIF(frames, [NSURL fileURLWithPath:temporary], 0.08, &error);
            if (ready) ready = G2StageGIFAtPath(temporary, pack, &error);
            [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.activity stopAnimating];
            strongSelf.stageButton.enabled = YES;
            [strongSelf.stageButton setTitle:@"Review & Apply" forState:UIControlStateNormal];
            if (!ready) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could not stage animation" message:error.localizedDescription ?: @"The selected theme could not be converted safely." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
                return;
            }
            G2MRecordRecent(pack);
            G2ModernApplyReviewController *review = [[G2ModernApplyReviewController alloc] initWithPack:pack frames:frames];
            [strongSelf.navigationController pushViewController:review animated:YES];
        });
    });
}

@end

@interface G2ModernThemeGalleryController : G2ThemeGalleryController <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *g2mSearchController;
@property (nonatomic, copy) NSString *g2mCategory;
@property (nonatomic, copy) NSString *g2mFilter;
@property (nonatomic, strong) NSArray<NSDictionary *> *g2mRecent;
@property (nonatomic, strong) NSArray<NSDictionary *> *g2mThemes;
@property (nonatomic, strong) NSArray<NSDictionary *> *g2mImported;
@property (nonatomic, strong) NSArray<NSDictionary *> *g2mHistorical;
@property (nonatomic, strong) UIView *g2mHeader;
@property (nonatomic, strong) UILabel *g2mStorageLabel;
@property (nonatomic, strong) NSMutableArray<UIButton *> *g2mCategoryButtons;
@property (nonatomic, strong) NSMutableArray<UIButton *> *g2mFilterButtons;
@end

@implementation G2ModernThemeGalleryController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Animation Gallery";
    self.tableView.rowHeight = 122.0;
    self.tableView.estimatedRowHeight = 122.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderTopPadding = 12.0;
    self.g2mCategory = @"All";
    self.g2mFilter = @"All";

    self.g2mSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.g2mSearchController.searchResultsUpdater = self;
    self.g2mSearchController.obscuresBackgroundDuringPresentation = NO;
    self.g2mSearchController.searchBar.placeholder = @"Search themes, sources, and categories";
    self.navigationItem.searchController = self.g2mSearchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [self g2m_buildHeader];
    [self g2m_buildManageMenu];
    [self g2m_rebuildData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect frame = self.g2mHeader.frame;
    CGFloat width = self.tableView.bounds.size.width;
    if (fabs(frame.size.width - width) > 0.5) {
        frame.size.width = width;
        self.g2mHeader.frame = frame;
        self.tableView.tableHeaderView = self.g2mHeader;
    }
}

- (void)refreshGallery {
    [super refreshGallery];
    [self g2m_scheduleRebuilds];
}

- (void)refreshOpenThemeLibrary {
    [super refreshOpenThemeLibrary];
    [self g2m_scheduleRebuilds];
}

- (void)g2m_scheduleRebuilds {
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in @[@0.25, @1.0, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf g2m_rebuildData];
        });
    }
}

- (UIButton *)g2m_chip:(NSString *)title selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    button.contentEdgeInsets = UIEdgeInsetsMake(7, 12, 7, 12);
    button.layer.cornerRadius = 15.0;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIScrollView *)g2m_chipRow:(NSArray<NSString *> *)titles selector:(SEL)selector storage:(NSMutableArray<UIButton *> *)storage {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsHorizontalScrollIndicator = NO;
    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 8;
    [scroll addSubview:stack];
    for (NSString *title in titles) {
        UIButton *button = [self g2m_chip:title selector:selector];
        [storage addObject:button];
        [stack addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-4],
        [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor constant:-8]
    ]];
    return scroll;
}

- (void)g2m_buildHeader {
    self.g2mHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 132)];
    self.g2mCategoryButtons = [NSMutableArray array];
    self.g2mFilterButtons = [NSMutableArray array];
    UIScrollView *categories = [self g2m_chipRow:@[@"All", @"Abstract", @"Gaming", @"Retro", @"Minimal", @"Colorful", @"Anime"]
                                         selector:@selector(g2m_categoryTapped:) storage:self.g2mCategoryButtons];
    UIScrollView *filters = [self g2m_chipRow:@[@"All", @"Offline", @"Downloaded", @"Not Downloaded", @"Favorites", @"Imported"]
                                      selector:@selector(g2m_filterTapped:) storage:self.g2mFilterButtons];
    self.g2mStorageLabel = [UILabel new];
    self.g2mStorageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.g2mStorageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.g2mStorageLabel.textColor = UIColor.secondaryLabelColor;
    self.g2mStorageLabel.textAlignment = NSTextAlignmentCenter;
    [self.g2mHeader addSubview:categories];
    [self.g2mHeader addSubview:filters];
    [self.g2mHeader addSubview:self.g2mStorageLabel];
    [NSLayoutConstraint activateConstraints:@[
        [categories.leadingAnchor constraintEqualToAnchor:self.g2mHeader.leadingAnchor],
        [categories.trailingAnchor constraintEqualToAnchor:self.g2mHeader.trailingAnchor],
        [categories.topAnchor constraintEqualToAnchor:self.g2mHeader.topAnchor constant:4],
        [categories.heightAnchor constraintEqualToConstant:42],
        [filters.leadingAnchor constraintEqualToAnchor:self.g2mHeader.leadingAnchor],
        [filters.trailingAnchor constraintEqualToAnchor:self.g2mHeader.trailingAnchor],
        [filters.topAnchor constraintEqualToAnchor:categories.bottomAnchor constant:4],
        [filters.heightAnchor constraintEqualToConstant:42],
        [self.g2mStorageLabel.leadingAnchor constraintEqualToAnchor:self.g2mHeader.leadingAnchor constant:12],
        [self.g2mStorageLabel.trailingAnchor constraintEqualToAnchor:self.g2mHeader.trailingAnchor constant:-12],
        [self.g2mStorageLabel.topAnchor constraintEqualToAnchor:filters.bottomAnchor constant:7],
        [self.g2mStorageLabel.heightAnchor constraintEqualToConstant:24]
    ]];
    self.tableView.tableHeaderView = self.g2mHeader;
    [self g2m_updateChipStyles];
}

- (void)g2m_buildManageMenu {
    __weak typeof(self) weakSelf = self;
    UIMenu *menu = [UIMenu menuWithTitle:@"Theme Management" children:@[
        [UIAction actionWithTitle:@"Download All 54 CC0 Themes" image:[UIImage systemImageNamed:@"icloud.and.arrow.down"] identifier:nil handler:^(__unused UIAction *action) { [weakSelf g2m_downloadAllCC0]; }],
        [UIAction actionWithTitle:@"Clear Downloaded Theme Cache" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *action) { [weakSelf g2m_clearCache]; }],
        [UIAction actionWithTitle:@"Rollback History" image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] identifier:nil handler:^(__unused UIAction *action) { [weakSelf g2m_showRollbacks]; }],
        [UIAction actionWithTitle:@"Refresh All Sources" image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(__unused UIAction *action) { [weakSelf refreshAllSources]; }],
        [UIAction actionWithTitle:@"Import Pack" image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(__unused UIAction *action) { [weakSelf importPack]; }]
    ]];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)g2m_categoryTapped:(UIButton *)sender {
    self.g2mCategory = sender.currentTitle ?: @"All";
    [self g2m_updateChipStyles];
    [self g2m_rebuildData];
}

- (void)g2m_filterTapped:(UIButton *)sender {
    self.g2mFilter = sender.currentTitle ?: @"All";
    [self g2m_updateChipStyles];
    [self g2m_rebuildData];
}

- (void)g2m_updateChipStyles {
    for (UIButton *button in self.g2mCategoryButtons) {
        BOOL selected = [button.currentTitle isEqualToString:self.g2mCategory ?: @"All"];
        button.backgroundColor = selected ? self.view.tintColor : UIColor.secondarySystemFillColor;
        [button setTitleColor:selected ? UIColor.whiteColor : self.view.tintColor forState:UIControlStateNormal];
    }
    for (UIButton *button in self.g2mFilterButtons) {
        BOOL selected = [button.currentTitle isEqualToString:self.g2mFilter ?: @"All"];
        button.backgroundColor = selected ? self.view.tintColor : UIColor.secondarySystemFillColor;
        [button setTitleColor:selected ? UIColor.whiteColor : self.view.tintColor forState:UIControlStateNormal];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self g2m_rebuildData];
}

- (BOOL)g2m_packMatches:(NSDictionary *)pack favorites:(NSSet *)favorites {
    NSString *query = self.g2mSearchController.searchBar.text.lowercaseString ?: @"";
    if (query.length) {
        NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@ %@",
                               pack[@"name"] ?: @"", pack[@"subtitle"] ?: @"",
                               pack[@"source"] ?: @"", G2MCategoryForPack(pack)] lowercaseString];
        if (![haystack containsString:query]) return NO;
    }
    if (![self.g2mCategory isEqualToString:@"All"] && ![G2MCategoryForPack(pack) isEqualToString:self.g2mCategory]) return NO;
    NSString *kind = pack[@"kind"];
    NSInteger cache = G2MCacheState(pack);
    if ([self.g2mFilter isEqualToString:@"Offline"] && ![kind isEqualToString:@"builtin"]) return NO;
    if ([self.g2mFilter isEqualToString:@"Downloaded"] && cache != 1) return NO;
    if ([self.g2mFilter isEqualToString:@"Not Downloaded"] && !(([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"]) && cache != 1)) return NO;
    if ([self.g2mFilter isEqualToString:@"Favorites"] && ![favorites containsObject:G2MThemeIdentifier(pack)]) return NO;
    if ([self.g2mFilter isEqualToString:@"Imported"] && !([kind isEqualToString:@"gif"] || [kind isEqualToString:@"frames"])) return NO;
    return YES;
}

- (NSArray<NSDictionary *> *)g2m_filterPacks:(NSArray<NSDictionary *> *)packs favorites:(NSSet *)favorites {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *pack in packs ?: @[]) if ([self g2m_packMatches:pack favorites:favorites]) [result addObject:pack];
    return result;
}

- (void)g2m_rebuildData {
    NSMutableArray *primary = [NSMutableArray arrayWithArray:self.builtIn ?: @[]];
    [primary addObjectsFromArray:self.openThemes ?: @[]];

    NSMutableArray *historical = [NSMutableArray array];
    for (NSDictionary *entry in self.legacy ?: @[]) {
        NSMutableDictionary *pack = [entry mutableCopy];
        pack[@"kind"] = @"legacy";
        pack[@"subtitle"] = [NSString stringWithFormat:@"Legacy compatibility • %@", pack[@"package"] ?: @"package reference"];
        [historical addObject:pack];
    }

    NSSet *favorites = [NSSet setWithArray:G2MFavorites()];
    self.g2mThemes = [self g2m_filterPacks:primary favorites:favorites];
    self.g2mImported = [self g2m_filterPacks:self.discovered ?: @[] favorites:favorites];
    self.g2mHistorical = [self g2m_filterPacks:historical favorites:favorites];

    NSMutableDictionary<NSString *, NSDictionary *> *map = [NSMutableDictionary dictionary];
    for (NSDictionary *pack in [primary arrayByAddingObjectsFromArray:[(self.discovered ?: @[]) arrayByAddingObjectsFromArray:historical]]) {
        map[G2MThemeIdentifier(pack)] = pack;
    }
    NSMutableArray *recent = [NSMutableArray array];
    NSArray *recentIDs = [G2MPreferences()[@"galleryRecent"] isKindOfClass:NSArray.class] ? G2MPreferences()[@"galleryRecent"] : @[];
    for (NSString *identifier in recentIDs) {
        NSDictionary *pack = map[identifier];
        if (pack && [self g2m_packMatches:pack favorites:favorites]) [recent addObject:pack];
        if (recent.count >= 8) break;
    }
    self.g2mRecent = recent;

    unsigned long long bytes = G2MThemeStorageBytes();
    self.g2mStorageLabel.text = [NSString stringWithFormat:@"%@ stored • %lu visible themes",
        [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile],
        (unsigned long)(self.g2mThemes.count + self.g2mImported.count + self.g2mHistorical.count)];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 4; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Recently Used";
    if (section == 1) return @"Built-In & Verified Source Themes";
    if (section == 2) return @"Installed & Imported Packs";
    return @"Historical Compatibility";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0 && !self.g2mRecent.count) return @"Themes you preview or apply will appear here.";
    if (section == 1) return @"Offline, CC0, and original Springy packages remain independently verified.";
    if (section == 2) return @"Imported packs remain separate and persist across tweak upgrades.";
    return @"Historical references are never downloaded or executed automatically.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return self.g2mRecent.count;
    if (section == 1) return self.g2mThemes.count;
    if (section == 2) return self.g2mImported.count;
    return self.g2mHistorical.count;
}

- (NSDictionary *)packAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *array = indexPath.section == 0 ? self.g2mRecent :
                     indexPath.section == 1 ? self.g2mThemes :
                     indexPath.section == 2 ? self.g2mImported : self.g2mHistorical;
    return indexPath.row < (NSInteger)array.count ? array[indexPath.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"G2ModernThemeCell";
    G2ModernThemeCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[G2ModernThemeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    NSDictionary *pack = [self packAtIndexPath:indexPath];
    cell.themeTitleLabel.text = pack[@"name"] ?: @"Animation";
    cell.themeSubtitleLabel.text = pack[@"subtitle"] ?: @"Preview and apply";
    cell.themeMetadataLabel.text = [NSString stringWithFormat:@"%@ • %@", G2MCategoryForPack(pack), G2MSourceText(pack)];

    NSInteger state = G2MCacheState(pack);
    NSString *badge = state == 2 ? @"Update available" :
                      state == 1 ? ([pack[@"kind"] isEqualToString:@"builtin"] ? @"Offline" : @"Downloaded") : @"Not downloaded";
    if ([pack[@"kind"] isEqualToString:@"legacy"]) badge = @"Historical";
    cell.themeBadgeLabel.text = [NSString stringWithFormat:@"  %@  ", badge];
    cell.themeBadgeLabel.backgroundColor = state == 2 ? [UIColor.systemOrangeColor colorWithAlphaComponent:0.18] :
                                           state == 1 ? [UIColor.systemGreenColor colorWithAlphaComponent:0.16] :
                                                        [UIColor.systemBlueColor colorWithAlphaComponent:0.14];
    cell.themeBadgeLabel.textColor = state == 2 ? UIColor.systemOrangeColor :
                                     state == 1 ? UIColor.systemGreenColor : UIColor.systemBlueColor;

    BOOL favorite = [G2MFavorites() containsObject:G2MThemeIdentifier(pack)];
    [cell.favoriteButton setImage:[UIImage systemImageNamed:favorite ? @"heart.fill" : @"heart"] forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    cell.favoriteHandler = ^{
        G2MSetFavorite(pack, !favorite);
        [weakSelf g2m_rebuildData];
    };

    NSString *cacheKey = [NSString stringWithFormat:@"modern-%@-%@", G2MThemeIdentifier(pack), pack[@"sha256"] ?: @""];
    UIImage *cached = [self.thumbnailCache objectForKey:cacheKey];
    if (cached) {
        cell.themeImageView.image = cached;
    } else {
        NSString *kind = pack[@"kind"];
        if ([kind isEqualToString:@"legacy"]) cell.themeImageView.image = [UIImage systemImageNamed:@"archivebox"];
        else if (([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"]) && state != 1) cell.themeImageView.image = [UIImage systemImageNamed:state == 2 ? @"arrow.triangle.2.circlepath.icloud" : @"icloud.and.arrow.down"];
        else {
            cell.themeImageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                UIImage *thumb = nil;
                if ([kind isEqualToString:@"builtin"]) thumb = G2RenderBuiltInFrame(pack[@"style"], 0, 24, CGSizeMake(120, 120));
                else if ([kind isEqualToString:@"remote"]) thumb = G2ThumbnailFromGIF(G2RemoteThemeCachePath(pack), 140);
                else if ([kind isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(pack[@"path"], 140);
                else if ([kind isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(pack[@"path"], 140);
                else if ([kind isEqualToString:@"sourceDeb"]) {
                    NSDictionary *info = G2OpenThemeCachedInfo(pack);
                    if ([info[@"kind"] isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(info[@"path"], 140);
                    else if ([info[@"kind"] isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(info[@"path"], 140);
                }
                if (!thumb) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.thumbnailCache setObject:thumb forKey:cacheKey];
                    G2ModernThemeCell *visible = (G2ModernThemeCell *)[weakSelf.tableView cellForRowAtIndexPath:indexPath];
                    if ([visible isKindOfClass:G2ModernThemeCell.class]) visible.themeImageView.image = thumb;
                });
            });
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *pack = [self packAtIndexPath:indexPath];
    if (!pack) return;
    G2MRecordRecent(pack);
    if ([pack[@"kind"] isEqualToString:@"legacy"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:pack[@"name"]
            message:@"This historical package remains a separate compatibility reference. Import a trusted local file to use it."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Import Pack" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self importPack]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    G2ModernThemePreviewController *preview = [[G2ModernThemePreviewController alloc] initWithPack:pack];
    [self.navigationController pushViewController:preview animated:YES];
    [self g2m_rebuildData];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSDictionary *pack = [self packAtIndexPath:indexPath];
    if (!pack) return nil;
    BOOL favorite = [G2MFavorites() containsObject:G2MThemeIdentifier(pack)];
    UIContextualAction *heart = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:favorite ? @"Unfavorite" : @"Favorite" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completion)(BOOL)) {
        G2MSetFavorite(pack, !favorite);
        [self g2m_rebuildData];
        completion(YES);
    }];
    heart.image = [UIImage systemImageNamed:favorite ? @"heart.slash" : @"heart"];
    NSMutableArray *actions = [NSMutableArray arrayWithObject:heart];
    NSString *kind = pack[@"kind"];
    if (([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"] || [kind isEqualToString:@"gif"] || [kind isEqualToString:@"frames"]) && G2MCacheState(pack) != 0) {
        UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completion)(BOOL)) {
            BOOL success = [self g2m_deletePack:pack];
            completion(success);
        }];
        remove.image = [UIImage systemImageNamed:@"trash"];
        [actions addObject:remove];
    }
    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

- (BOOL)g2m_deletePack:(NSDictionary *)pack {
    NSString *kind = pack[@"kind"];
    NSFileManager *manager = NSFileManager.defaultManager;
    BOOL success = YES;
    if ([kind isEqualToString:@"remote"]) success = ![manager fileExistsAtPath:G2RemoteThemeCachePath(pack)] || [manager removeItemAtPath:G2RemoteThemeCachePath(pack) error:nil];
    else if ([kind isEqualToString:@"sourceDeb"]) success = ![manager fileExistsAtPath:G2OpenThemePackageDirectory(pack)] || [manager removeItemAtPath:G2OpenThemePackageDirectory(pack) error:nil];
    else if (([kind isEqualToString:@"gif"] || [kind isEqualToString:@"frames"]) && [pack[@"path"] hasPrefix:G2ImportedPacksDirectory]) {
        NSString *path = pack[@"path"];
        while (path.length > G2ImportedPacksDirectory.length && ![[path stringByDeletingLastPathComponent] isEqualToString:G2ImportedPacksDirectory]) path = [path stringByDeletingLastPathComponent];
        success = [path hasPrefix:G2ImportedPacksDirectory] && [manager removeItemAtPath:path error:nil];
    }
    [self refreshGallery];
    [self g2m_rebuildData];
    return success;
}

- (void)g2m_downloadAllCC0 {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Download all CC0 themes?"
        message:@"Gif2Ani will download and verify each of the 54 pinned CC0 animations. Existing valid downloads are skipped."
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        self.navigationItem.prompt = @"Downloading verified CC0 themes…";
        NSArray *remote = [self.builtIn filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *pack, __unused NSDictionary *bindings) {
            return [pack[@"kind"] isEqualToString:@"remote"];
        }]];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSUInteger downloaded = 0, failed = 0, skipped = 0;
            NSFileManager *manager = NSFileManager.defaultManager;
            [manager createDirectoryAtPath:G2RemoteThemeCacheDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
            for (NSUInteger index = 0; index < remote.count; index++) {
                NSDictionary *pack = remote[index];
                if (G2MCacheState(pack) == 1) { skipped++; continue; }
                NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
                NSError *error = nil;
                NSData *data = G2RemoteThemeURLIsAllowed(url) ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error] : nil;
                if (!data || !G2RemoteDataMatchesManifest(data, pack, &error) || !G2ValidateGIFData(data, &error)) {
                    failed++;
                } else {
                    NSString *path = G2RemoteThemeCachePath(pack);
                    NSString *temp = [path stringByAppendingString:@".all-download"];
                    [manager removeItemAtPath:temp error:nil];
                    [manager removeItemAtPath:path error:nil];
                    if ([data writeToFile:temp options:NSDataWritingAtomic error:&error] &&
                        [manager moveItemAtPath:temp toPath:path error:&error]) {
                        chmod(path.fileSystemRepresentation, 0644);
                        downloaded++;
                    } else failed++;
                    [manager removeItemAtPath:temp error:nil];
                }
                if (index % 5 == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.navigationItem.prompt = [NSString stringWithFormat:@"Verified %lu of %lu CC0 themes…", (unsigned long)(index + 1), (unsigned long)remote.count];
                    });
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navigationItem.prompt = nil;
                [self g2m_rebuildData];
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"CC0 download finished"
                    message:[NSString stringWithFormat:@"%lu downloaded • %lu already valid • %lu failed", (unsigned long)downloaded, (unsigned long)skipped, (unsigned long)failed]
                    preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:done animated:YES completion:nil];
            });
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)g2m_clearCache {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Clear downloaded theme cache?"
        message:@"Downloaded CC0 and Springy artwork will be removed. Offline themes, imports, active animation, favorites, and rollback history are preserved."
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Clear Cache" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [NSFileManager.defaultManager removeItemAtPath:G2RemoteThemeCacheDirectory error:nil];
        [NSFileManager.defaultManager removeItemAtPath:G2OpenThemeLibraryRoot error:nil];
        [self.thumbnailCache removeAllObjects];
        [self g2m_rebuildData];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)g2m_showRollbacks {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSString *> *files = [[manager contentsOfDirectoryAtPath:G2MRollbackDirectory error:nil] filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSString *name, __unused NSDictionary *bindings) {
            return [name.pathExtension.lowercaseString isEqualToString:@"gif"];
        }]];
    files = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *aa = [manager attributesOfItemAtPath:[G2MRollbackDirectory stringByAppendingPathComponent:a] error:nil];
        NSDictionary *bb = [manager attributesOfItemAtPath:[G2MRollbackDirectory stringByAppendingPathComponent:b] error:nil];
        return [bb[NSFileModificationDate] compare:aa[NSFileModificationDate]];
    }];
    if (!files.count) {
        UIAlertController *none = [UIAlertController alertControllerWithTitle:@"No rollback snapshots" message:@"Snapshots are created automatically before each new animation is activated." preferredStyle:UIAlertControllerStyleAlert];
        [none addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:none animated:YES completion:nil];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Rollback History" message:@"Choose a snapshot to stage for review." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *file in files) {
        NSString *path = [G2MRollbackDirectory stringByAppendingPathComponent:file];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
        NSString *title = [NSDateFormatter localizedStringFromDate:attributes[NSFileModificationDate] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSError *error = nil;
            NSDictionary *pack = @{@"identifier":[@"rollback-" stringByAppendingString:file],
                                   @"name":[NSString stringWithFormat:@"Rollback %@", title],
                                   @"kind":@"gif", @"path":path,
                                   @"subtitle":@"Saved active-animation snapshot"};
            if (!G2StageGIFAtPath(path, pack, &error)) {
                UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"Rollback staging failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [failed addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:failed animated:YES completion:nil];
                return;
            }
            G2ModernThemePreviewController *preview = [[G2ModernThemePreviewController alloc] initWithPack:pack];
            [self.navigationController pushViewController:preview animated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
