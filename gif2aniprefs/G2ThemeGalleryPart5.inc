                    strongSelf.statusLabel.text = [NSString stringWithFormat:@"%lu bounded preview frames • staged safely before Apply", (unsigned long)strongSelf.frames.count];
                    strongSelf.stageButton.enabled = YES;
                    strongSelf.stageButton.alpha = 1.0;
                } else {
                    strongSelf.imageView.image = strongSelf.frames.firstObject;
                    strongSelf.statusLabel.text = @"No animation frames were found. Install or import this legacy pack first.";
                    strongSelf.stageButton.enabled = NO;
                    strongSelf.stageButton.alpha = 0.45;
                }
            });
        }
    });
}

- (void)stageAnimation {
    self.stageButton.enabled = NO;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    [self.activity startAnimating];
    NSDictionary *pack = self.pack;
    NSArray<UIImage *> *frames = self.frames;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *temporary = [G2MediaDirectory stringByAppendingPathComponent:@"Gallery-generated.gif"];
        [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error];
        [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
        BOOL ready = NO;
        if (!error && [pack[@"kind"] isEqualToString:@"gif"]) {
            ready = G2StageGIFAtPath(pack[@"path"], pack, &error);
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
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:ready ? @"Animation staged" : @"Could not stage animation"
                                                                           message:ready ? @"The theme is safely staged. Return to Gif2Ani and tap Apply and Respring when ready." : (error.localizedDescription ?: @"The selected theme could not be converted safely.")
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
        });
    });
}

@end

@interface G2ThemeGalleryController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *builtIn;
@property (nonatomic, strong) NSArray<NSDictionary *> *openThemes;
@property (nonatomic, strong) NSArray<NSDictionary *> *discovered;
@property (nonatomic, strong) NSArray<NSDictionary *> *legacy;
@property (nonatomic, assign) BOOL openLibraryLoading;
@property (nonatomic, strong) NSString *openLibraryError;
@property (nonatomic, assign) BOOL importing;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property (nonatomic, assign) NSUInteger scanGeneration;
@end

@implementation G2ThemeGalleryController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Animation Gallery";
    self.tableView.rowHeight = 70.0;
    self.tableView.estimatedRowHeight = 70.0;
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshAllSources)];
    refreshButton.accessibilityLabel = @"Refresh Animation Gallery and Open Theme Library";
    UIBarButtonItem *importButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importPack)];
    importButton.accessibilityLabel = @"Import GIF, ZIP, DEB, or Frame Folder";
    self.navigationItem.rightBarButtonItems = @[refreshButton, importButton];
    self.thumbnailCache = [NSCache new];
    self.thumbnailCache.countLimit = 120;
    self.builtIn = G2BuiltInPacks();
    self.openThemes = G2LoadCachedOpenThemeCatalog();
    self.legacy = G2LegacyCatalog();
    [self refreshGallery];
    [self refreshOpenThemeLibrary];
}

- (void)refreshAllSources {
    [self refreshGallery];
    [self refreshOpenThemeLibrary];
}

- (void)refreshGallery {
    if (self.scanning) return;
    self.scanning = YES;
    NSUInteger generation = ++self.scanGeneration;
    self.navigationItem.prompt = @"Scanning installed theme packs…";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSArray<NSDictionary *> *packs = [strongSelf scanThemeDirectories];
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) current = weakSelf;
                if (!current || generation != current.scanGeneration) return;
                current.discovered = packs ?: @[];
                current.scanning = NO;
                current.navigationItem.prompt = nil;
                [current.tableView reloadData];
            });
        }
    });
}

