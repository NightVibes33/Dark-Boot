        NSArray *zipTools = @[@"/var/jb/usr/bin/unzip", @"/usr/bin/unzip"];
        listing = G2RunToolCapture(zipTools, @[@"-Z1", archivePath], &code);
        int detailCode = -1;
        NSString *details = G2RunToolCapture(zipTools, @[@"-Z", @"-l", archivePath], &detailCode);
        if (detailCode != 0 || !details) {
            if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:22 userInfo:@{NSLocalizedDescriptionKey:@"The ZIP file attributes could not be inspected safely."}];
            return NO;
        }
        for (NSString *detail in [details componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *trimmed = [detail stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([trimmed hasPrefix:@"l"] || [trimmed hasPrefix:@"h"] || [trimmed hasPrefix:@"c"] ||
                [trimmed hasPrefix:@"b"] || [trimmed hasPrefix:@"p"] || [trimmed hasPrefix:@"s"]) {
                if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:23 userInfo:@{NSLocalizedDescriptionKey:@"ZIP theme archives containing links or special files are not accepted."}];
                return NO;
            }
        }
    } else {
        listing = G2RunToolCapture(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"],
                                   @[@"-c", archivePath], &code);
    }
    if (!listing || code != 0) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:22 userInfo:@{
            NSLocalizedDescriptionKey:@"The archive could not be inspected safely before extraction."
        }];
        return NO;
    }

    NSUInteger entries = 0;
    for (NSString *line in [listing componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (!line.length) continue;
        NSString *entry = line;
        if (!isZip) {
            if ([line hasPrefix:@"l"] || [line hasPrefix:@"h"] || [line hasPrefix:@"c"] ||
                [line hasPrefix:@"b"] || [line hasPrefix:@"p"] || [line hasPrefix:@"s"]) {
                if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:23 userInfo:@{
                    NSLocalizedDescriptionKey:@"DEB theme archives containing links or special files are not accepted."
                }];
                return NO;
            }
            NSRange marker = [line rangeOfString:@" ./" options:NSBackwardsSearch];
            if (marker.location == NSNotFound) continue;
            entry = [line substringFromIndex:marker.location + 1];
            NSRange arrow = [entry rangeOfString:@" -> "];
            if (arrow.location != NSNotFound) entry = [entry substringToIndex:arrow.location];
        }
        entries++;
        if (entries > G2MaximumImportedFiles || !G2ArchivePathIsSafe(entry)) {
            if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:24 userInfo:@{
                NSLocalizedDescriptionKey:@"The archive contains too many files or an unsafe path."
            }];
            return NO;
        }
    }
    if (!entries) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:25 userInfo:@{
            NSLocalizedDescriptionKey:@"The archive did not contain any readable files."
        }];
        return NO;
    }
    return YES;
}

static BOOL G2ValidateExtractedTree(NSString *root, NSError **error) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *prefix = [root.stringByStandardizingPath stringByAppendingString:@"/"];
    NSArray *keys = @[NSURLIsSymbolicLinkKey, NSURLIsRegularFileKey, NSURLFileSizeKey];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:root]
                                      includingPropertiesForKeys:keys
                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    errorHandler:^BOOL(__unused NSURL *url, __unused NSError *scanError) { return NO; }];
    NSUInteger count = 0;
    unsigned long long total = 0;
    for (NSURL *url in enumerator) {
        NSString *standard = url.path.stringByStandardizingPath;
        if (![standard hasPrefix:prefix]) {
            if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:26 userInfo:@{NSLocalizedDescriptionKey:@"An extracted path escaped the import sandbox."}];
            return NO;
        }
        NSNumber *symlink = nil;
        NSNumber *regular = nil;
        NSNumber *size = nil;
        [url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil];
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (symlink.boolValue) {
            if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:27 userInfo:@{NSLocalizedDescriptionKey:@"Imported theme packs may not contain symbolic links."}];
            return NO;
        }
        count++;
        if (regular.boolValue) total += size.unsignedLongLongValue;
        if (count > G2MaximumImportedFiles || total > G2MaximumExtractedBytes) {
            if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:28 userInfo:@{NSLocalizedDescriptionKey:@"The extracted theme pack exceeds the safe file or storage limit."}];
            return NO;
        }
    }
    return count > 0;
}

