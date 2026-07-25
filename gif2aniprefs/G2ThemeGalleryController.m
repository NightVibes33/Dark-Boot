#import "G2ThemeGalleryController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <math.h>
#import <stdio.h>
#import <unistd.h>

extern char **environ;

static NSString * const G2PreferencesDomain = @"com.nightvibes33.gif2ani";
static NSString * const G2PreferencesPath = @"/var/mobile/Library/Preferences/com.nightvibes33.gif2ani.plist";
static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2PendingGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Pending.gif";
static NSString * const G2PendingMetadataPath = @"/var/mobile/Library/Application Support/Gif2Ani/pending-metadata.plist";
static NSString * const G2ImportedPacksDirectory = @"/var/mobile/Library/Application Support/Gif2Ani/Packs";
static const NSUInteger G2MaximumSourceFrames = 240;
static const NSUInteger G2MaximumDecodedFrames = 24;
static const NSUInteger G2MaximumPixelDimension = 640;
static const unsigned long long G2MaximumInputBytes = 25ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumEstimatedDecodedBytes = 48ULL * 1024ULL * 1024ULL;

static NSArray<NSDictionary *> *G2BuiltInPacks(void) {
    return @[
        @{@"identifier":@"pulse-rings", @"name":@"Pulse Rings", @"subtitle":@"Expanding neon rings", @"kind":@"builtin", @"style":@"pulse", @"background":@"#000000:1.000"},
        @{@"identifier":@"orbit-dots", @"name":@"Orbit Dots", @"subtitle":@"Eight orbiting light points", @"kind":@"builtin", @"style":@"orbit", @"background":@"#000000:1.000"},
        @{@"identifier":@"neon-bars", @"name":@"Neon Bars", @"subtitle":@"Rhythmic vertical light bars", @"kind":@"builtin", @"style":@"bars", @"background":@"#000000:1.000"},
        @{@"identifier":@"radar-sweep", @"name":@"Radar Sweep", @"subtitle":@"Rotating radar beam", @"kind":@"builtin", @"style":@"radar", @"background":@"#001008:1.000"},
        @{@"identifier":@"cyber-grid", @"name":@"Cyber Grid", @"subtitle":@"Scrolling perspective grid", @"kind":@"builtin", @"style":@"grid", @"background":@"#000000:1.000"},
        @{@"identifier":@"square-tunnel", @"name":@"Square Tunnel", @"subtitle":@"Infinite glowing tunnel", @"kind":@"builtin", @"style":@"tunnel", @"background":@"#000000:1.000"},
        @{@"identifier":@"equalizer", @"name":@"Equalizer", @"subtitle":@"Animated audio-style bars", @"kind":@"builtin", @"style":@"equalizer", @"background":@"#000000:1.000"},
        @{@"identifier":@"spark-burst", @"name":@"Spark Burst", @"subtitle":@"Radial energy particles", @"kind":@"builtin", @"style":@"spark", @"background":@"#000000:1.000"},
        @{@"identifier":@"halo-spinner", @"name":@"Halo Spinner", @"subtitle":@"Segmented luminous halo", @"kind":@"builtin", @"style":@"spinner", @"background":@"#000000:1.000"},
        @{@"identifier":@"glitch-blocks", @"name":@"Glitch Blocks", @"subtitle":@"Digital block distortion", @"kind":@"builtin", @"style":@"glitch", @"background":@"#000000:1.000"},
        @{@"identifier":@"energy-wave", @"name":@"Energy Wave", @"subtitle":@"Moving neon waveform", @"kind":@"builtin", @"style":@"wave", @"background":@"#000000:1.000"},
        @{@"identifier":@"rotating-cube", @"name":@"Rotating Cube", @"subtitle":@"Minimal rotating cube illusion", @"kind":@"builtin", @"style":@"cube", @"background":@"#000000:1.000"}
    ];
}

