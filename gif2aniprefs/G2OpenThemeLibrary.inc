#import <CommonCrypto/CommonDigest.h>

static NSString * const G2OpenThemeLibraryRoot = @"/var/mobile/Library/Application Support/Gif2Ani/OpenThemeLibrary";
static NSString * const G2OpenThemeIndexCachePath = @"/var/mobile/Library/Application Support/Gif2Ani/OpenThemeLibrary/catalog.plist";
static NSString * const G2OpenThemeIndexURLString = @"https://virenmohindra.github.io/Packages";

static BOOL G2StringContainsOnlyCharacters(NSString *value, NSCharacterSet *allowed) {
    if (![value isKindOfClass:NSString.class] || !value.length) return NO;
    return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static NSString * const G2OpenThemePinnedRawHost = @"raw.githubusercontent.com";
static NSString * const G2OpenThemePinnedRawPrefix = @"/VirenMohindra/CydiaRepo/c507a391f193c2bb362ff77fc1c1673c0da2dcae/debs/";

static BOOL G2OpenThemeURLIsAllowed(NSURL *url, BOOL indexURL) {
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.stringByStandardizingPath;
    if (indexURL) {
        return [host isEqualToString:@"virenmohindra.github.io"] && [path isEqualToString:@"/Packages"];
    }
    if ([host isEqualToString:@"virenmohindra.github.io"]) {
        return [path hasPrefix:@"/debs/"] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
    }
    if ([host isEqualToString:G2OpenThemePinnedRawHost]) {
        return [path hasPrefix:G2OpenThemePinnedRawPrefix] && [path.pathExtension.lowercaseString isEqualToString:@"deb"];
    }
    return NO;
}

static NSString *G2SHA256ForData(NSData *data) {
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

static NSDictionary<NSString *, NSString *> *G2ParseDeb822Stanza(NSString *stanza) {
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    NSString *lastKey = nil;
    for (NSString *rawLine in [stanza componentsSeparatedByString:@"\n"]) {
        if (!rawLine.length) continue;
        if (([rawLine hasPrefix:@" "] || [rawLine hasPrefix:@"\t"]) && lastKey.length) {
            NSString *continuation = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (continuation.length) fields[lastKey] = [NSString stringWithFormat:@"%@ %@", fields[lastKey] ?: @"", continuation];
            continue;
        }
        NSRange separator = [rawLine rangeOfString:@":"];
        if (separator.location == NSNotFound || separator.location == 0) continue;
        NSString *key = [rawLine substringToIndex:separator.location];
        NSString *value = [[rawLine substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (key.length && value.length) {
            fields[key] = value;
            lastKey = key;
        }
    }
    return fields;
}

static NSString *G2DisplayNameForOpenTheme(NSString *rawName, NSString *package) {
    NSString *name = rawName.length ? rawName : package;
    NSRange marker = [name rangeOfString:@" - Springy BootLogo"];
    if (marker.location != NSNotFound) {
        NSString *suffix = [name substringFromIndex:NSMaxRange(marker)];
        name = [[name substringToIndex:marker.location] stringByAppendingString:suffix];
    }
    return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray<NSDictionary *> *G2OpenThemePacksFromIndexData(NSData *data, NSError **error) {
    if (!data.length || data.length > 2ULL * 1024ULL * 1024ULL) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:60 userInfo:@{NSLocalizedDescriptionKey:@"The open-theme package index is empty or unexpectedly large."}];
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:61 userInfo:@{NSLocalizedDescriptionKey:@"The open-theme package index is not valid UTF-8 text."}];
        return nil;
    }
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSArray<NSString *> *stanzas = [text componentsSeparatedByString:@"\n\n"];
    NSMutableArray<NSDictionary *> *packs = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSCharacterSet *packageCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    NSCharacterSet *hexCharacters = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];

    for (NSString *stanza in stanzas) {
        NSDictionary<NSString *, NSString *> *fields = G2ParseDeb822Stanza(stanza);
        NSString *package = fields[@"Package"];
        NSString *depends = fields[@"Depends"];
        NSString *filename = fields[@"Filename"];
        NSString *sha256 = fields[@"SHA256"];
        unsigned long long size = strtoull(fields[@"Size"].UTF8String ?: "0", NULL, 10);
        if (![depends containsString:@"com.aditkamath.springy"]) continue;
        if (![package hasPrefix:@"io.github.virenmohindra."] || !G2StringContainsOnlyCharacters(package, packageCharacters)) continue;
        if (![filename hasPrefix:@"./debs/"] || ![filename.pathExtension.lowercaseString isEqualToString:@"deb"] || [filename containsString:@".."] || [filename containsString:@"\\"]) continue;
        if (sha256.length != 64 || !G2StringContainsOnlyCharacters(sha256, hexCharacters)) continue;
        if (!size || size > G2MaximumArchiveBytes) continue;
        if ([seen containsObject:package]) continue;

        NSString *relative = [filename substringFromIndex:2];
        NSURL *downloadURL = [NSURL URLWithString:[@"https://virenmohindra.github.io/" stringByAppendingString:relative]];
        if (!G2OpenThemeURLIsAllowed(downloadURL, NO)) continue;
        [seen addObject:package];
        NSString *displayName = G2DisplayNameForOpenTheme(fields[@"Name"], package);
        NSString *credit = fields[@"Description"] ?: @"Animated respring theme for Springy";
        NSString *subtitle = [NSString stringWithFormat:@"Original Springy pack • %@ • %.1f MB", fields[@"Version"] ?: @"unknown version", (double)size / (1024.0 * 1024.0)];
        [packs addObject:@{
            @"identifier": package,
            @"package": package,
            @"name": displayName.length ? displayName : package,
            @"subtitle": subtitle,
            @"description": credit,
            @"kind": @"sourceDeb",
            @"version": fields[@"Version"] ?: @"",
            @"downloadURL": downloadURL.absoluteString,
            @"sha256": sha256.lowercaseString,
            @"downloadBytes": @(size),
            @"source": @"Viren's Repo",
            @"sourceRepository": @"VirenMohindra/CydiaRepo",
            @"license": @"MIT repository license; original credits preserved",
            @"background": @"#000000:1.000",
            @"scaling": @"resizeAspect",
            @"customLoop": @(-1),
            @"customDuration": @(-1)
        }];
    }
    [packs sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] compare:right[@"name"] options:NSCaseInsensitiveSearch|NSNumericSearch];
    }];
    if (packs.count < 40) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:62 userInfo:@{NSLocalizedDescriptionKey:@"The original repository returned an incomplete Springy catalog."}];
        return nil;
    }
    return packs;
}

