    CGImageDestinationRef writer = CGImageDestinationCreateWithURL((__bridge CFURLRef)destination,
                                                                   (__bridge CFStringRef)UTTypeGIF.identifier,
                                                                   frames.count, NULL);
    if (!writer) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:6 userInfo:@{NSLocalizedDescriptionKey:@"ImageIO could not create the staged GIF."}];
        return NO;
    }
    NSDictionary *gifProperties = @{(NSString *)kCGImagePropertyGIFDictionary:@{(NSString *)kCGImagePropertyGIFLoopCount:@0}};
    CGImageDestinationSetProperties(writer, (__bridge CFDictionaryRef)gifProperties);
    NSDictionary *frameProperties = @{(NSString *)kCGImagePropertyGIFDictionary:@{
        (NSString *)kCGImagePropertyGIFDelayTime:@(MAX(0.03, delay)),
        (NSString *)kCGImagePropertyGIFUnclampedDelayTime:@(MAX(0.03, delay))
    }};
    for (UIImage *image in frames) {
        UIImage *scaled = G2ScaledImage(image, G2MaximumPixelDimension);
        if (scaled.CGImage) CGImageDestinationAddImage(writer, scaled.CGImage, (__bridge CFDictionaryRef)frameProperties);
    }
    BOOL finalized = CGImageDestinationFinalize(writer);
    CFRelease(writer);
    if (!finalized && error) {
        *error = [NSError errorWithDomain:@"Gif2AniGallery" code:7 userInfo:@{NSLocalizedDescriptionKey:@"ImageIO could not finish the staged GIF."}];
    }
    return finalized;
}

static BOOL G2WriteGalleryPreferences(NSDictionary *updates, NSError **error) {
    NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    [preferences addEntriesFromDictionary:updates];
    if (![preferences writeToFile:G2PreferencesPath atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:10 userInfo:@{NSLocalizedDescriptionKey:@"The staged theme settings could not be written."}];
        return NO;
    }
    chown(G2PreferencesPath.fileSystemRepresentation, 501, 501);
    chmod(G2PreferencesPath.fileSystemRepresentation, 0644);
    for (NSString *key in updates) {
        id value = updates[key];
        if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                                     (__bridge CFStringRef)G2PreferencesDomain);
        }
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
    NSDictionary *verified = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath];
    for (NSString *key in updates) {
        if (![verified[key] isEqual:updates[key]]) {
            if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:11 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"The %@ theme setting did not survive verification.", key]}];
            return NO;
        }
    }
    return YES;
}