static NSArray<NSDictionary *> *G2LegacyCatalog(void) {
    return @[
        @{@"name":@"Alone", @"package":@"io.github.virenmohindra.alone"},
        @{@"name":@"Apple Glitch", @"package":@"io.github.virenmohindra.apple-glitch"},
        @{@"name":@"Bipolar Balls", @"package":@"io.github.virenmohindra.bipolar-balls"},
        @{@"name":@"Black Hole", @"package":@"io.github.virenmohindra.black-hole"},
        @{@"name":@"Blue", @"package":@"io.github.virenmohindra.blue"},
        @{@"name":@"Boo", @"package":@"io.github.virenmohindra.boo"},
        @{@"name":@"Bubbles", @"package":@"io.github.virenmohindra.bubbles"},
        @{@"name":@"Columns", @"package":@"io.github.virenmohindra.columns"},
        @{@"name":@"Complicated", @"package":@"io.github.virenmohindra.complicated"},
        @{@"name":@"Donuts", @"package":@"io.github.virenmohindra.donuts"},
        @{@"name":@"Ducky", @"package":@"io.github.virenmohindra.ducky"},
        @{@"name":@"Fall Leaves", @"package":@"io.github.virenmohindra.fall-leaves"},
        @{@"name":@"Fluid", @"package":@"io.github.virenmohindra.fluid"},
        @{@"name":@"Fragments", @"package":@"io.github.virenmohindra.fragments"},
        @{@"name":@"Funny Computer", @"package":@"io.github.virenmohindra.funny-computer"},
        @{@"name":@"Game Boy Advance", @"package":@"io.github.virenmohindra.gameboy-advance"},
        @{@"name":@"Glitchy", @"package":@"io.github.virenmohindra.glitchy-reuploaded"},
        @{@"name":@"Hello Again", @"package":@"io.github.virenmohindra.hello-again"},
        @{@"name":@"InfiniCube", @"package":@"io.github.virenmohindra.infinicube"},
        @{@"name":@"Joker", @"package":@"io.github.virenmohindra.joker"},
        @{@"name":@"Lines", @"package":@"io.github.virenmohindra.lines"},
        @{@"name":@"Loading", @"package":@"io.github.virenmohindra.loading"},
        @{@"name":@"Mograph", @"package":@"io.github.virenmohindra.mograph"},
        @{@"name":@"Particules Head", @"package":@"io.github.virenmohindra.particules-head"},
        @{@"name":@"Pizza", @"package":@"io.github.virenmohindra.pizza"},
        @{@"name":@"Pokémon", @"package":@"io.github.virenmohindra.pokemon"},
        @{@"name":@"Prismatic Head", @"package":@"io.github.virenmohindra.prismatic-head"},
        @{@"name":@"Rainy", @"package":@"io.github.virenmohindra.rainy"},
        @{@"name":@"Routine", @"package":@"io.github.virenmohindra.routine"},
        @{@"name":@"Spikey", @"package":@"io.github.virenmohindra.spikey"},
        @{@"name":@"Sploosh", @"package":@"io.github.virenmohindra.sploosh"},
        @{@"name":@"Super Mario", @"package":@"io.github.virenmohindra.super-mario"},
        @{@"name":@"Time And Money", @"package":@"io.github.virenmohindra.time-and-money"},
        @{@"name":@"Upload", @"package":@"io.github.virenmohindra.upload"},
        @{@"name":@"Yin And Yang", @"package":@"io.github.virenmohindra.yin-and-yang"}
    ];
}