static void G2WriteOpenThemeCatalogCache(NSArray<NSDictionary *> *packs) {
    if (!packs.count) return;
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:G2OpenThemeLibraryRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    [packs writeToFile:G2OpenThemeIndexCachePath atomically:YES];
    chown(G2OpenThemeIndexCachePath.fileSystemRepresentation, 501, 501);
    chmod(G2OpenThemeIndexCachePath.fileSystemRepresentation, 0644);
}

static NSArray<NSDictionary *> *G2LoadCachedOpenThemeCatalog(void) {
    NSArray *packs = [NSArray arrayWithContentsOfFile:G2OpenThemeIndexCachePath];
    if (![packs isKindOfClass:NSArray.class] || packs.count < 40) return @[];
    NSMutableArray *safe = [NSMutableArray array];
    for (NSDictionary *pack in packs) {
        NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
        if ([pack[@"kind"] isEqualToString:@"sourceDeb"] && G2OpenThemeURLIsAllowed(url, NO)) [safe addObject:pack];
    }
    return safe.count >= 40 ? safe : @[];
}

static NSString *G2OpenThemePackageDirectory(NSDictionary *pack) {
    NSString *package = pack[@"package"];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if (![package hasPrefix:@"io.github.virenmohindra."] || !G2StringContainsOnlyCharacters(package, allowed)) return nil;
    return [G2OpenThemeLibraryRoot stringByAppendingPathComponent:package];
}

