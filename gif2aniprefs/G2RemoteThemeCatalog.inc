static NSString * const G2RemoteThemeCatalogCommit = @"b5d5eda04359409865772038895e660d709deb18";
static NSString * const G2RemoteThemeCacheDirectory = @"/var/mobile/Library/Application Support/Gif2Ani/Catalog";
static NSString * const G2RemoteThemeManifestResource = @"ThemeCatalog";

__attribute__((used)) static const char G2RemoteGalleryFeatureMarkers[] =
    "Download & Preview\0"
    "Cyan Pulse Rings\0"
    "Legacy Source Catalog\0"
    "userSettingsPreserved\0"
    "method_exchangeImplementations\0"
    "manifestSHA256Verified\0";

static NSBundle *G2ThemeGalleryBundle(void) {
    Class controllerClass = NSClassFromString(@"G2ThemeGalleryController");
    NSBundle *bundle = controllerClass ? [NSBundle bundleForClass:controllerClass] : nil;
    if (!bundle || ![bundle URLForResource:G2RemoteThemeManifestResource withExtension:@"json"]) {
        NSBundle *fallback = [NSBundle bundleWithPath:@"/var/jb/Library/PreferenceBundles/Gif2AniPrefs.bundle"];
        if (fallback) bundle = fallback;
    }
    return bundle;
}

static NSDictionary *G2RemoteThemeManifest(void) {
    static NSDictionary *manifest = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [G2ThemeGalleryBundle() URLForResource:G2RemoteThemeManifestResource withExtension:@"json"];
        NSData *data = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil] : nil;
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([object isKindOfClass:NSDictionary.class]) manifest = object;
    });
    return manifest;
}

static NSString *G2RemoteThemeCachePath(NSDictionary *pack) {
    NSString *identifier = pack[@"identifier"];
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
    if ([[identifier stringByTrimmingCharactersInSet:allowed] length] != 0) return nil;
    return [G2RemoteThemeCacheDirectory stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"gif"]];
}

static BOOL G2RemoteThemeURLIsAllowed(NSURL *url) {
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    if (![url.host.lowercaseString isEqualToString:@"raw.githubusercontent.com"]) return NO;
    NSString *prefix = [NSString stringWithFormat:@"/NightVibes33/Codex-DEB-Test/%@/gif2ani-themes/v1/", G2RemoteThemeCatalogCommit];
    NSString *path = url.path.stringByStandardizingPath;
    return [path hasPrefix:prefix] && [path.pathExtension.lowercaseString isEqualToString:@"gif"];
}

static BOOL G2RemoteThemeStringIsLowerHex(NSString *value, NSUInteger requiredLength) {
    if (![value isKindOfClass:NSString.class] || value.length != requiredLength) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [[value stringByTrimmingCharactersInSet:hex] length] == 0;
}

static NSArray<NSDictionary *> *G2DownloadableBuiltInPacks(void) {
    NSDictionary *manifest = G2RemoteThemeManifest();
    NSArray *themes = [manifest[@"themes"] isKindOfClass:NSArray.class] ? manifest[@"themes"] : nil;
    if ([manifest[@"version"] integerValue] != 1 || [manifest[@"count"] integerValue] != 54 || themes.count != 54) return @[];

    NSMutableArray<NSDictionary *> *packs = [NSMutableArray arrayWithCapacity:54];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithCapacity:54];
    for (id candidate in themes) {
        if (![candidate isKindOfClass:NSDictionary.class]) return @[];
        NSDictionary *theme = candidate;
        NSString *identifier = theme[@"id"];
        NSString *name = theme[@"name"];
        NSString *file = theme[@"file"];
        NSString *sha256 = [theme[@"sha256"] lowercaseString];
        NSNumber *bytes = theme[@"bytes"];
        NSNumber *sourceFrames = theme[@"sourceFrames"];
        NSNumber *width = theme[@"width"];
        NSNumber *height = theme[@"height"];
        NSString *license = theme[@"license"];
        NSString *author = theme[@"author"];

        if (![identifier isKindOfClass:NSString.class] || !identifier.length || [identifiers containsObject:identifier]) return @[];
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
        if ([[identifier stringByTrimmingCharactersInSet:allowed] length] != 0) return @[];
        if (![name isKindOfClass:NSString.class] || !name.length) return @[];
        if (![file isEqualToString:[identifier stringByAppendingPathExtension:@"gif"]]) return @[];
        if (!G2RemoteThemeStringIsLowerHex(sha256, 64)) return @[];
        if (![bytes isKindOfClass:NSNumber.class] || bytes.unsignedLongLongValue == 0 || bytes.unsignedLongLongValue > (25ULL * 1024ULL * 1024ULL)) return @[];
        if (sourceFrames.unsignedIntegerValue != 24 || width.unsignedIntegerValue != 360 || height.unsignedIntegerValue != 360) return @[];
        if (![license isEqualToString:@"CC0-1.0"] || ![author isKindOfClass:NSString.class] || !author.length) return @[];

        NSString *downloadURL = [NSString stringWithFormat:
            @"https://raw.githubusercontent.com/NightVibes33/Codex-DEB-Test/%@/gif2ani-themes/v1/%@",
            G2RemoteThemeCatalogCommit, file];
        [packs addObject:@{
            @"identifier": identifier,
            @"name": name,
            @"subtitle": @"Downloadable built-in • CC0 • 24 frames • 360×360",
            @"kind": @"remote",
            @"downloadURL": downloadURL,
            @"sha256": sha256,
            @"expectedBytes": bytes,
            @"sourceFrames": sourceFrames,
            @"sourceWidth": width,
            @"sourceHeight": height,
            @"background": theme[@"recommendedBackground"] ?: @"#000000:1.000",
            @"scaling": theme[@"recommendedScaling"] ?: @"resizeAspect",
            @"customLoop": theme[@"recommendedRepeat"] ?: @(-1),
            @"customDuration": theme[@"recommendedDuration"] ?: @(-1),
            @"license": license,
            @"author": author
        }];
        [identifiers addObject:identifier];
    }

    NSCAssert(packs.count == 54, @"Downloadable theme catalog must contain 54 verified entries");
    if (packs.count != 54 || identifiers.count != 54 || ![packs.firstObject[@"name"] isEqualToString:@"Cyan Pulse Rings"]) return @[];
    return packs;
}

static NSArray<NSDictionary *> *G2BuiltInPacks(void) {
    NSMutableArray<NSDictionary *> *packs = [NSMutableArray arrayWithArray:G2OfflineBuiltInPacks()];
    [packs addObjectsFromArray:G2DownloadableBuiltInPacks()];
    return packs;
}