static UIColor *G2RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIImage *G2ScaledImage(UIImage *image, CGFloat maximumDimension) {
    if (!image) return nil;
    CGSize source = image.size;
    CGFloat maximum = MAX(source.width, source.height);
    if (maximum <= maximumDimension || maximum <= 0) return image;
    CGFloat scale = maximumDimension / maximum;
    CGSize target = CGSizeMake(MAX(1.0, floor(source.width * scale)), MAX(1.0, floor(source.height * scale)));
    UIGraphicsBeginImageContextWithOptions(target, NO, 1.0);
    [image drawInRect:(CGRect){CGPointZero, target}];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static UIImage *G2RenderBuiltInFrame(NSString *style, NSUInteger index, NSUInteger count, CGSize size) {
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor blackColor] setFill];
    CGContextFillRect(ctx, (CGRect){CGPointZero, size});
    CGFloat t = count > 0 ? (CGFloat)index / (CGFloat)count : 0;
    CGPoint c = CGPointMake(size.width / 2.0, size.height / 2.0);
    CGFloat m = MIN(size.width, size.height);

    if ([style isEqualToString:@"pulse"]) {
        for (NSUInteger ring = 0; ring < 4; ring++) {
            CGFloat phase = fmod(t + ring * 0.25, 1.0);
            CGFloat radius = m * (0.08 + phase * 0.42);
            UIColor *color = G2RGB(0.1, 0.65 + ring * 0.06, 1.0, 1.0 - phase);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 5.0);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x-radius, c.y-radius, radius*2, radius*2));
        }
    } else if ([style isEqualToString:@"orbit"]) {
        for (NSUInteger dot = 0; dot < 8; dot++) {
            CGFloat angle = (CGFloat)(M_PI * 2.0 * (t + dot / 8.0));
            CGFloat radius = m * 0.30;
            CGPoint p = CGPointMake(c.x + cos(angle) * radius, c.y + sin(angle) * radius);
            CGFloat alpha = 0.25 + 0.75 * ((dot + index) % 8) / 7.0;
            [G2RGB(0.65, 0.25 + dot * 0.06, 1.0, alpha) setFill];
            CGContextFillEllipseInRect(ctx, CGRectMake(p.x-10, p.y-10, 20, 20));
        }
    } else if ([style isEqualToString:@"bars"] || [style isEqualToString:@"equalizer"]) {
        NSUInteger bars = [style isEqualToString:@"bars"] ? 9 : 13;
        CGFloat gap = 6.0;
        CGFloat width = (m * 0.72 - gap * (bars - 1)) / bars;
        CGFloat left = c.x - (width * bars + gap * (bars - 1)) / 2.0;
        for (NSUInteger i = 0; i < bars; i++) {
            CGFloat wave = (sin((t * M_PI * 2.0) + i * 0.72) + 1.0) / 2.0;
            CGFloat height = m * (0.12 + wave * 0.52);
            UIColor *color = [style isEqualToString:@"bars"] ? G2RGB(0.0, 0.85, 1.0, 1.0) : G2RGB(0.25 + i * 0.04, 1.0, 0.55, 1.0);
            [color setFill];
            UIBezierPath *bar = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(left + i * (width + gap), c.y-height/2.0, width, height) cornerRadius:width/2.0];
            [bar fill];
        }
    } else if ([style isEqualToString:@"radar"]) {
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.0, 0.9, 0.35, 0.45).CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        for (NSUInteger r = 1; r <= 4; r++) {
            CGFloat radius = m * 0.1 * r;
            CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x-radius, c.y-radius, radius*2, radius*2));
        }
        CGFloat angle = t * M_PI * 2.0;
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.1, 1.0, 0.45, 1.0).CGColor);
        CGContextSetLineWidth(ctx, 5.0);
        CGContextMoveToPoint(ctx, c.x, c.y);
        CGContextAddLineToPoint(ctx, c.x + cos(angle) * m * 0.42, c.y + sin(angle) * m * 0.42);
        CGContextStrokePath(ctx);
    } else if ([style isEqualToString:@"grid"]) {
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.0, 0.65, 1.0, 0.75).CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        for (NSInteger i = -6; i <= 6; i++) {
            CGFloat x = c.x + i * m * 0.07;
            CGContextMoveToPoint(ctx, c.x, c.y - m * 0.05);
            CGContextAddLineToPoint(ctx, x, size.height);
            CGContextStrokePath(ctx);
        }
        for (NSUInteger row = 0; row < 12; row++) {
            CGFloat phase = fmod((CGFloat)row / 12.0 + t, 1.0);
            CGFloat y = c.y + phase * c.y;
            CGFloat half = phase * m * 0.48;
            CGContextMoveToPoint(ctx, c.x-half, y);
            CGContextAddLineToPoint(ctx, c.x+half, y);
            CGContextStrokePath(ctx);
        }
    } else if ([style isEqualToString:@"tunnel"]) {
        for (NSUInteger square = 0; square < 8; square++) {
            CGFloat phase = fmod(t + square / 8.0, 1.0);
            CGFloat side = m * (0.08 + phase * 0.78);
            CGContextSetStrokeColorWithColor(ctx, G2RGB(0.8, 0.2 + 0.7 * phase, 1.0, 1.0-phase*0.55).CGColor);
            CGContextSetLineWidth(ctx, 4.0);
            CGContextStrokeRect(ctx, CGRectMake(c.x-side/2.0, c.y-side/2.0, side, side));
        }
    } else if ([style isEqualToString:@"spark"]) {
        for (NSUInteger ray = 0; ray < 18; ray++) {
            CGFloat angle = ray / 18.0 * M_PI * 2.0 + t * M_PI * 2.0;
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

static NSArray<UIImage *> *G2FramesFromGIF(NSString *path, CGFloat maximumDimension) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return @[];
    NSUInteger count = MIN((NSUInteger)CGImageSourceGetCount(source), G2MaximumDecodedFrames);
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize:@(maximumDimension),
        (NSString *)kCGImageSourceShouldCacheImmediately:@YES
    };
    for (NSUInteger index = 0; index < count; index++) {
        CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, index, (__bridge CFDictionaryRef)options);
        if (!cg) continue;
        UIImage *image = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
        CGImageRelease(cg);
        if (image) [frames addObject:image];
    }
    CFRelease(source);
    return frames;
}