@interface G2ThemePreviewController : UIViewController
- (instancetype)initWithPack:(NSDictionary *)pack;
@end

@interface G2ThemePreviewController ()
@property (nonatomic, strong) NSDictionary *pack;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *stageButton;
@property (nonatomic, strong) UIActivityIndicatorView *activity;
@property (nonatomic, strong) NSArray<UIImage *> *frames;
@property (nonatomic, assign) NSUInteger previewGeneration;
@end

@implementation G2ThemePreviewController

- (instancetype)initWithPack:(NSDictionary *)pack {
    if ((self = [super init])) _pack = pack;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.pack[@"name"] ?: @"Animation";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.imageView = [UIImageView new];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.backgroundColor = UIColor.blackColor;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.layer.cornerRadius = 18.0;
    self.imageView.layer.masksToBounds = YES;
    [self.view addSubview:self.imageView];

    UILabel *description = [UILabel new];
    description.translatesAutoresizingMaskIntoConstraints = NO;
    description.text = self.pack[@"subtitle"] ?: self.pack[@"package"] ?: @"Preview this animation before staging it.";
    description.textAlignment = NSTextAlignmentCenter;
    description.numberOfLines = 0;
    description.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [self.view addSubview:description];

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [self.view addSubview:self.statusLabel];

    self.stageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stageButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stageButton setTitle:@"Stage This Animation" forState:UIControlStateNormal];
    self.stageButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.stageButton.backgroundColor = self.view.tintColor;
    [self.stageButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.stageButton.layer.cornerRadius = 12.0;
    [self.stageButton addTarget:self action:@selector(stageAnimation) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stageButton];

    self.activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activity.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.activity];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.imageView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [self.imageView.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.imageView.widthAnchor constraintEqualToConstant:300],
        [self.imageView.heightAnchor constraintEqualToConstant:300],
        [description.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:18],
        [description.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [description.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [self.statusLabel.topAnchor constraintEqualToAnchor:description.bottomAnchor constant:10],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [self.stageButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.statusLabel.bottomAnchor constant:22],
        [self.stageButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],
        [self.stageButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],
        [self.stageButton.heightAnchor constraintEqualToConstant:50],
        [self.stageButton.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-24],
        [self.activity.centerXAnchor constraintEqualToAnchor:self.stageButton.centerXAnchor],
        [self.activity.centerYAnchor constraintEqualToAnchor:self.stageButton.centerYAnchor]
    ]];

    [self loadPreview];
}

- (void)loadPreview {
    NSUInteger generation = ++self.previewGeneration;
    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    self.statusLabel.text = @"Preparing bounded preview…";
    [self.activity startAnimating];
    NSDictionary *pack = self.pack;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSArray<UIImage *> *frames = nil;
            NSString *kind = pack[@"kind"];
            if ([kind isEqualToString:@"builtin"]) {
                frames = G2BuiltInFrames(pack[@"style"], CGSizeMake(300,300));
            } else if ([kind isEqualToString:@"gif"]) {
                frames = G2FramesFromGIF(pack[@"path"], 400);
            } else if ([kind isEqualToString:@"frames"]) {
                frames = G2FramesFromDirectory(pack[@"path"], 400);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf || generation != strongSelf.previewGeneration) return;
                [strongSelf.activity stopAnimating];
                strongSelf.frames = frames ?: @[];
                if (strongSelf.frames.count > 1) {
                    strongSelf.imageView.animationImages = strongSelf.frames;
                    NSTimeInterval previewDuration = [pack[@"kind"] isEqualToString:@"gif"] ? G2NaturalGIFDuration(pack[@"path"]) : strongSelf.frames.count * 0.08;
                    strongSelf.imageView.animationDuration = MAX(0.8, previewDuration);
                    strongSelf.imageView.animationRepeatCount = 0;
                    strongSelf.imageView.image = strongSelf.frames.firstObject;
                    [strongSelf.imageView startAnimating];
