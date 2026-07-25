    NSDictionary *pack = [self packAtIndexPath:indexPath];
    cell.textLabel.text = pack[@"name"];
    cell.detailTextLabel.text = pack[@"subtitle"];
    cell.detailTextLabel.numberOfLines = 2;
    NSString *cacheKey = pack[@"identifier"] ?: [NSString stringWithFormat:@"legacy-%@", pack[@"package"] ?: pack[@"name"]];
    UIImage *cached = [self.thumbnailCache objectForKey:cacheKey];
    if (cached) {
        cell.imageView.image = cached;
    } else if ([pack[@"kind"] isEqualToString:@"legacy"]) {
        cell.imageView.image = [UIImage systemImageNamed:@"archivebox"];
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                UIImage *thumb = nil;
                if ([pack[@"kind"] isEqualToString:@"builtin"]) thumb = G2RenderBuiltInFrame(pack[@"style"], 0, 24, CGSizeMake(64,64));
                else if ([pack[@"kind"] isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(pack[@"path"], 96);
                else if ([pack[@"kind"] isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(pack[@"path"], 96);
                if (!thumb) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    typeof(self) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf.thumbnailCache setObject:thumb forKey:cacheKey];
                    UITableViewCell *visible = [strongSelf.tableView cellForRowAtIndexPath:indexPath];
                    NSDictionary *currentPack = [strongSelf packAtIndexPath:indexPath];
                    NSString *currentKey = currentPack[@"identifier"] ?: [NSString stringWithFormat:@"legacy-%@", currentPack[@"package"] ?: currentPack[@"name"]];
                    if ([currentKey isEqualToString:cacheKey]) visible.imageView.image = thumb;
                });
            }
        });
    }
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.layer.masksToBounds = YES;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && self.discovered.count == 0) {
        [self importPack];
        return;
    }
    NSDictionary *pack = [self packAtIndexPath:indexPath];
    if ([pack[@"kind"] isEqualToString:@"legacy"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:pack[@"name"]
                                                                       message:[NSString stringWithFormat:@"%@ is a known free Springy pack, but no open redistribution license was published. Import its original DEB, ZIP, GIF, or frame folder to make it previewable without rehosting someone else’s artwork.", pack[@"package"]]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Import Pack File" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self importPack]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    G2ThemePreviewController *preview = [[G2ThemePreviewController alloc] initWithPack:pack];
    [self.navigationController pushViewController:preview animated:YES];
}

- (void)importPack {
    if (self.importing) return;
    self.importing = YES;
    NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObjects:UTTypeGIF, UTTypeZIP, UTTypeFolder, nil];
    for (NSString *extension in @[@"deb",@"theme"]) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type) [types addObject:type];
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.importing = NO;
    (void)controller;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    self.importing = NO;
    if (!urls.count) return;
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:G2ImportedPacksDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSMutableArray<NSString *> *failures = [NSMutableArray array];
            NSUInteger imported = 0;
            for (NSURL *url in urls) {
                @autoreleasepool {
                    BOOL scoped = [url startAccessingSecurityScopedResource];
                    NSString *safeName = url.lastPathComponent.length ? url.lastPathComponent : [[NSUUID UUID] UUIDString];
                    NSString *baseName = safeName.stringByDeletingPathExtension.length ? safeName.stringByDeletingPathExtension : @"Imported-Pack";
                    NSString *identifier = [NSString stringWithFormat:@"%@-%@", baseName, [[NSUUID UUID] UUIDString]];
                    NSString *work = [G2ImportedPacksDirectory stringByAppendingPathComponent:[@".importing-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
                    NSString *destination = [G2ImportedPacksDirectory stringByAppendingPathComponent:identifier];
                    NSError *error = nil;
                    BOOL success = [manager createDirectoryAtPath:work withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error];
                    NSString *extension = url.pathExtension.lowercaseString;
                    NSNumber *isDirectory = nil;
                    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

                    if (success && ([extension isEqualToString:@"deb"] || [extension isEqualToString:@"zip"])) {
                        NSString *local = [work stringByAppendingPathComponent:safeName];
                        success = [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:local] error:&error];
                        if (success) success = G2PreflightArchive(local, extension, &error);
                        NSString *extractRoot = [work stringByAppendingPathComponent:@"Extracted"];
                        if (success) success = [manager createDirectoryAtPath:extractRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error];
                        if (success && [extension isEqualToString:@"deb"]) {
                            success = G2RunTool(@[@"/var/jb/usr/bin/dpkg-deb", @"/usr/bin/dpkg-deb"], @[@"-x", local, extractRoot]) == 0;
                        } else if (success) {
                            success = G2RunTool(@[@"/var/jb/usr/bin/unzip", @"/usr/bin/unzip"], @[@"-qq", @"-o", local, @"-d", extractRoot]) == 0;
                        }
                        if (success) success = G2ValidateExtractedTree(extractRoot, &error);
                        [manager removeItemAtPath:local error:nil];
                        if (success) {
                            [manager removeItemAtPath:destination error:nil];
                            success = [manager moveItemAtPath:extractRoot toPath:destination error:&error];
                        }
                    } else if (success && isDirectory.boolValue) {
                        NSString *copied = [work stringByAppendingPathComponent:safeName];
                        success = [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:copied] error:&error];
                        if (success) success = G2ValidateExtractedTree(work, &error);
                        if (success) {
                            [manager removeItemAtPath:destination error:nil];
                            success = [manager moveItemAtPath:work toPath:destination error:&error];
                            work = nil;
                        }
                    } else if (success) {
                        NSDictionary *attributes = [manager attributesOfItemAtPath:url.path error:nil];
                        if ([attributes[NSFileSize] unsignedLongLongValue] > G2MaximumArchiveBytes) {
                            success = NO;
                            error = [NSError errorWithDomain:@"Gif2AniGallery" code:29 userInfo:@{NSLocalizedDescriptionKey:@"Imported files must be 100 MB or smaller."}];
                        }
                        if (success) {
                            NSString *local = [work stringByAppendingPathComponent:safeName];
                            success = [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:local] error:&error];
                        }
                        if (success) success = G2ValidateExtractedTree(work, &error);
                        if (success) {
                            [manager removeItemAtPath:destination error:nil];
                            success = [manager moveItemAtPath:work toPath:destination error:&error];
                            work = nil;
                        }
                    }
                    if (scoped) [url stopAccessingSecurityScopedResource];
                    if (success) imported++;
                    else [failures addObject:error.localizedDescription ?: safeName];
                    if (work.length) [manager removeItemAtPath:work error:nil];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf refreshGallery];
                NSString *message = [NSString stringWithFormat:@"Imported %lu pack file%@.%@", (unsigned long)imported, imported == 1 ? @"" : @"s",
                                     failures.count ? [NSString stringWithFormat:@"\n\n%lu item%@ could not be imported safely.\n%@", (unsigned long)failures.count, failures.count == 1 ? @"" : @"s", [failures componentsJoinedByString:@"\n"]] : @""];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:imported ? @"Import finished" : @"Import failed"
                                                                               message:message
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            });
        }
    });
    (void)controller;
}

@end