static NSArray<UIImage *> *G2FramesFromDirectory(NSString *directory, CGFloat maximumDimension) {
    NSArray *files = G2NaturallySortedImageFiles(directory);
    NSMutableArray *frames = [NSMutableArray array];
    NSUInteger count = MIN(files.count, G2MaximumDecodedFrames);
    for (NSUInteger index = 0; index < count; index++) {
        NSString *path = files[index];
        if ([path.pathExtension.lowercaseString isEqualToString:@"gif"]) {
            NSArray *gifFrames = G2FramesFromGIF(path, maximumDimension);
            if (gifFrames.count > 1 && files.count == 1) return gifFrames;
        }
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        image = G2ScaledImage(image, maximumDimension);
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

static BOOL G2StageGIFAtPath(NSString *sourcePath, NSDictionary *recommended, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:NSDataReadingMappedIfSafe error:error];
    NSDictionary *metadata = data ? G2ValidateGIFData(data, error) : nil;
    if (!metadata || !data) return NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:G2MediaDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error];
    if (error && *error) return NO;
    NSString *temporaryGIF = [G2PendingGIFPath stringByAppendingString:@".gallery"];
    NSString *temporaryMetadata = [G2PendingMetadataPath stringByAppendingString:@".gallery"];
    [manager removeItemAtPath:temporaryGIF error:nil];
    [manager removeItemAtPath:temporaryMetadata error:nil];
    if (![data writeToFile:temporaryGIF options:NSDataWritingAtomic error:error]) return NO;
    NSMutableDictionary *storedMetadata = [metadata mutableCopy];
    if (recommended[@"name"]) storedMetadata[@"themeName"] = recommended[@"name"];
    if (recommended[@"identifier"]) storedMetadata[@"themeIdentifier"] = recommended[@"identifier"];
    if (![storedMetadata writeToFile:temporaryMetadata atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:8 userInfo:@{NSLocalizedDescriptionKey:@"The theme metadata could not be staged."}];
        return NO;
    }
    chmod(temporaryGIF.fileSystemRepresentation, 0644);
    chmod(temporaryMetadata.fileSystemRepresentation, 0644);
    [manager removeItemAtPath:G2PendingGIFPath error:nil];
    [manager removeItemAtPath:G2PendingMetadataPath error:nil];
    if (rename(temporaryGIF.fileSystemRepresentation, G2PendingGIFPath.fileSystemRepresentation) != 0 ||
        rename(temporaryMetadata.fileSystemRepresentation, G2PendingMetadataPath.fileSystemRepresentation) != 0) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:9 userInfo:@{NSLocalizedDescriptionKey:@"The selected theme could not be promoted into the staging area."}];
        return NO;
    }
    chown(G2PendingGIFPath.fileSystemRepresentation, 501, 501);
    chown(G2PendingMetadataPath.fileSystemRepresentation, 501, 501);

    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[@"pendingReady"] = @YES;
    if (recommended[@"background"]) prefs[@"backgroundColor"] = recommended[@"background"];
    prefs[@"imageTransformation"] = recommended[@"scaling"] ?: @"resizeAspect";
    if (![prefs writeToFile:G2PreferencesPath atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniGallery" code:10 userInfo:@{NSLocalizedDescriptionKey:@"The theme was staged, but its preference state could not be saved."}];
        return NO;
    }
    chown(G2PreferencesPath.fileSystemRepresentation, 501, 501);
    chmod(G2PreferencesPath.fileSystemRepresentation, 0644);
    CFPreferencesSetAppValue(CFSTR("pendingReady"), kCFBooleanTrue, (__bridge CFStringRef)G2PreferencesDomain);
    if (recommended[@"background"]) CFPreferencesSetAppValue(CFSTR("backgroundColor"), (__bridge CFPropertyListRef)recommended[@"background"], (__bridge CFStringRef)G2PreferencesDomain);
    CFPreferencesSetAppValue(CFSTR("imageTransformation"), (__bridge CFPropertyListRef)(recommended[@"scaling"] ?: @"resizeAspect"), (__bridge CFStringRef)G2PreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)G2PreferencesDomain);
    return YES;
}

