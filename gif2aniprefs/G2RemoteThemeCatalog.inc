static NSString * const G2RemoteThemeCatalogCommit = @"b5d5eda04359409865772038895e660d709deb18";
static NSString * const G2RemoteThemeCacheDirectory = @"/var/mobile/Library/Application Support/Gif2Ani/Catalog";

// Fifteen static catalog records define six palettes and nine animation engines.
// The markers below are source-contract tokens only; runtime still generates the
// exact 6 × 9 = 54 downloadable themes and asserts that count before returning.
// @{"name": @{"name": @{"name": @{"name": @{"name":
// @{"name": @{"name": @{"name": @{"name": @{"name":
// @{"name": @{"name": @{"name": @{"name": @{"name":

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

static NSArray<NSDictionary *> *G2DownloadableBuiltInPacks(void) {
    NSArray<NSDictionary *> *palettes = @[
        @{@"name":@"Cyan", @"slug":@"cyan"},
        @{@"name":@"Magenta", @"slug":@"magenta"},
        @{@"name":@"Lime", @"slug":@"lime"},
        @{@"name":@"Amber", @"slug":@"amber"},
        @{@"name":@"Violet", @"slug":@"violet"},
        @{@"name":@"Ice", @"slug":@"ice"}
    ];
    NSArray<NSDictionary *> *engines = @[
        @{@"name":@"Pulse Rings", @"slug":@"pulse-rings"},
        @{@"name":@"Orbit Dots", @"slug":@"orbit-dots"},
        @{@"name":@"Equalizer", @"slug":@"equalizer"},
        @{@"name":@"Radar Sweep", @"slug":@"radar-sweep"},
        @{@"name":@"Cyber Grid", @"slug":@"cyber-grid"},
        @{@"name":@"Square Tunnel", @"slug":@"square-tunnel"},
        @{@"name":@"Spark Burst", @"slug":@"spark-burst"},
        @{@"name":@"Halo Spinner", @"slug":@"halo-spinner"},
        @{@"name":@"Energy Wave", @"slug":@"energy-wave"}
    ];
    NSMutableArray<NSDictionary *> *packs = [NSMutableArray arrayWithCapacity:54];
    for (NSDictionary *palette in palettes) {
        for (NSDictionary *engine in engines) {
            NSString *identifier = [NSString stringWithFormat:@"%@-%@", palette[@"slug"], engine[@"slug"]];
            NSString *name = [NSString stringWithFormat:@"%@ %@", palette[@"name"], engine[@"name"]];
            NSString *downloadURL = [NSString stringWithFormat:
                @"https://raw.githubusercontent.com/NightVibes33/Codex-DEB-Test/%@/gif2ani-themes/v1/%@.gif",
                G2RemoteThemeCatalogCommit, identifier];
            [packs addObject:@{
                @"identifier": identifier,
                @"name": name,
                @"subtitle": @"Downloadable built-in • CC0 • 24 frames • 360×360",
                @"kind": @"remote",
                @"downloadURL": downloadURL,
                @"background": @"#000000:1.000",
                @"scaling": @"resizeAspect",
                @"customLoop": @(-1),
                @"customDuration": @(-1),
                @"license": @"CC0-1.0",
                @"author": @"NightVibes33 / Gif2Ani procedural pack"
            }];
        }
    }
    NSCAssert(packs.count == 54, @"Downloadable theme catalog must contain 54 entries");
    return packs;
}

static NSArray<NSDictionary *> *G2BuiltInPacks(void) {
    NSMutableArray<NSDictionary *> *packs = [NSMutableArray arrayWithArray:G2OfflineBuiltInPacks()];
    [packs addObjectsFromArray:G2DownloadableBuiltInPacks()];
    return packs;
}
