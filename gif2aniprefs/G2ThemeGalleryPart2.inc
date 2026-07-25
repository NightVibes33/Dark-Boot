            CGFloat start = m * 0.06;
            CGFloat end = m * (0.15 + 0.28 * fmod(t + ray / 18.0, 1.0));
            CGContextSetStrokeColorWithColor(ctx, G2RGB(1.0, 0.45 + 0.4 * (ray%3)/2.0, 0.1, 0.9).CGColor);
            CGContextSetLineWidth(ctx, 3.0);
            CGContextMoveToPoint(ctx, c.x + cos(angle)*start, c.y + sin(angle)*start);
            CGContextAddLineToPoint(ctx, c.x + cos(angle)*end, c.y + sin(angle)*end);
            CGContextStrokePath(ctx);
        }
    } else if ([style isEqualToString:@"spinner"]) {
        for (NSUInteger segment = 0; segment < 12; segment++) {
            CGFloat angle = (segment / 12.0) * M_PI * 2.0;
            CGFloat alpha = 0.15 + 0.85 * ((segment + 12 - (index % 12)) % 12) / 11.0;
            CGContextSetStrokeColorWithColor(ctx, G2RGB(0.35, 0.75, 1.0, alpha).CGColor);
            CGContextSetLineWidth(ctx, 12.0);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGFloat inner = m * 0.24, outer = m * 0.37;
            CGContextMoveToPoint(ctx, c.x + cos(angle)*inner, c.y + sin(angle)*inner);
            CGContextAddLineToPoint(ctx, c.x + cos(angle)*outer, c.y + sin(angle)*outer);
            CGContextStrokePath(ctx);
        }
    } else if ([style isEqualToString:@"glitch"]) {
        uint32_t seed = (uint32_t)(index * 2654435761u + 17u);
        for (NSUInteger block = 0; block < 18; block++) {
            seed = seed * 1664525u + 1013904223u;
            CGFloat x = (seed % 1000) / 1000.0 * size.width;
            seed = seed * 1664525u + 1013904223u;
            CGFloat y = (seed % 1000) / 1000.0 * size.height;
            seed = seed * 1664525u + 1013904223u;
            CGFloat w = 20 + (seed % 90);
            CGFloat h = 4 + (seed % 24);
            UIColor *color = block % 3 == 0 ? G2RGB(1.0,0.1,0.45,0.8) : (block % 3 == 1 ? G2RGB(0.0,0.9,1.0,0.8) : G2RGB(0.75,0.25,1.0,0.8));
            [color setFill];
            CGContextFillRect(ctx, CGRectMake(x-w/2.0, y-h/2.0, w, h));
        }
    } else if ([style isEqualToString:@"wave"]) {
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.0, 0.9, 1.0, 1.0).CGColor);
        CGContextSetLineWidth(ctx, 5.0);
        CGContextMoveToPoint(ctx, 0, c.y);
        for (NSUInteger x = 0; x <= (NSUInteger)size.width; x += 4) {
            CGFloat y = c.y + sin((x / size.width) * M_PI * 4.0 + t * M_PI * 2.0) * m * 0.16;
            CGContextAddLineToPoint(ctx, x, y);
        }
        CGContextStrokePath(ctx);
    } else if ([style isEqualToString:@"cube"]) {
        CGFloat angle = t * M_PI * 2.0;
        CGFloat side = m * 0.32;
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, c.x, c.y);
        CGContextRotateCTM(ctx, angle);
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.5, 0.3, 1.0, 1.0).CGColor);
        CGContextSetLineWidth(ctx, 6.0);
        CGContextStrokeRect(ctx, CGRectMake(-side/2.0, -side/2.0, side, side));
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.0, 0.85, 1.0, 0.75).CGColor);
        CGContextStrokeRect(ctx, CGRectMake(-side/2.0+24, -side/2.0-24, side, side));
        CGContextRestoreGState(ctx);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static NSArray<UIImage *> *G2BuiltInFrames(NSString *style, CGSize size) {
    NSMutableArray *frames = [NSMutableArray array];
    const NSUInteger count = 24;
    for (NSUInteger index = 0; index < count; index++) {
        UIImage *frame = G2RenderBuiltInFrame(style, index, count, size);
        if (frame) [frames addObject:frame];
    }
    return frames;
}

static NSArray<NSString *> *G2NaturallySortedImageFiles(NSString *directory) {
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSSet *extensions = [NSSet setWithArray:@[@"png",@"jpg",@"jpeg",@"gif",@"webp"]];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in contents) {
        if ([extensions containsObject:name.pathExtension.lowercaseString]) {
            [files addObject:[directory stringByAppendingPathComponent:name]];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a.lastPathComponent compare:b.lastPathComponent options:NSNumericSearch|NSCaseInsensitiveSearch];
    }];
    return files;
}

static UIImage *G2ThumbnailFromGIF(NSString *path, CGFloat maximumDimension) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;
    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize:@(maximumDimension),
        (NSString *)kCGImageSourceShouldCacheImmediately:@YES
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!cg) return nil;
    UIImage *image = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return image;
}