static BOOL G2StageGIFAtPath(NSString *sourcePath, NSDictionary *recommended, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:NSDataReadingMappedIfSafe error:error];
    NSDictionary *metadata = data ? G2ValidateGIFData(data, error) : nil;
    if (!metadata || !data) return NO;

    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:G2MediaDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error]) return NO;
    NSString *temporaryGIF = [G2PendingGIFPath stringByAppendingString:@".gallery-new"];
    NSString *temporaryMetadata = [G2PendingMetadataPath stringByAppendingString:@".gallery-new"];
    NSString *backupGIF = [G2PendingGIFPath stringByAppendingString:@".gallery-backup"];
    NSString *backupMetadata = [G2PendingMetadataPath stringByAppendingString:@".gallery-backup"];
    for (NSString *path in @[temporaryGIF, temporaryMetadata, backupGIF, backupMetadata]) [manager removeItemAtPath:path error:nil];

    if (![data writeToFile:temporaryGIF options:NSDataWritingAtomic error:error]) return NO;
    NSMutableDictionary *storedMetadata = [metadata mutableCopy];
    if (recommended[@"name"]) storedMetadata[@"themeName"] = recommended[@"name"];
    if (recommended[@"identifier"]) storedMetadata[@"themeIdentifier"] = recommended[@"identifier"];
    storedMetadata[@"stagedBy"] = @"Gif2Ani Animation Gallery";
    if (![storedMetadata writeToFile:temporaryMetadata atomically:YES]) {
        [manager removeItemAtPath:temporaryGIF error:nil];
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:8 userInfo:@{NSLocalizedDescriptionKey:@"The theme metadata could not be staged."}];
        return NO;
    }
    chmod(temporaryGIF.fileSystemRepresentation, 0644);
    chmod(temporaryMetadata.fileSystemRepresentation, 0644);

    BOOL hadGIF = [manager fileExistsAtPath:G2PendingGIFPath];
    BOOL hadMetadata = [manager fileExistsAtPath:G2PendingMetadataPath];
    NSError *transactionError = nil;
    NSDictionary *oldPrefs = nil;
    NSDictionary *oldValues = nil;
    NSDictionary *updates = nil;
    if (hadGIF && ![manager moveItemAtPath:G2PendingGIFPath toPath:backupGIF error:&transactionError]) goto rollback;
    if (hadMetadata && ![manager moveItemAtPath:G2PendingMetadataPath toPath:backupMetadata error:&transactionError]) goto rollback;
    if (![manager moveItemAtPath:temporaryGIF toPath:G2PendingGIFPath error:&transactionError]) goto rollback;
    if (![manager moveItemAtPath:temporaryMetadata toPath:G2PendingMetadataPath error:&transactionError]) goto rollback;

    chown(G2PendingGIFPath.fileSystemRepresentation, 501, 501);
    chown(G2PendingMetadataPath.fileSystemRepresentation, 501, 501);
    chmod(G2PendingGIFPath.fileSystemRepresentation, 0644);
    chmod(G2PendingMetadataPath.fileSystemRepresentation, 0644);

    oldPrefs = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] ?: @{};
    oldValues = @{
        @"pendingReady": oldPrefs[@"pendingReady"] ?: @NO,
        @"backgroundColor": oldPrefs[@"backgroundColor"] ?: @"#000000:1.000",
        @"imageTransformation": oldPrefs[@"imageTransformation"] ?: @"resizeAspect"
    };
    updates = @{
        @"pendingReady": @YES,
        @"backgroundColor": recommended[@"background"] ?: oldValues[@"backgroundColor"],
        @"imageTransformation": recommended[@"scaling"] ?: @"resizeAspect"
    };
    if (!G2WriteGalleryPreferences(updates, &transactionError)) {
        G2WriteGalleryPreferences(oldValues, nil);
        goto rollback;
    }

    [manager removeItemAtPath:backupGIF error:nil];
    [manager removeItemAtPath:backupMetadata error:nil];
    return YES;

rollback:
    [manager removeItemAtPath:G2PendingGIFPath error:nil];
    [manager removeItemAtPath:G2PendingMetadataPath error:nil];
    if (hadGIF && [manager fileExistsAtPath:backupGIF]) [manager moveItemAtPath:backupGIF toPath:G2PendingGIFPath error:nil];
    if (hadMetadata && [manager fileExistsAtPath:backupMetadata]) [manager moveItemAtPath:backupMetadata toPath:G2PendingMetadataPath error:nil];
    [manager removeItemAtPath:temporaryGIF error:nil];
    [manager removeItemAtPath:temporaryMetadata error:nil];
    [manager removeItemAtPath:backupGIF error:nil];
    [manager removeItemAtPath:backupMetadata error:nil];
    if (error) *error = transactionError ?: [NSError errorWithDomain:@"Gif2AniGallery" code:9 userInfo:@{NSLocalizedDescriptionKey:@"The theme staging transaction could not be completed and was rolled back."}];
    return NO;
}

static void G2PrepareRootlessToolEnvironment(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        setenv("PATH", "/var/jb/usr/bin:/var/jb/usr/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin", 1);
        setenv("HOME", "/var/mobile", 1);
        setenv("TMPDIR", "/tmp", 1);
        setenv("LC_ALL", "C", 1);
    });
}

