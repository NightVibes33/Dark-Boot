static NSString * const G2BundledSnowBoardCatalogResource = @"SnowBoardCatalog";

static BOOL G2SnowBoardSafeString(NSString *value, NSString *characters) {
    if (![value isKindOfClass:NSString.class] || !value.length) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:characters];
    return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static NSArray<NSDictionary *> *G2BundledSnowBoardCatalog(void) {
    NSURL *url = [G2OpenThemeResourceBundle() URLForResource:G2BundledSnowBoardCatalogResource withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil] : nil;
    if (!data.length || data.length > 4ULL * 1024ULL * 1024ULL) return @[];
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *records = [manifest[@"themes"] isKindOfClass:NSArray.class] ? manifest[@"themes"] : nil;
    if (![manifest isKindOfClass:NSDictionary.class] || [manifest[@"version"] integerValue] != 1 ||
        [manifest[@"count"] unsignedIntegerValue] != records.count || records.count == 0 ||
        ![manifest[@"catalogType"] isEqualToString:@"verified-snowboard-respring"]) return @[];

    NSMutableArray<NSDictionary *> *packs = [NSMutableArray arrayWithCapacity:records.count];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithCapacity:records.count];
    for (NSDictionary *record in records) {
        NSString *identifier = record[@"identifier"];
        NSString *package = record[@"package"];
        NSString *name = record[@"name"];
        NSString *version = record[@"version"];
        NSString *sha256 = [record[@"sha256"] lowercaseString];
        NSNumber *bytes = record[@"bytes"];
        NSString *downloadURL = record[@"downloadURL"];
        NSString *effectiveURL = record[@"effectiveURL"];
        NSString *archiveSubpath = record[@"archiveSubpath"];
        NSNumber *mediaFiles = record[@"mediaFiles"];
        NSURL *sourceURL = [NSURL URLWithString:downloadURL];
        NSURL *finalURL = [NSURL URLWithString:effectiveURL];

        if (!G2SnowBoardSafeString(identifier, @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-") ||
            ![identifier hasPrefix:@"snowboard."] || [identifiers containsObject:identifier]) return @[];
        if (!G2SnowBoardSafeString(package, @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+~-")) return @[];
        if (![name isKindOfClass:NSString.class] || !name.length) return @[];
        if (![version isKindOfClass:NSString.class]) version = @"";
        if (!G2OpenThemeManifestStringMatches(sha256, @"[0-9a-f]{64}")) return @[];
        if (![bytes isKindOfClass:NSNumber.class] || bytes.unsignedLongLongValue == 0 || bytes.unsignedLongLongValue > G2MaximumArchiveBytes) return @[];
        if (![sourceURL.scheme.lowercaseString isEqualToString:@"https"] ||
            ![finalURL.scheme.lowercaseString isEqualToString:@"https"]) return @[];
        if (![archiveSubpath isKindOfClass:NSString.class] || !archiveSubpath.length ||
            [archiveSubpath hasPrefix:@"/"] || [archiveSubpath containsString:@".."] ||
            [archiveSubpath containsString:@"\\"] || ![archiveSubpath.lowercaseString containsString:@".theme"]) return @[];
        if (![mediaFiles isKindOfClass:NSNumber.class] || mediaFiles.unsignedIntegerValue == 0) return @[];

        [identifiers addObject:identifier];
        NSString *subtitle = [NSString stringWithFormat:@"SnowBoard Respring • %@ • %.1f MB",
                              version.length ? version : @"unknown version",
                              bytes.doubleValue / (1024.0 * 1024.0)];
        [packs addObject:@{
            @"identifier": identifier,
            @"package": package,
            @"name": name,
            @"subtitle": subtitle,
            @"description": record[@"description"] ?: @"Verified SnowBoard-compatible respring theme",
            @"kind": @"sourceDeb",
            @"sourceType": @"snowboard",
            @"version": version,
            @"downloadURL": downloadURL,
            @"effectiveURL": effectiveURL,
            @"sha256": sha256,
            @"downloadBytes": bytes,
            @"archiveSubpath": archiveSubpath,
            @"mediaFiles": mediaFiles,
            @"source": record[@"source"] ?: @"Original jailbreak repository",
            @"sourcePage": record[@"sourcePage"] ?: @"",
            @"license": @"Free original package; downloaded from its original public repository and never installed",
            @"author": record[@"author"] ?: @"Original theme author",
            @"background": @"#000000:1.000",
            @"scaling": @"resizeAspect",
            @"customLoop": @(-1),
            @"customDuration": @(-1)
        }];
    }
    [packs sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] compare:right[@"name"] options:NSCaseInsensitiveSearch|NSNumericSearch];
    }];
    return packs;
}

static BOOL G2SnowBoardThemeURLIsAllowed(NSURL *url) {
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.absoluteString.length) return NO;
    static NSSet<NSString *> *allowedURLs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString *> *values = [NSMutableSet set];
        for (NSDictionary *pack in G2BundledSnowBoardCatalog()) {
            NSString *download = pack[@"downloadURL"];
            NSString *effective = pack[@"effectiveURL"];
            if (download.length) [values addObject:download];
            if (effective.length) [values addObject:effective];
        }
        allowedURLs = values.copy;
    });
    return [allowedURLs containsObject:url.absoluteString];
}