static NSDictionary *G2OpenThemeCachedInfo(NSDictionary *pack) {
    NSString *directory = G2OpenThemePackageDirectory(pack);
    if (!directory.length) return nil;
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:@"metadata.plist"]];
    if (![metadata[@"package"] isEqualToString:pack[@"package"]] || ![metadata[@"sha256"] isEqualToString:pack[@"sha256"]]) return nil;
    NSString *relative = metadata[@"relativePath"];
    NSString *kind = metadata[@"kind"];
    if (![relative isKindOfClass:NSString.class] || !relative.length || [relative containsString:@".."] || [relative hasPrefix:@"/"]) return nil;
    NSString *path = [[directory stringByAppendingPathComponent:relative] stringByStandardizingPath];
    NSString *prefix = [[directory stringByStandardizingPath] stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) return nil;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) return nil;
    if ([kind isEqualToString:@"gif"] && isDirectory) return nil;
    if ([kind isEqualToString:@"frames"] && (!isDirectory || G2NaturallySortedImageFiles(path).count < 2)) return nil;
    NSMutableDictionary *result = [metadata mutableCopy];
    result[@"path"] = path;
    return result;
}

static NSInteger G2AnimationCandidateScore(NSString *path, NSUInteger count, BOOL gif) {
    NSString *lower = path.lowercaseString;
    NSInteger score = gif ? 100000 : MIN((NSUInteger)5000, count) * 10;
    if ([lower containsString:@"springy"]) score += 4000;
    if ([lower containsString:@"respring"]) score += 3500;
    if ([lower containsString:@"bootlogo"]) score += 3000;
    if ([lower containsString:@"animation"]) score += 1500;
    if ([lower containsString:@"preview"] || [lower containsString:@"icon"]) score -= 5000;
    return score;
}

static NSDictionary *G2BestAnimationCandidateInTree(NSString *root) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *directories = [NSMutableArray arrayWithObject:root];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:root]
                                      includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) { return YES; }];
    for (NSURL *url in enumerator) {
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) [directories addObject:url.path];
        if (directories.count > G2MaximumImportedFiles) break;
    }

    NSDictionary *best = nil;
    NSInteger bestScore = NSIntegerMin;
    for (NSString *directory in directories) {
        NSArray<NSString *> *files = G2NaturallySortedImageFiles(directory);
        if (!files.count) continue;
        for (NSString *file in files) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"gif"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
            if (!G2ValidateGIFData(data, nil)) continue;
            NSInteger score = G2AnimationCandidateScore(file, 1, YES);
            if (score > bestScore) {
                bestScore = score;
                best = @{@"kind":@"gif", @"path":file};
            }
        }
        if (files.count >= 2) {
            NSInteger score = G2AnimationCandidateScore(directory, files.count, NO);
            if (score > bestScore) {
                bestScore = score;
                best = @{@"kind":@"frames", @"path":directory, @"count":@(files.count)};
            }
        }
    }
    return best;
}

