static NSString * const G2BundledOpenThemeCatalogResource = @"OpenThemeCatalog";

static NSBundle *G2OpenThemeResourceBundle(void) {
    Class controllerClass = NSClassFromString(@"G2ThemeGalleryController");
    NSBundle *bundle = controllerClass ? [NSBundle bundleForClass:controllerClass] : nil;
    if (!bundle || ![bundle URLForResource:G2BundledOpenThemeCatalogResource withExtension:@"json"]) {
        NSBundle *fallback = [NSBundle bundleWithPath:@"/var/jb/Library/PreferenceBundles/Gif2AniPrefs.bundle"];
        if (fallback) bundle = fallback;
    }
    return bundle;
}

static BOOL G2OpenThemeManifestStringMatches(NSString *value, NSString *pattern) {
    if (![value isKindOfClass:NSString.class] || !value.length) return NO;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if (!expression) return NO;
    return [expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)].range.length == value.length;
}

static NSDictionary *G2OpenThemePackFromManifestRecord(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return nil;
    NSString *package = record[@"package"];
    NSString *identifier = record[@"identifier"];
    NSString *name = record[@"name"];
    NSString *version = record[@"version"];
    NSString *filename = record[@"filename"];
    NSString *sourceCommit = [record[@"sourceCommit"] lowercaseString];
    NSString *sha256 = [record[@"sha256"] lowercaseString];
    NSNumber *bytes = record[@"bytes"];
    NSString *sourceLicense = record[@"sourceLicense"];

    if (![identifier isEqualToString:package]) return nil;
    if (!G2OpenThemeManifestStringMatches(package, @"io\\.github\\.virenmohindra\\.[A-Za-z0-9.-]+")) return nil;
    if (![name isKindOfClass:NSString.class] || !name.length) return nil;
    if (![version isKindOfClass:NSString.class]) version = @"";
    if (!G2OpenThemeManifestStringMatches(sha256, @"[0-9a-f]{64}")) return nil;
    if (![bytes isKindOfClass:NSNumber.class] || bytes.unsignedLongLongValue == 0 || bytes.unsignedLongLongValue > G2MaximumArchiveBytes) return nil;
    if (![sourceLicense isEqualToString:@"MIT"]) return nil;
    if (!G2OpenThemeManifestStringMatches(sourceCommit, @"[0-9a-f]{40}")) return nil;
    if (![filename isKindOfClass:NSString.class] ||
        ![filename hasPrefix:@"./debs/"] ||
        ![filename.pathExtension.lowercaseString isEqualToString:@"deb"] ||
        [filename containsString:@".."] ||
        [filename containsString:@"\\"]) return nil;

    NSString *relativePath = [filename substringFromIndex:2];
    NSString *downloadURL = [NSString stringWithFormat:
        @"https://raw.githubusercontent.com/VirenMohindra/CydiaRepo/%@/%@",
        sourceCommit,
        relativePath];
    NSURL *url = [NSURL URLWithString:downloadURL];
    if (!G2OpenThemeURLIsAllowed(url, NO)) return nil;

    NSString *subtitle = [NSString stringWithFormat:@"Original Springy pack • %@ • %.1f MB",
                          version.length ? version : @"unknown version",
                          bytes.doubleValue / (1024.0 * 1024.0)];
    NSString *description = [record[@"description"] isKindOfClass:NSString.class] ? record[@"description"] : @"Animated respring theme for Springy";
    NSString *author = [record[@"author"] isKindOfClass:NSString.class] ? record[@"author"] : @"Viren Mohindra";

    return @{
        @"identifier": identifier,
        @"package": package,
        @"name": name,
        @"subtitle": subtitle,
        @"description": description,
        @"kind": @"sourceDeb",
        @"version": version,
        @"downloadURL": downloadURL,
        @"sha256": sha256,
        @"downloadBytes": bytes,
        @"source": record[@"source"] ?: @"Viren's Repo",
        @"sourceRepository": record[@"sourceRepository"] ?: @"VirenMohindra/CydiaRepo",
        @"sourceCommit": sourceCommit,
        @"license": @"MIT repository license; original credits preserved",
        @"author": author,
        @"depiction": record[@"depiction"] ?: @"",
        @"background": @"#000000:1.000",
        @"scaling": @"resizeAspect",
        @"customLoop": @(-1),
        @"customDuration": @(-1)
    };
}

static NSArray<NSDictionary *> *G2BundledOpenThemeCatalog(void) {
    NSURL *url = [G2OpenThemeResourceBundle() URLForResource:G2BundledOpenThemeCatalogResource withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil] : nil;
    if (!data.length || data.length > 2ULL * 1024ULL * 1024ULL) return @[];
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *records = [manifest[@"themes"] isKindOfClass:NSArray.class] ? manifest[@"themes"] : nil;
    if (![manifest isKindOfClass:NSDictionary.class] || [manifest[@"version"] integerValue] != 1 ||
        [manifest[@"count"] unsignedIntegerValue] != records.count || records.count < 48 ||
        ![manifest[@"sourceRepository"] isEqualToString:@"VirenMohindra/CydiaRepo"] ||
        ![manifest[@"sourceLicense"] isEqualToString:@"MIT"]) return @[];

    NSMutableArray<NSDictionary *> *packs = [NSMutableArray arrayWithCapacity:records.count];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithCapacity:records.count];
    for (NSDictionary *record in records) {
        NSDictionary *pack = G2OpenThemePackFromManifestRecord(record);
        NSString *identifier = pack[@"identifier"];
        if (!pack || [identifiers containsObject:identifier]) return @[];
        [identifiers addObject:identifier];
        [packs addObject:pack];
    }
    return packs.count == records.count ? packs : @[];
}