static NSTimeInterval G2NaturalGIFDuration(NSString *path) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return 0;
    NSUInteger count = CGImageSourceGetCount(source);
    NSTimeInterval duration = 0;
    for (NSUInteger index = 0; index < count; index++) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
        NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
        NSNumber *delay = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(NSString *)kCGImagePropertyGIFDelayTime];
        NSTimeInterval value = delay.doubleValue;
        if (!isfinite(value) || value < 0.02) value = 0.10;
        duration += MIN(value, 10.0);
    }
    CFRelease(source);
    return MAX(0.05, duration);
}

static NSArray<UIImage *> *G2FramesFromGIF(NSString *path, CGFloat maximumDimension) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return @[];
    NSUInteger sourceCount = CGImageSourceGetCount(source);
    NSUInteger count = MIN(sourceCount, G2MaximumDecodedFrames);
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize:@(maximumDimension),
        (NSString *)kCGImageSourceShouldCacheImmediately:@YES
    };
    for (NSUInteger outputIndex = 0; outputIndex < count; outputIndex++) {
        size_t sourceIndex = outputIndex;
        if (sourceCount > count && count > 1) {
            sourceIndex = (size_t)llround(((double)outputIndex * (double)(sourceCount - 1)) / (double)(count - 1));
        }
        CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, sourceIndex, (__bridge CFDictionaryRef)options);
        if (!cg) continue;
        UIImage *image = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
        CGImageRelease(cg);
        if (image) [frames addObject:image];
    }
    CFRelease(source);
    return frames;
}

static UIImage *G2ThumbnailFromDirectory(NSString *directory, CGFloat maximumDimension) {
    NSString *path = G2NaturallySortedImageFiles(directory).firstObject;
    if (!path) return nil;
    if ([path.pathExtension.lowercaseString isEqualToString:@"gif"]) return G2ThumbnailFromGIF(path, maximumDimension);
    return G2ScaledImage([UIImage imageWithContentsOfFile:path], maximumDimension);
}

static NSArray<UIImage *> *G2FramesFromDirectory(NSString *directory, CGFloat maximumDimension) {
    NSArray *files = G2NaturallySortedImageFiles(directory);
    if (files.count == 1 && [files.firstObject.pathExtension.lowercaseString isEqualToString:@"gif"]) {
        return G2FramesFromGIF(files.firstObject, maximumDimension);
    }
    NSMutableArray *frames = [NSMutableArray array];
    NSUInteger count = MIN(files.count, G2MaximumDecodedFrames);
    for (NSUInteger outputIndex = 0; outputIndex < count; outputIndex++) {
        NSUInteger sourceIndex = outputIndex;
        if (files.count > count && count > 1) {
            sourceIndex = (NSUInteger)llround(((double)outputIndex * (double)(files.count - 1)) / (double)(count - 1));
        }
        NSString *path = files[sourceIndex];
        UIImage *image = nil;
        if ([path.pathExtension.lowercaseString isEqualToString:@"gif"]) image = G2ThumbnailFromGIF(path, maximumDimension);
        else image = G2ScaledImage([UIImage imageWithContentsOfFile:path], maximumDimension);
        if (image) [frames addObject:image];
    }
    return frames;
}

static NSDictionary *G2ValidateGIFData(NSData *data, NSError **error) {
    if (!data.length || data.length > G2MaximumInputBytes) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The animation must be 25 MB or smaller."}];
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceShouldCache:@NO});
    if (!source) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:2 userInfo:@{NSLocalizedDescriptionKey:@"The generated file is not a readable GIF."}];
        return nil;
    }
    NSUInteger sourceFrames = CGImageSourceGetCount(source);
    NSDictionary *properties = sourceFrames ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
    NSUInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
    CFRelease(source);
    if (!gif || sourceFrames < 2 || sourceFrames > G2MaximumSourceFrames || !width || !height) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:3 userInfo:@{NSLocalizedDescriptionKey:@"The animation does not contain a safe animated GIF sequence."}];
        return nil;
    }
    NSUInteger decodedFrames = MIN(sourceFrames, G2MaximumDecodedFrames);
    double scale = MIN(1.0, (double)G2MaximumPixelDimension / MAX(1.0, (double)MAX(width,height)));
    NSUInteger decodedWidth = MAX((NSUInteger)1, (NSUInteger)ceil(width * scale));
    NSUInteger decodedHeight = MAX((NSUInteger)1, (NSUInteger)ceil(height * scale));
    unsigned long long estimated = (unsigned long long)decodedWidth * decodedHeight * 4ULL * decodedFrames;
    if (estimated > G2MaximumEstimatedDecodedBytes) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:4 userInfo:@{NSLocalizedDescriptionKey:@"This animation would use too much decoded memory on the 2 GB iPad."}];
        return nil;
    }
    return @{@"inputBytes":@(data.length), @"sourceFrames":@(sourceFrames), @"decodedFrames":@(decodedFrames),
             @"sourceWidth":@(width), @"sourceHeight":@(height), @"decodedWidth":@(decodedWidth),
             @"decodedHeight":@(decodedHeight), @"estimatedDecodedBytes":@(estimated),
             @"decoder":@"ImageIO-bounded-thumbnail", @"source":@"theme-gallery"};
}

static BOOL G2WriteGIF(NSArray<UIImage *> *frames, NSURL *destination, NSTimeInterval delay, NSError **error) {
    if (frames.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:5 userInfo:@{NSLocalizedDescriptionKey:@"At least two usable frames are required."}];
        return NO;
    }