static BOOL G2NormalizeOpenThemeCandidate(NSDictionary *candidate, NSDictionary *pack, NSError **error) {
    NSString *finalDirectory = G2OpenThemePackageDirectory(pack);
    if (!finalDirectory.length) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:70 userInfo:@{NSLocalizedDescriptionKey:@"The package identifier is not safe."}];
        return NO;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:G2OpenThemeLibraryRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    NSString *staging = [G2OpenThemeLibraryRoot stringByAppendingPathComponent:[NSString stringWithFormat:@".ready-%@", NSUUID.UUID.UUIDString]];
    if (![manager createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error]) return NO;

    BOOL success = NO;
    NSString *relativePath = nil;
    NSString *kind = candidate[@"kind"];
    NSString *sourcePath = candidate[@"path"];
    if ([kind isEqualToString:@"gif"]) {
        relativePath = @"Animation.gif";
        NSString *destination = [staging stringByAppendingPathComponent:relativePath];
        success = [manager copyItemAtPath:sourcePath toPath:destination error:error];
        if (success) {
            NSData *data = [NSData dataWithContentsOfFile:destination options:NSDataReadingMappedIfSafe error:error];
            success = data && G2ValidateGIFData(data, error);
        }
    } else if ([kind isEqualToString:@"frames"]) {
        relativePath = @"Frames";
        NSString *destination = [staging stringByAppendingPathComponent:relativePath];
        success = [manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error];
        NSArray<NSString *> *files = G2NaturallySortedImageFiles(sourcePath);
        NSUInteger outputCount = MIN(files.count, G2MaximumSourceFrames);
        for (NSUInteger outputIndex = 0; success && outputIndex < outputCount; outputIndex++) {
            NSUInteger sourceIndex = outputIndex;
            if (files.count > outputCount && outputCount > 1) sourceIndex = (NSUInteger)llround(((double)outputIndex * (double)(files.count - 1)) / (double)(outputCount - 1));
            NSString *source = files[sourceIndex];
            NSString *extension = source.pathExtension.lowercaseString.length ? source.pathExtension.lowercaseString : @"png";
            NSString *name = [NSString stringWithFormat:@"%04lu.%@", (unsigned long)outputIndex, extension];
            success = [manager copyItemAtPath:source toPath:[destination stringByAppendingPathComponent:name] error:error];
        }
        if (success) success = G2FramesFromDirectory(destination, 400).count > 1;
        if (!success && error && !*error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:71 userInfo:@{NSLocalizedDescriptionKey:@"The package did not contain at least two usable animation frames."}];
    }

    if (success) {
        NSDictionary *metadata = @{
            @"package": pack[@"package"] ?: @"",
            @"version": pack[@"version"] ?: @"",
            @"sha256": pack[@"sha256"] ?: @"",
            @"kind": kind ?: @"",
            @"relativePath": relativePath ?: @"",
            @"source": pack[@"source"] ?: @"",
            @"license": pack[@"license"] ?: @"",
            @"cachedAt": @([[NSDate date] timeIntervalSince1970])
        };
        success = [metadata writeToFile:[staging stringByAppendingPathComponent:@"metadata.plist"] atomically:YES];
        if (!success && error && !*error) *error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:72 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded theme metadata could not be saved."}];
    }
    if (success) {
        NSString *backup = [finalDirectory stringByAppendingString:@".old"];
        [manager removeItemAtPath:backup error:nil];
        if ([manager fileExistsAtPath:finalDirectory]) [manager moveItemAtPath:finalDirectory toPath:backup error:nil];
        success = [manager moveItemAtPath:staging toPath:finalDirectory error:error];
        if (success) [manager removeItemAtPath:backup error:nil];
        else if ([manager fileExistsAtPath:backup]) [manager moveItemAtPath:backup toPath:finalDirectory error:nil];
    }
    [manager removeItemAtPath:staging error:nil];
    return success && G2OpenThemeCachedInfo(pack) != nil;
}

@implementation G2ThemeGalleryController (G2OpenThemeLibrary)

- (void)refreshOpenThemeLibrary {
    if (self.openLibraryLoading) return;
    self.openLibraryLoading = YES;
    self.openLibraryError = nil;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];

    NSURL *url = [NSURL URLWithString:G2OpenThemeIndexURLString];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 20.0;
    configuration.timeoutIntervalForResource = 30.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSError *error = networkError;
        NSArray<NSDictionary *> *packs = nil;
        NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!error && (!G2OpenThemeURLIsAllowed(response.URL, YES) || statusCode != 200)) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:63 userInfo:@{NSLocalizedDescriptionKey:@"The original theme repository returned an unexpected response or redirect."}];
        }
        if (!error) packs = G2OpenThemePacksFromIndexData(data, &error);
        if (packs.count) G2WriteOpenThemeCatalogCache(packs);
        [session finishTasksAndInvalidate];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (packs.count) strongSelf.openThemes = packs;
            strongSelf.openLibraryLoading = NO;
            strongSelf.openLibraryError = packs.count ? nil : (error.localizedDescription ?: @"The original theme library could not be refreshed.");
            [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
        });
    }];
    [task resume];
}

