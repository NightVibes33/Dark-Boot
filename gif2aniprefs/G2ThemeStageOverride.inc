static BOOL G2StageGIFAtPath(NSString *sourcePath, NSDictionary *recommended, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:NSDataReadingMappedIfSafe error:error];
    NSDictionary *metadata = data ? G2ValidateGIFData(data, error) : nil;
    if (!metadata || !data) return NO;

    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:G2MediaDirectory
             withIntermediateDirectories:YES
                              attributes:@{NSFilePosixPermissions:@0755}
                                   error:error]) return NO;

    NSString *temporaryGIF = [G2PendingGIFPath stringByAppendingString:@".gallery-new"];
    NSString *temporaryMetadata = [G2PendingMetadataPath stringByAppendingString:@".gallery-new"];
    NSString *backupGIF = [G2PendingGIFPath stringByAppendingString:@".gallery-backup"];
    NSString *backupMetadata = [G2PendingMetadataPath stringByAppendingString:@".gallery-backup"];
    for (NSString *path in @[temporaryGIF, temporaryMetadata, backupGIF, backupMetadata]) {
        [manager removeItemAtPath:path error:nil];
    }

    if (![data writeToFile:temporaryGIF options:NSDataWritingAtomic error:error]) return NO;
    NSMutableDictionary *storedMetadata = [metadata mutableCopy];
    if (recommended[@"name"]) storedMetadata[@"themeName"] = recommended[@"name"];
    if (recommended[@"identifier"]) storedMetadata[@"themeIdentifier"] = recommended[@"identifier"];
    if (recommended[@"background"]) storedMetadata[@"recommendedBackground"] = recommended[@"background"];
    if (recommended[@"scaling"]) storedMetadata[@"recommendedScaling"] = recommended[@"scaling"];
    if (recommended[@"customLoop"]) storedMetadata[@"recommendedRepeat"] = recommended[@"customLoop"];
    if (recommended[@"customDuration"]) storedMetadata[@"recommendedDuration"] = recommended[@"customDuration"];
    if (recommended[@"license"]) storedMetadata[@"themeLicense"] = recommended[@"license"];
    if (recommended[@"author"]) storedMetadata[@"themeAuthor"] = recommended[@"author"];
    storedMetadata[@"stagedBy"] = @"Gif2Ani Animation Gallery";
    storedMetadata[@"userSettingsPreserved"] = @YES;

    if (![storedMetadata writeToFile:temporaryMetadata atomically:YES]) {
        [manager removeItemAtPath:temporaryGIF error:nil];
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:8 userInfo:@{
            NSLocalizedDescriptionKey:@"The theme metadata could not be staged."
        }];
        return NO;
    }
    chmod(temporaryGIF.fileSystemRepresentation, 0644);
    chmod(temporaryMetadata.fileSystemRepresentation, 0644);

    BOOL hadGIF = [manager fileExistsAtPath:G2PendingGIFPath];
    BOOL hadMetadata = [manager fileExistsAtPath:G2PendingMetadataPath];
    NSDictionary *oldPrefs = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] ?: @{};
    NSDictionary *oldValues = @{@"pendingReady": oldPrefs[@"pendingReady"] ?: @NO};
    NSError *transactionError = nil;

    if (hadGIF && ![manager moveItemAtPath:G2PendingGIFPath toPath:backupGIF error:&transactionError]) goto rollback;
    if (hadMetadata && ![manager moveItemAtPath:G2PendingMetadataPath toPath:backupMetadata error:&transactionError]) goto rollback;
    if (![manager moveItemAtPath:temporaryGIF toPath:G2PendingGIFPath error:&transactionError]) goto rollback;
    if (![manager moveItemAtPath:temporaryMetadata toPath:G2PendingMetadataPath error:&transactionError]) goto rollback;

    chown(G2PendingGIFPath.fileSystemRepresentation, 501, 501);
    chown(G2PendingMetadataPath.fileSystemRepresentation, 501, 501);
    chmod(G2PendingGIFPath.fileSystemRepresentation, 0644);
    chmod(G2PendingMetadataPath.fileSystemRepresentation, 0644);

    if (!G2WriteGalleryPreferences(@{@"pendingReady":@YES}, &transactionError)) {
        G2WriteGalleryPreferences(oldValues, nil);
        goto rollback;
    }

    [manager removeItemAtPath:backupGIF error:nil];
    [manager removeItemAtPath:backupMetadata error:nil];
    return YES;

rollback:
    [manager removeItemAtPath:G2PendingGIFPath error:nil];
    [manager removeItemAtPath:G2PendingMetadataPath error:nil];
    if (hadGIF && [manager fileExistsAtPath:backupGIF]) {
        [manager moveItemAtPath:backupGIF toPath:G2PendingGIFPath error:nil];
    }
    if (hadMetadata && [manager fileExistsAtPath:backupMetadata]) {
        [manager moveItemAtPath:backupMetadata toPath:G2PendingMetadataPath error:nil];
    }
    [manager removeItemAtPath:temporaryGIF error:nil];
    [manager removeItemAtPath:temporaryMetadata error:nil];
    [manager removeItemAtPath:backupGIF error:nil];
    [manager removeItemAtPath:backupMetadata error:nil];
    if (error) *error = transactionError ?: [NSError errorWithDomain:@"Gif2AniGallery" code:9 userInfo:@{
        NSLocalizedDescriptionKey:@"The theme staging transaction could not be completed and was rolled back."
    }];
    return NO;
}