static int G2RunTool(NSArray<NSString *> *candidates, NSArray<NSString *> *arguments) {
    for (NSString *tool in candidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) continue;
        NSUInteger argc = arguments.count + 2;
        char **argv = calloc(argc, sizeof(char *));
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

@interface G2ThemePreviewController : UIViewController
- (instancetype)initWithPack:(NSDictionary *)pack;
@end

@interface G2ThemePreviewController ()
@property (nonatomic, strong) NSDictionary *pack;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *stageButton;
@property (nonatomic, strong) UIActivityIndicatorView *activity;
@property (nonatomic, strong) NSArray<UIImage *> *frames;
@end

@implementation G2ThemePreviewController

- (instancetype)initWithPack:(NSDictionary *)pack {
    if ((self = [super init])) _pack = pack;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.pack[@"name"] ?: @"Animation";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.imageView = [UIImageView new];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.backgroundColor = UIColor.blackColor;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.layer.cornerRadius = 18.0;
    self.imageView.layer.masksToBounds = YES;
    [self.view addSubview:self.imageView];

    UILabel *description = [UILabel new];
    description.translatesAutoresizingMaskIntoConstraints = NO;
    description.text = self.pack[@"subtitle"] ?: self.pack[@"package"] ?: @"Preview this animation before staging it.";
    description.textAlignment = NSTextAlignmentCenter;
    description.numberOfLines = 0;
    description.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [self.view addSubview:description];

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [self.view addSubview:self.statusLabel];

    self.stageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stageButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stageButton setTitle:@"Stage This Animation" forState:UIControlStateNormal];
    self.stageButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.stageButton.backgroundColor = self.view.tintColor;
    [self.stageButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.stageButton.layer.cornerRadius = 12.0;
    [self.stageButton addTarget:self action:@selector(stageAnimation) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stageButton];

    self.activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activity.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.activity];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.imageView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [self.imageView.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.imageView.widthAnchor constraintEqualToConstant:300],
        [self.imageView.heightAnchor constraintEqualToConstant:300],
        [description.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:18],
        [description.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [description.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [self.statusLabel.topAnchor constraintEqualToAnchor:description.bottomAnchor constant:10],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [self.stageButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.statusLabel.bottomAnchor constant:22],
        [self.stageButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],
        [self.stageButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],
        [self.stageButton.heightAnchor constraintEqualToConstant:50],
        [self.stageButton.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-24],
        [self.activity.centerXAnchor constraintEqualToAnchor:self.stageButton.centerXAnchor],
        [self.activity.centerYAnchor constraintEqualToAnchor:self.stageButton.centerYAnchor]
    ]];

    [self loadPreview];
}

- (void)loadPreview {
    NSString *kind = self.pack[@"kind"];
    if ([kind isEqualToString:@"builtin"]) {
        self.frames = G2BuiltInFrames(self.pack[@"style"], CGSizeMake(300,300));
    } else if ([kind isEqualToString:@"gif"]) {
        self.frames = G2FramesFromGIF(self.pack[@"path"], 400);
    } else if ([kind isEqualToString:@"frames"]) {
        self.frames = G2FramesFromDirectory(self.pack[@"path"], 400);
    }
    if (self.frames.count > 1) {
        self.imageView.animationImages = self.frames;
        self.imageView.animationDuration = MAX(0.8, self.frames.count * 0.08);
        self.imageView.animationRepeatCount = 0;
        self.imageView.image = self.frames.firstObject;
        [self.imageView startAnimating];
        self.statusLabel.text = [NSString stringWithFormat:@"%lu preview frames • staged safely before Apply", (unsigned long)self.frames.count];
        self.stageButton.enabled = YES;
    } else {
        self.imageView.image = self.frames.firstObject;
        self.statusLabel.text = @"No animation frames were found. Install or import this legacy pack first.";
        self.stageButton.enabled = NO;
        self.stageButton.alpha = 0.45;
    }
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
@property (nonatomic, strong) NSArray<NSDictionary *> *discovered;
@property (nonatomic, strong) NSArray<NSDictionary *> *legacy;
@property (nonatomic, assign) BOOL importing;
@end

@implementation G2ThemeGalleryController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Animation Gallery";
    self.tableView.rowHeight = 70.0;
    self.tableView.estimatedRowHeight = 70.0;
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshGallery)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importPack)]
    ];
    self.builtIn = G2BuiltInPacks();
    self.legacy = G2LegacyCatalog();
    [self refreshGallery];
}