- (NSArray<NSDictionary *> *)scanThemeDirectories {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:G2ImportedPacksDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    NSArray *roots = @[
        G2ImportedPacksDirectory,
        @"/var/jb/Library/Springy",
        @"/Library/Springy",
        @"/var/jb/Library/Application Support/Springy",
        @"/Library/Application Support/Springy",
        @"/var/jb/Library/Themes",
        @"/Library/Themes"
    ];
    NSMutableArray *packs = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSSet *extensions = [NSSet setWithArray:@[@"png",@"jpg",@"jpeg",@"gif",@"webp"]];
    for (NSString *root in roots) {
        BOOL directory = NO;
        if (![manager fileExistsAtPath:root isDirectory:&directory] || !directory) continue;
        NSUInteger rootDepth = root.pathComponents.count;
        NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:root]
                                         includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                            options:NSDirectoryEnumerationSkipsHiddenFiles
                                                       errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) { return YES; }];
        for (NSURL *url in enumerator) {
            if (url.path.pathComponents.count > rootDepth + 5) {
                [enumerator skipDescendants];
                continue;
            }
            NSNumber *isDirectory = nil;
            [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            if (![isDirectory boolValue]) continue;
            NSArray *files = [manager contentsOfDirectoryAtPath:url.path error:nil] ?: @[];
            NSMutableArray *images = [NSMutableArray array];
            for (NSString *name in files) if ([extensions containsObject:name.pathExtension.lowercaseString]) [images addObject:name];
            if (images.count == 0) continue;
            NSString *lower = url.path.lowercaseString;
            BOOL likelyTheme = [root isEqualToString:G2ImportedPacksDirectory] ||
                               [lower containsString:@"respring"] ||
                               [lower containsString:@"springy"] ||
                               [lower containsString:@"bootlogo"] ||
                               [lower containsString:@".theme"];
            if (!likelyTheme) continue;
            NSString *canonical = url.path.stringByStandardizingPath;
            if ([seen containsObject:canonical]) continue;
            [seen addObject:canonical];
            NSArray<NSString *> *sorted = G2NaturallySortedImageFiles(canonical);
            NSString *kind = (sorted.count == 1 && [sorted.firstObject.pathExtension.lowercaseString isEqualToString:@"gif"]) ? @"gif" : @"frames";
            NSString *path = [kind isEqualToString:@"gif"] ? sorted.firstObject : canonical;
            NSString *name = url.lastPathComponent;
            if ([name.pathExtension.lowercaseString isEqualToString:@"theme"]) name = name.stringByDeletingPathExtension;
            [packs addObject:@{@"identifier":canonical, @"name":name ?: @"Imported Theme",
                               @"subtitle":[NSString stringWithFormat:@"%lu source file%@", (unsigned long)sorted.count, sorted.count == 1 ? @"" : @"s"],
                               @"kind":kind, @"path":path, @"background":@"#000000:1.000", @"scaling":@"resizeAspect"}];
            if (packs.count >= 200) break;
        }
        if (packs.count >= 200) break;
    }
    [packs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];
    return packs;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Built-In • Offline and Downloadable";
    if (section == 1) return @"Open Source Pack Library";
    if (section == 2) return @"Installed or Imported Packs";
    return @"Additional Legacy References";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Twelve offline animations and 54 pinned CC0 downloads are first-class Gif2Ani themes.";
    if (section == 1) return @"Every row downloads its original Springy DEB, verifies SHA-256 and package identity, extracts only safe image content, previews it, and stages it without installing the old package.";
    if (section == 2) return self.discovered.count ? @"Springy, SnowBoard Respring, GIF, frame-folder, ZIP, and DEB packs are detected here." : @"Tap + to import a GIF, ZIP, DEB, or theme folder. Installed Springy and SnowBoard packs are detected automatically.";
    return @"References from other historical repositories remain listed when their original files or redistribution terms cannot be verified.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return self.builtIn.count;
    if (section == 1) return MAX((NSUInteger)1, self.openThemes.count);
    if (section == 2) return MAX((NSUInteger)1, self.discovered.count);
    return self.legacy.count;
}

- (NSDictionary *)packAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return self.builtIn[indexPath.row];
    if (indexPath.section == 1 && self.openThemes.count) return self.openThemes[indexPath.row];
    if (indexPath.section == 2 && self.discovered.count) return self.discovered[indexPath.row];
    if (indexPath.section == 3) {
        NSMutableDictionary *legacy = [self.legacy[indexPath.row] mutableCopy];
        legacy[@"kind"] = @"legacy";
        legacy[@"subtitle"] = [NSString stringWithFormat:@"Legacy package: %@", legacy[@"package"]];
        return legacy;
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"G2ThemeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section == 1 && self.openThemes.count == 0) {
        cell.textLabel.text = self.openLibraryLoading ? @"Loading original Springy packs…" : @"Open theme library unavailable";
        cell.detailTextLabel.text = self.openLibraryLoading ? @"Reading and validating the original repository index" : (self.openLibraryError ?: @"Tap to retry the original source");
        cell.detailTextLabel.numberOfLines = 2;
        cell.imageView.image = [UIImage systemImageNamed:self.openLibraryLoading ? @"arrow.triangle.2.circlepath" : @"exclamationmark.icloud"];
        cell.accessoryType = self.openLibraryLoading ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.section == 2 && self.discovered.count == 0) {
        cell.textLabel.text = self.scanning ? @"Scanning installed packs…" : @"No imported packs yet";
        cell.detailTextLabel.text = self.scanning ? @"This runs outside the Settings UI thread" : @"Tap + to import or install a compatible theme";
        cell.imageView.image = [UIImage systemImageNamed:self.scanning ? @"hourglass" : @"square.and.arrow.down"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