@end

@implementation G2ThemePreviewController (G2OpenThemeLibrary)

- (void)g2_downloadOpenTheme {
    NSDictionary *pack = self.pack;
    NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
    if (!G2OpenThemeURLIsAllowed(url, NO)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download blocked" message:@"This pack does not point to the verified original theme repository." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.stageButton.enabled = NO;
    self.stageButton.alpha = 0.45;
    [self.stageButton setTitle:@"" forState:UIControlStateNormal];
    self.statusLabel.text = @"Downloading the original pack and verifying its SHA-256…";
    [self.activity startAnimating];

    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 45.0;
    configuration.timeoutIntervalForResource = 90.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSError *error = networkError;
        BOOL success = NO;
        NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!error && (!G2OpenThemeURLIsAllowed(response.URL, NO) || statusCode != 200)) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:73 userInfo:@{NSLocalizedDescriptionKey:@"The original repository returned an unexpected response or redirect."}];
        }
        unsigned long long expectedMaximum = MIN(G2MaximumArchiveBytes, [pack[@"downloadBytes"] unsignedLongLongValue] + 65536ULL);
        if (!error && (!data.length || data.length > expectedMaximum)) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:74 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded package size does not match the verified catalog."}];
        }
        NSString *actualSHA = !error ? G2SHA256ForData(data) : nil;
        if (!error && ![actualSHA isEqualToString:pack[@"sha256"]]) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:75 userInfo:@{NSLocalizedDescriptionKey:@"SHA-256 verification failed. The package was not opened or cached."}];
        }

        NSFileManager *manager = NSFileManager.defaultManager;
        NSString *work = [G2OpenThemeLibraryRoot stringByAppendingPathComponent:[NSString stringWithFormat:@".download-%@", NSUUID.UUID.UUIDString]];
        NSString *debPath = [work stringByAppendingPathComponent:@"theme.deb"];
        NSString *extractRoot = [work stringByAppendingPathComponent:@"Extracted"];
        if (!error && ![manager createDirectoryAtPath:extractRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) success = NO;
        if (!error && ![data writeToFile:debPath options:NSDataWritingAtomic error:&error]) success = NO;
        if (!error) {
            int code = -1;
            NSString *packageID = [G2RunToolCapture(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-f", debPath, @"Package"], &code) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (code != 0 || ![packageID isEqualToString:pack[@"package"]]) {
                error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:76 userInfo:@{NSLocalizedDescriptionKey:@"The downloaded DEB package identifier does not match the selected theme."}];
            }
        }
        if (!error && !G2PreflightArchive(debPath, @"deb", &error)) success = NO;
        if (!error && G2RunTool(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-x", debPath, extractRoot]) != 0) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:77 userInfo:@{NSLocalizedDescriptionKey:@"The verified theme package could not be extracted."}];
        }
        if (!error && !G2ValidateExtractedTree(extractRoot, &error)) success = NO;
        NSDictionary *candidate = !error ? G2BestAnimationCandidateInTree(extractRoot) : nil;
        if (!error && !candidate) {
            error = [NSError errorWithDomain:@"Gif2AniOpenLibrary" code:78 userInfo:@{NSLocalizedDescriptionKey:@"The package did not contain a compatible animated GIF or frame sequence."}];
        }
        if (!error) success = G2NormalizeOpenThemeCandidate(candidate, pack, &error);
        [manager removeItemAtPath:work error:nil];
        [session finishTasksAndInvalidate];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.activity stopAnimating];
            if (success) {
                [strongSelf loadPreview];
            } else {
                strongSelf.statusLabel.text = error.localizedDescription ?: @"The source-backed theme could not be downloaded safely.";
                [strongSelf.stageButton setTitle:@"Retry Download" forState:UIControlStateNormal];
                strongSelf.stageButton.enabled = YES;
                strongSelf.stageButton.alpha = 1.0;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download failed" message:error.localizedDescription ?: @"The source-backed theme could not be downloaded safely." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
    [task resume];
}

@end