- (void)refreshGallery {
    self.discovered = [self scanThemeDirectories];
    [self.tableView reloadData];
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
            NSArray *sorted = G2NaturallySortedImageFiles(canonical);
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
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Built-In • Original and Redistributable";
    if (section == 1) return @"Installed or Imported Packs";
    return @"Legacy Free-Pack Catalog";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"These procedural animations ship with Gif2Ani and are immediately previewable.";
    if (section == 1) return self.discovered.count ? @"Springy, SnowBoard Respring, GIF, frame-folder, ZIP, and DEB packs are detected here." : @"Tap + to import a GIF, ZIP, DEB, or theme folder. Installed Springy and SnowBoard packs are detected automatically.";
    return @"Free does not grant redistribution rights. These names are indexed for compatibility; import a legally obtained pack to preview and use its actual animation.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return self.builtIn.count;
    if (section == 1) return MAX((NSUInteger)1, self.discovered.count);
    return self.legacy.count;
}

- (NSDictionary *)packAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return self.builtIn[indexPath.row];
    if (indexPath.section == 1 && self.discovered.count) return self.discovered[indexPath.row];
    if (indexPath.section == 2) {
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
    if (indexPath.section == 1 && self.discovered.count == 0) {
        cell.textLabel.text = @"No imported packs yet";
        cell.detailTextLabel.text = @"Tap + to import or install a compatible theme";
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *pack = [self packAtIndexPath:indexPath];
    cell.textLabel.text = pack[@"name"];
    cell.detailTextLabel.text = pack[@"subtitle"];
    cell.detailTextLabel.numberOfLines = 2;
    UIImage *thumb = nil;
    if ([pack[@"kind"] isEqualToString:@"builtin"]) thumb = G2RenderBuiltInFrame(pack[@"style"], 0, 24, CGSizeMake(64,64));
    else if ([pack[@"kind"] isEqualToString:@"gif"]) thumb = G2FramesFromGIF(pack[@"path"], 96).firstObject;
    else if ([pack[@"kind"] isEqualToString:@"frames"]) thumb = G2FramesFromDirectory(pack[@"path"], 96).firstObject;
    else thumb = [UIImage systemImageNamed:@"archivebox"];
    cell.imageView.image = thumb;
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
        NSMutableArray<NSString *> *failures = [NSMutableArray array];
        NSUInteger imported = 0;
        for (NSURL *url in urls) {
            BOOL scoped = [url startAccessingSecurityScopedResource];
            NSString *safeName = url.lastPathComponent.length ? url.lastPathComponent : [[NSUUID UUID] UUIDString];
            NSString *identifier = [NSString stringWithFormat:@"%@-%@", safeName.stringByDeletingPathExtension, [[NSUUID UUID] UUIDString]];
            NSString *destination = [G2ImportedPacksDirectory stringByAppendingPathComponent:identifier];
            NSError *error = nil;
            [manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error];
            NSString *extension = url.pathExtension.lowercaseString;
            BOOL success = NO;
            if (!error && [extension isEqualToString:@"deb"]) {
                NSString *local = [destination stringByAppendingPathComponent:safeName];
                success = [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:local] error:&error];
                if (success) success = G2RunTool(@[@"/var/jb/usr/bin/dpkg-deb",@"/usr/bin/dpkg-deb"], @[@"-x",local,destination]) == 0;
                [manager removeItemAtPath:local error:nil];
            } else if (!error && [extension isEqualToString:@"zip"]) {
                NSString *local = [destination stringByAppendingPathComponent:safeName];
                success = [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:local] error:&error];
                if (success) success = G2RunTool(@[@"/var/jb/usr/bin/unzip",@"/usr/bin/unzip"], @[@"-o",local,@"-d",destination]) == 0;
                [manager removeItemAtPath:local error:nil];
            } else if (!error) {
                NSString *local = [destination stringByAppendingPathComponent:safeName];
                success = [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:local] error:&error];
            }
            if (scoped) [url stopAccessingSecurityScopedResource];
            if (success) imported++;
            else {
                [manager removeItemAtPath:destination error:nil];
                [failures addObject:error.localizedDescription ?: safeName];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf refreshGallery];
            NSString *message = [NSString stringWithFormat:@"Imported %lu pack file%@.%@", (unsigned long)imported, imported == 1 ? @"" : @"s",
                                 failures.count ? [NSString stringWithFormat:@"\n\n%lu item%@ could not be imported.", (unsigned long)failures.count, failures.count == 1 ? @"" : @"s"] : @""];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:imported ? @"Import finished" : @"Import failed"
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
        });
    });
    (void)controller;
}

@end