static int G2RunTool(NSArray<NSString *> *candidates, NSArray<NSString *> *arguments) {
    G2PrepareRootlessToolEnvironment();
    for (NSString *tool in candidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) continue;
        NSUInteger argc = arguments.count + 2;
        char **argv = calloc(argc, sizeof(char *));
        if (!argv) return -1;
        argv[0] = strdup(tool.lastPathComponent.UTF8String);
        for (NSUInteger i = 0; i < arguments.count; i++) argv[i+1] = strdup(arguments[i].UTF8String);
        argv[argc-1] = NULL;
        pid_t pid = 0;
        int spawnResult = posix_spawn(&pid, tool.fileSystemRepresentation, NULL, NULL, argv, environ);
        for (NSUInteger i = 0; i < argc-1; i++) free(argv[i]);
        free(argv);
        if (spawnResult != 0) continue;
        int status = 0;
        if (waitpid(pid, &status, 0) == pid && WIFEXITED(status)) return WEXITSTATUS(status);
    }
    return -1;
}

static NSString *G2RunToolCapture(NSArray<NSString *> *candidates,
                                  NSArray<NSString *> *arguments,
                                  int *exitCode) {
    G2PrepareRootlessToolEnvironment();
    NSString *token = [[NSUUID UUID] UUIDString];
    NSString *capturePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"gif2ani-capture-%@.txt", token]];
    NSString *errorPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"gif2ani-stderr-%@.txt", token]];
    for (NSString *tool in candidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) continue;
        NSUInteger argc = arguments.count + 2;
        char **argv = calloc(argc, sizeof(char *));
        if (!argv) return nil;
        argv[0] = strdup(tool.lastPathComponent.UTF8String);
        for (NSUInteger i = 0; i < arguments.count; i++) argv[i+1] = strdup(arguments[i].UTF8String);
        argv[argc-1] = NULL;

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, capturePath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_TRUNC, 0600);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, errorPath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_TRUNC, 0600);
        pid_t pid = 0;
        int spawnResult = posix_spawn(&pid, tool.fileSystemRepresentation, &actions, NULL, argv, environ);
        posix_spawn_file_actions_destroy(&actions);
        for (NSUInteger i = 0; i < argc-1; i++) free(argv[i]);
        free(argv);
        if (spawnResult != 0) continue;
        int status = 0;
        int code = -1;
        if (waitpid(pid, &status, 0) == pid && WIFEXITED(status)) code = WEXITSTATUS(status);
        NSData *data = [NSData dataWithContentsOfFile:capturePath];
        [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:errorPath error:nil];
        if (exitCode) *exitCode = code;
        return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    }
    [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:errorPath error:nil];
    if (exitCode) *exitCode = -1;
    return nil;
}

static BOOL G2ArchivePathIsSafe(NSString *entry) {
    NSString *path = [[entry stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([path hasPrefix:@"./"]) path = [path substringFromIndex:2];
    if (!path.length) return YES;
    if ([path hasPrefix:@"/"] || [path hasPrefix:@"~"] || [path containsString:@":"]) return NO;
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    for (NSString *part in parts) {
        if ([part isEqualToString:@".."] || [part isEqualToString:@"."] || !part.length) {
            if ([part isEqualToString:@".."]) return NO;
        }
    }
    return YES;
}

static BOOL G2PreflightArchive(NSString *archivePath, NSString *extension, NSError **error) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:archivePath error:error];
    if (!attributes) return NO;
    unsigned long long bytes = [attributes[NSFileSize] unsignedLongLongValue];
    if (!bytes || bytes > G2MaximumArchiveBytes) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:21 userInfo:@{
            NSLocalizedDescriptionKey:@"Theme archives must be 100 MB or smaller."
        }];
        return NO;
    }

    int code = -1;
    NSString *listing = nil;
    BOOL isZip = [extension isEqualToString:@"zip"];
    if (isZip) {
