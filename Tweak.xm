#import "G2PreferencesManager.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <unistd.h>
#include <math.h>
#include <sys/stat.h>

static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2ActiveGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Active.gif";
static NSString * const G2RejectedGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Rejected.gif";
static NSString * const G2StatusPath = @"/var/mobile/Library/Application Support/Gif2Ani/runtime-status.plist";
static NSString * const G2LoadSentinelPath = @"/var/mobile/Library/Application Support/Gif2Ani/load-in-progress";
static NSString * const G2PreferencesPath = @"/var/mobile/Library/Preferences/com.nightvibes33.gif2ani.plist";
static NSString * const G2AnimationKey = @"com.nightvibes33.gif2ani.animation";
static CFStringRef const G2ReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

static const NSUInteger G2MaximumSourceFrames = 240;
static const NSUInteger G2MaximumDecodedFrames = 24;
static const NSUInteger G2MaximumPixelDimension = 640;
static const unsigned long long G2MaximumInputBytes = 25ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumEstimatedDecodedBytes = 48ULL * 1024ULL * 1024ULL;
static const NSTimeInterval G2MaximumTotalAnimationDuration = 30.0;

static NSArray<UIImage *> *g2Frames;
static NSArray<NSNumber *> *g2KeyTimes;
static NSTimeInterval g2NaturalDuration;
static NSDictionary *g2MediaMetadata;
static BOOL g2AnimationPending;
static CALayer *g2PreparedContentLayer;
static CALayer *g2DedicatedAnimationLayer;
static __weak CALayer *g2AppleLoaderLayer;
static float g2AppleLoaderOriginalOpacity = 1.0f;
static CGRect g2PresentationBounds;
static BOOL g2DecodeInProgress;
static unsigned long long g2PeakDecodedBytes;
static NSTimeInterval g2LastDecodeMilliseconds;
static dispatch_source_t g2MemoryPressureSource;
static id g2AnimationLifetimeObserver;

static void G2EnsureMediaDirectory(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory
                               withIntermediateDirectories:YES
                                                attributes:@{NSFilePosixPermissions: @0755}
                                                     error:nil];
}

static dispatch_queue_t G2StatusQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.nightvibes33.gif2ani.status", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static dispatch_queue_t G2DecodeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.nightvibes33.gif2ani.decode", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static BOOL G2StatusEventIsUrgent(NSString *event) {
    NSString *lower = event.lowercaseString;
    return [lower containsString:@"disabled"] || [lower containsString:@"failed"] ||
           [lower containsString:@"exception"] || [lower containsString:@"stable"] ||
           [lower containsString:@"memory-pressure"];
}

static void G2WriteStatus(NSString *event, NSDictionary *extra) {
    NSString *eventSnapshot = [event copy] ?: @"unknown";
    NSDictionary *extraSnapshot = [extra copy];
    NSDictionary *mediaSnapshot = [g2MediaMetadata copy];
    NSUInteger frameCount = g2Frames.count;
    BOOL animationPending = g2AnimationPending;
    NSTimeInterval decodeMilliseconds = g2LastDecodeMilliseconds;
    unsigned long long peakBytes = g2PeakDecodedBytes;
    dispatch_async(G2StatusQueue(), ^{
        static CFAbsoluteTime lastWrite = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (!G2StatusEventIsUrgent(eventSnapshot) && now - lastWrite < 0.75) return;
        lastWrite = now;
        G2EnsureMediaDirectory();
        NSMutableDictionary *status = [@{
            @"event": eventSnapshot,
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"process": NSProcessInfo.processInfo.processName ?: @"unknown",
            @"BKDisplayRenderOverlaySpinny": @(objc_getClass("BKDisplayRenderOverlaySpinny") != Nil),
            @"gifExists": @([[NSFileManager defaultManager] fileExistsAtPath:G2ActiveGIFPath]),
            @"frameCount": @(frameCount),
            @"animationPending": @(animationPending),
            @"decodeMilliseconds": @(decodeMilliseconds),
            @"peakDecodedBytes": @(peakBytes),
            @"safetyLimits": @{
                @"maximumSourceFrames": @(G2MaximumSourceFrames),
                @"maximumDecodedFrames": @(G2MaximumDecodedFrames),
                @"maximumPixelDimension": @(G2MaximumPixelDimension),
                @"maximumInputBytes": @(G2MaximumInputBytes),
                @"maximumEstimatedDecodedBytes": @(G2MaximumEstimatedDecodedBytes),
                @"maximumTotalAnimationDuration": @(G2MaximumTotalAnimationDuration),
            },
        } mutableCopy];
        if (mediaSnapshot) status[@"media"] = mediaSnapshot;
        if (extraSnapshot) [status addEntriesFromDictionary:extraSnapshot];
        [status writeToFile:G2StatusPath atomically:YES];
    });
}

static void G2SetEnabledOnDisk(BOOL enabled) {
    NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath] mutableCopy];
    if (!preferences) preferences = [NSMutableDictionary dictionary];
    preferences[@"isEnabled"] = @(enabled);
    if ([preferences writeToFile:G2PreferencesPath atomically:YES]) {
        chown(G2PreferencesPath.fileSystemRepresentation, 501, 501);
        chmod(G2PreferencesPath.fileSystemRepresentation, 0644);
    }
}

static void G2ClearLoadSentinel(void) {
    [[NSFileManager defaultManager] removeItemAtPath:G2LoadSentinelPath error:nil];
}

static void G2RestoreAppleLoader(void) {
    CALayer *layer = g2AppleLoaderLayer;
    if (layer) layer.opacity = g2AppleLoaderOriginalOpacity;
    g2AppleLoaderLayer = nil;
    g2AppleLoaderOriginalOpacity = 1.0f;
}

static void G2RejectActiveGIF(NSString *reason) {
    NSFileManager *manager = [NSFileManager defaultManager];
    G2EnsureMediaDirectory();
    [manager removeItemAtPath:G2RejectedGIFPath error:nil];
    if ([manager fileExistsAtPath:G2ActiveGIFPath]) {
        [manager moveItemAtPath:G2ActiveGIFPath toPath:G2RejectedGIFPath error:nil];
    }
    G2ClearLoadSentinel();
    G2SetEnabledOnDisk(NO);
    [[G2PreferencesManager sharedInstance] reload];
    g2Frames = nil;
    g2KeyTimes = nil;
    g2NaturalDuration = 0;
    g2MediaMetadata = nil;
    g2AnimationPending = NO;
    g2PreparedContentLayer = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        G2RestoreAppleLoader();
        [g2DedicatedAnimationLayer removeFromSuperlayer];
        g2DedicatedAnimationLayer = nil;
        g2PresentationBounds = CGRectZero;
    });
    G2WriteStatus(@"gif-auto-disabled", @{ @"reason": reason ?: @"unknown" });
}

static NSDictionary *G2ValidateActiveGIF(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [manager attributesOfItemAtPath:G2ActiveGIFPath error:nil];
    unsigned long long inputBytes = [attributes[NSFileSize] unsignedLongLongValue];
    if (!attributes || inputBytes == 0 || inputBytes > G2MaximumInputBytes) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:G2ActiveGIFPath], NULL);
    if (!source) return nil;

    size_t sourceFrames = CGImageSourceGetCount(source);
    NSDictionary *properties = sourceFrames ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
    NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSUInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CFRelease(source);

    if (!gifProperties || sourceFrames < 2 || sourceFrames > G2MaximumSourceFrames || width == 0 || height == 0) return nil;

    NSUInteger decodedFrames = MIN((NSUInteger)sourceFrames, G2MaximumDecodedFrames);
    double maxDimension = (double)MAX(width, height);
    double scale = MIN(1.0, (double)G2MaximumPixelDimension / MAX(1.0, maxDimension));
    NSUInteger decodedWidth = MAX((NSUInteger)1, (NSUInteger)ceil(width * scale));
    NSUInteger decodedHeight = MAX((NSUInteger)1, (NSUInteger)ceil(height * scale));
    unsigned long long estimatedBytes = (unsigned long long)decodedWidth * decodedHeight * 4ULL * decodedFrames;
    if (estimatedBytes > G2MaximumEstimatedDecodedBytes) return nil;

    return @{
        @"inputBytes": @(inputBytes),
        @"sourceFrames": @(sourceFrames),
        @"decodedFrames": @(decodedFrames),
        @"sourceWidth": @(width),
        @"sourceHeight": @(height),
        @"decodedWidth": @(decodedWidth),
        @"decodedHeight": @(decodedHeight),
        @"estimatedDecodedBytes": @(estimatedBytes),
    };
}

static NSTimeInterval G2FrameDelay(CGImageSourceRef source, size_t index) {
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
    NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSNumber *unclamped = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    NSNumber *clamped = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
    NSTimeInterval delay = (unclamped ?: clamped).doubleValue;
    if (!isfinite(delay) || delay < 0.02) delay = 0.10;
    return MIN(delay, 10.0);
}

static BOOL G2DecodeActiveGIF(NSDictionary *metadata,
                               NSArray<UIImage *> **framesOut,
                               NSArray<NSNumber *> **keyTimesOut,
                               NSTimeInterval *durationOut,
                               unsigned long long *decodedBytesOut,
                               NSString **failureReasonOut) {
    NSURL *url = [NSURL fileURLWithPath:G2ActiveGIFPath];
    NSDictionary *sourceOptions = @{(NSString *)kCGImageSourceShouldCache: @NO};
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url,
                                                          (__bridge CFDictionaryRef)sourceOptions);
    if (!source) {
        if (failureReasonOut) *failureReasonOut = @"ImageIO could not open the active GIF";
        return NO;
    }

    NSUInteger sourceFrames = CGImageSourceGetCount(source);
    NSUInteger decodedFrames = [metadata[@"decodedFrames"] unsignedIntegerValue];
    if (sourceFrames < 2 || sourceFrames > G2MaximumSourceFrames || decodedFrames == 0) {
        CFRelease(source);
        if (failureReasonOut) *failureReasonOut = @"source frame count was outside the safe limit";
        return NO;
    }

    NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:decodedFrames];
    NSMutableArray<NSNumber *> *keyTimes = [NSMutableArray arrayWithCapacity:decodedFrames];
    NSMutableArray<NSNumber *> *sourceFrameStartTimes = [NSMutableArray arrayWithCapacity:sourceFrames];
    unsigned long long decodedBytes = 0;
    NSTimeInterval duration = 0;

    for (NSUInteger index = 0; index < sourceFrames; index++) {
        [sourceFrameStartTimes addObject:@(duration)];
        duration += G2FrameDelay(source, index);
    }

    NSDictionary *thumbnailOptions = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(G2MaximumPixelDimension),
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
    };

    for (NSUInteger outputIndex = 0; outputIndex < decodedFrames; outputIndex++) {
        size_t sourceIndex = outputIndex;
        if (sourceFrames > decodedFrames && decodedFrames > 1) {
            sourceIndex = (size_t)llround(((double)outputIndex * (double)(sourceFrames - 1)) /
                                           (double)(decodedFrames - 1));
        }

        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source,
                                                                sourceIndex,
                                                                (__bridge CFDictionaryRef)thumbnailOptions);
        if (!image) {
            CFRelease(source);
            if (failureReasonOut) *failureReasonOut = @"ImageIO could not decode a bounded GIF frame";
            return NO;
        }

        unsigned long long frameBytes = (unsigned long long)CGImageGetBytesPerRow(image) *
                                         (unsigned long long)CGImageGetHeight(image);
        if (frameBytes == 0 || frameBytes > G2MaximumEstimatedDecodedBytes ||
            decodedBytes > G2MaximumEstimatedDecodedBytes - frameBytes) {
            CGImageRelease(image);
            CFRelease(source);
            if (failureReasonOut) *failureReasonOut = @"actual decoded memory exceeded the safe limit";
            return NO;
        }
        decodedBytes += frameBytes;

        UIImage *frame = [UIImage imageWithCGImage:image scale:1.0 orientation:UIImageOrientationUp];
        CGImageRelease(image);
        if (!frame) {
            CFRelease(source);
            if (failureReasonOut) *failureReasonOut = @"UIKit could not create a bounded animation frame";
            return NO;
        }
        [frames addObject:frame];
        NSTimeInterval frameStart = [sourceFrameStartTimes[sourceIndex] doubleValue];
        [keyTimes addObject:@(duration > 0 ? MIN(1.0, MAX(0.0, frameStart / duration)) : 0.0)];
    }

    CFRelease(source);
    if (!frames.count || decodedBytes == 0 || keyTimes.count != frames.count) {
        if (failureReasonOut) *failureReasonOut = @"no usable bounded frames or timing data were decoded";
        return NO;
    }

    if (framesOut) *framesOut = [frames copy];
    if (keyTimesOut) *keyTimesOut = [keyTimes copy];
    if (durationOut) *durationOut = MAX(0.05, duration);
    if (decodedBytesOut) *decodedBytesOut = decodedBytes;
    return YES;
}

static BOOL G2LoadGIF(void) {
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (!preferences.isEnabled) return NO;

    NSFileManager *manager = [NSFileManager defaultManager];
    g2Frames = nil;
    g2KeyTimes = nil;
    g2NaturalDuration = 0;
    g2MediaMetadata = nil;
    g2AnimationPending = NO;

    if (![manager fileExistsAtPath:G2ActiveGIFPath]) {
        G2WriteStatus(@"no-active-gif", nil);
        return NO;
    }

    if ([manager fileExistsAtPath:G2LoadSentinelPath]) {
        G2RejectActiveGIF(@"previous backboardd GIF decode or animation startup did not complete");
        return NO;
    }

    NSDictionary *metadata = G2ValidateActiveGIF();
    if (!metadata) {
        G2RejectActiveGIF(@"GIF exceeded safe type, size, frame, dimension, or memory limits");
        return NO;
    }
    g2MediaMetadata = metadata;

    G2EnsureMediaDirectory();
    [@"loading" writeToFile:G2LoadSentinelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<UIImage *> *frames = nil;
    NSArray<NSNumber *> *keyTimes = nil;
    NSTimeInterval duration = 0;
    unsigned long long decodedBytes = 0;
    NSString *failureReason = nil;
    BOOL decoded = NO;
    CFAbsoluteTime decodeStarted = CFAbsoluteTimeGetCurrent();
    @try {
        decoded = G2DecodeActiveGIF(metadata, &frames, &keyTimes, &duration, &decodedBytes, &failureReason);
    } @catch (NSException *exception) {
        failureReason = [NSString stringWithFormat:@"bounded decoder exception: %@", exception.name ?: @"unknown"];
        G2WriteStatus(@"decode-exception", @{ @"name": exception.name ?: @"unknown" });
    }
    g2LastDecodeMilliseconds = (CFAbsoluteTimeGetCurrent() - decodeStarted) * 1000.0;
    g2PeakDecodedBytes = MAX(g2PeakDecodedBytes, decodedBytes);

    if (!decoded || !frames.count || keyTimes.count != frames.count) {
        G2RejectActiveGIF(failureReason ?: @"bounded ImageIO decoder failed");
        return NO;
    }

    g2Frames = frames;
    g2KeyTimes = keyTimes;
    g2NaturalDuration = duration;
    G2WriteStatus(@"gif-decoded-awaiting-animation", @{
        @"duration": @(g2NaturalDuration),
        @"decodedBytes": @(decodedBytes),
        @"decodeMilliseconds": @(g2LastDecodeMilliseconds),
        @"peakDecodedBytes": @(g2PeakDecodedBytes),
        @"timingMode": @"sampled-source-frame-key-times",
        @"decoder": @"ImageIO-bounded-thumbnail-serial-queue",
    });
    return YES;
}

static NSArray *G2CGImageValues(void) {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:g2Frames.count];
    for (UIImage *frame in g2Frames) {
        if (frame.CGImage) [values addObject:(__bridge id)frame.CGImage];
    }
    return values;
}

static CALayer *G2BestAnimationContainer(CALayer *appleLayer) {
    if (!appleLayer) return nil;

    CALayer *best = appleLayer.superlayer ?: appleLayer;
    CGFloat targetArea = CGRectGetWidth(g2PresentationBounds) * CGRectGetHeight(g2PresentationBounds);
    CALayer *cursor = best;
    for (NSUInteger depth = 0; cursor && depth < 8; depth++, cursor = cursor.superlayer) {
        best = cursor;
        CGFloat area = CGRectGetWidth(cursor.bounds) * CGRectGetHeight(cursor.bounds);
        if (targetArea > 0 && area >= targetArea * 0.75) break;
    }
    return best;
}

static CGRect G2OverlayBounds(CALayer *container) {
    CGRect bounds = container ? container.bounds : CGRectZero;
    CGFloat containerArea = CGRectGetWidth(bounds) * CGRectGetHeight(bounds);
    CGFloat displayArea = CGRectGetWidth(g2PresentationBounds) * CGRectGetHeight(g2PresentationBounds);

    if (displayArea > 0 && containerArea < displayArea * 0.75) {
        bounds = CGRectMake(0, 0,
                            CGRectGetWidth(g2PresentationBounds),
                            CGRectGetHeight(g2PresentationBounds));
    }
    if (CGRectIsEmpty(bounds)) {
        CGFloat width = [g2MediaMetadata[@"decodedWidth"] doubleValue];
        CGFloat height = [g2MediaMetadata[@"decodedHeight"] doubleValue];
        bounds = CGRectMake(0, 0, MAX(1.0, width), MAX(1.0, height));
    }
    bounds.origin = CGPointZero;
    return bounds;
}

@interface G2AnimationLifetimeObserver : NSObject <CAAnimationDelegate>
@end

@implementation G2AnimationLifetimeObserver
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    (void)animation;
    dispatch_async(dispatch_get_main_queue(), ^{
        g2Frames = nil;
        g2KeyTimes = nil;
        g2NaturalDuration = 0;
        g2MediaMetadata = nil;
        g2AnimationPending = NO;
        g2PreparedContentLayer = nil;
        if (finished) {
            [g2DedicatedAnimationLayer removeFromSuperlayer];
            g2DedicatedAnimationLayer = nil;
            G2RestoreAppleLoader();
        }
        G2WriteStatus(@"custom-animation-finished-frames-released", @{
            @"finished": @(finished),
            @"peakDecodedBytes": @(g2PeakDecodedBytes),
            @"decodeMilliseconds": @(g2LastDecodeMilliseconds),
        });
    });
}
@end

static BOOL G2InstallAnimationOnLayer(CALayer *appleLayer) {
    if (!appleLayer || !g2Frames.count) return NO;

    NSArray *values = G2CGImageValues();
    if (!values.count || values.count != g2KeyTimes.count) return NO;

    CALayer *container = G2BestAnimationContainer(appleLayer);
    if (!container) return NO;

    if (!g2DedicatedAnimationLayer || g2DedicatedAnimationLayer.superlayer != container) {
        G2RestoreAppleLoader();
        [g2DedicatedAnimationLayer removeFromSuperlayer];
        g2DedicatedAnimationLayer = [CALayer layer];
        g2DedicatedAnimationLayer.name = @"com.nightvibes33.gif2ani.dedicated-overlay";
        g2DedicatedAnimationLayer.zPosition = 100000.0;
        [container addSublayer:g2DedicatedAnimationLayer];
    }

    CGRect overlayBounds = G2OverlayBounds(container);
    g2DedicatedAnimationLayer.bounds = overlayBounds;
    CGRect containerBounds = container.bounds;
    CGPoint center = CGPointMake(CGRectGetMidX(containerBounds), CGRectGetMidY(containerBounds));
    if (CGRectIsEmpty(containerBounds)) {
        center = CGPointMake(CGRectGetMidX(overlayBounds), CGRectGetMidY(overlayBounds));
    }
    g2DedicatedAnimationLayer.position = center;
    g2DedicatedAnimationLayer.opacity = 1.0;
    g2DedicatedAnimationLayer.hidden = NO;
    g2DedicatedAnimationLayer.masksToBounds = YES;
    g2DedicatedAnimationLayer.contentsScale = appleLayer.contentsScale > 0 ? appleLayer.contentsScale : 1.0;

    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    g2DedicatedAnimationLayer.contentsGravity = preferences.imageTransformation;
    g2DedicatedAnimationLayer.backgroundColor = preferences.backgroundColor.CGColor;
    g2DedicatedAnimationLayer.contents = values.firstObject;

    BOOL appleLoaderHidden = container != appleLayer;
    if (appleLoaderHidden) {
        if (g2AppleLoaderLayer != appleLayer) {
            G2RestoreAppleLoader();
            g2AppleLoaderLayer = appleLayer;
            g2AppleLoaderOriginalOpacity = appleLayer.opacity;
        }
        appleLayer.opacity = 0.0;
    }

    if ([g2DedicatedAnimationLayer animationForKey:G2AnimationKey]) {
        g2AnimationPending = NO;
        return YES;
    }

    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    animation.values = values;
    animation.keyTimes = g2KeyTimes;
    animation.calculationMode = kCAAnimationDiscrete;
    CGFloat requestedLoops = preferences.customLoop;
    NSTimeInterval requestedDuration = preferences.customDuration;
    NSTimeInterval cycleDuration = requestedDuration < 0 ? g2NaturalDuration : MAX(0.05, requestedDuration);
    cycleDuration = MIN(G2MaximumTotalAnimationDuration, MAX(0.05, cycleDuration));
    CGFloat repeatCount = requestedLoops < 0 ? HUGE_VALF : MAX(0.0, requestedLoops);
    NSUInteger maximumPlays = MAX((NSUInteger)1, (NSUInteger)floor(G2MaximumTotalAnimationDuration / cycleDuration));
    if (!isfinite(repeatCount) || repeatCount + 1.0 > maximumPlays) repeatCount = MAX(0.0, (CGFloat)maximumPlays - 1.0);
    animation.repeatCount = repeatCount;
    animation.duration = cycleDuration;
    animation.removedOnCompletion = YES;
    animation.fillMode = kCAFillModeBoth;
    animation.delegate = g2AnimationLifetimeObserver;

    @try {
        [g2DedicatedAnimationLayer addAnimation:animation forKey:G2AnimationKey];
    } @catch (NSException *exception) {
        G2RejectActiveGIF([NSString stringWithFormat:@"BackBoard animation exception: %@", exception.name ?: @"unknown"]);
        return NO;
    }

    g2AnimationPending = NO;
    G2WriteStatus(@"custom-animation-started", @{
        @"duration": @(animation.duration),
        @"repeatCount": @(animation.repeatCount),
        @"timingMode": @"sampled-source-frame-key-times",
        @"decoder": @"ImageIO-bounded-thumbnail-serial-queue",
        @"maximumTotalDuration": @(G2MaximumTotalAnimationDuration),
        @"decodeMilliseconds": @(g2LastDecodeMilliseconds),
        @"peakDecodedBytes": @(g2PeakDecodedBytes),
        @"attachmentPoint": @"dedicated-overlay-layer",
        @"overlayWidth": @(CGRectGetWidth(overlayBounds)),
        @"overlayHeight": @(CGRectGetHeight(overlayBounds)),
        @"appleLoaderHidden": @(appleLoaderHidden),
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        G2ClearLoadSentinel();
        G2WriteStatus(@"custom-animation-stable", @{
            @"attachmentPoint": @"dedicated-overlay-layer",
            @"appleLoaderHidden": @(appleLoaderHidden),
            @"duration": @(animation.duration),
            @"repeatCount": @(animation.repeatCount),
            @"maximumTotalDuration": @(G2MaximumTotalAnimationDuration),
            @"contentsGravity": g2DedicatedAnimationLayer.contentsGravity ?: @"unknown",
        });
        g2PreparedContentLayer = nil;
    });
    return YES;
}

static void G2Reload(__unused CFNotificationCenterRef center,
                      __unused void *observer,
                      __unused CFStringRef name,
                      __unused const void *object,
                      __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[G2PreferencesManager sharedInstance] reload];
        g2Frames = nil;
        g2KeyTimes = nil;
        g2NaturalDuration = 0;
        g2MediaMetadata = nil;
        g2AnimationPending = NO;
        g2PreparedContentLayer = nil;
        G2RestoreAppleLoader();
        [g2DedicatedAnimationLayer removeFromSuperlayer];
        g2DedicatedAnimationLayer = nil;
        g2PresentationBounds = CGRectZero;
        G2WriteStatus(@"preferences-reloaded-without-media-decode", @{ @"mainThread": @YES });
    });
}

@interface CADisplay : NSObject
- (CGRect)safeBounds;
@end

@interface BKDisplayRenderOverlaySpinny : NSObject
@property (nonatomic, readonly) CALayer *contentLayer;
@property (nonatomic, readonly, retain) CADisplay *display;
@end

%group G2SpinnyHooks
%hook BKDisplayRenderOverlaySpinny

- (void)_startAnimating {
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    %orig;
    if (!preferences.isEnabled) return;

    if ([self.display respondsToSelector:@selector(safeBounds)]) {
        g2PresentationBounds = [self.display safeBounds];
    }
    CALayer *initialLayer = self.contentLayer ?: g2PreparedContentLayer;
    if (g2Frames.count) {
        g2AnimationPending = YES;
        if (initialLayer && G2InstallAnimationOnLayer(initialLayer)) return;
    }
    if (g2DecodeInProgress) return;

    g2DecodeInProgress = YES;
    g2AnimationPending = YES;
    __weak typeof(self) weakSelf = self;
    __weak CALayer *weakInitialLayer = initialLayer;
    dispatch_async(G2DecodeQueue(), ^{
        BOOL loaded = G2LoadGIF();
        dispatch_async(dispatch_get_main_queue(), ^{
            g2DecodeInProgress = NO;
            if (!loaded) {
                g2AnimationPending = NO;
                return;
            }
            CALayer *resolvedLayer = weakSelf.contentLayer ?: g2PreparedContentLayer ?: weakInitialLayer;
            if (resolvedLayer && G2InstallAnimationOnLayer(resolvedLayer)) return;

            G2WriteStatus(@"custom-animation-awaiting-content-layer", @{ @"decodeCompleted": @YES });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!g2AnimationPending) return;
                CALayer *delayedLayer = weakSelf.contentLayer ?: g2PreparedContentLayer ?: weakInitialLayer;
                if (delayedLayer && G2InstallAnimationOnLayer(delayedLayer)) return;
                G2RejectActiveGIF(@"BackBoard content layer never became available after serial decode completed");
            });
        });
    });
}

- (CALayer *)_prepareContentLayerForPresentation:(id)presentation {
    CALayer *layer = %orig;
    if (layer) g2PreparedContentLayer = layer;
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (!preferences.isEnabled || !g2Frames.count || !layer) return layer;

    if ([self.display respondsToSelector:@selector(safeBounds)]) {
        g2PresentationBounds = [self.display safeBounds];
    }
    G2InstallAnimationOnLayer(layer);
    (void)presentation;
    return layer;
}

%end
%end

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"backboardd"]) return;
        G2EnsureMediaDirectory();
        g2AnimationLifetimeObserver = [G2AnimationLifetimeObserver new];
        g2MemoryPressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
            DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, G2DecodeQueue());
        if (g2MemoryPressureSource) {
            dispatch_source_set_event_handler(g2MemoryPressureSource, ^{
                unsigned long pressure = dispatch_source_get_data(g2MemoryPressureSource);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [g2DedicatedAnimationLayer removeAnimationForKey:G2AnimationKey];
                    [g2DedicatedAnimationLayer removeFromSuperlayer];
                    g2DedicatedAnimationLayer = nil;
                    G2RestoreAppleLoader();
                    g2Frames = nil;
                    g2KeyTimes = nil;
                    g2NaturalDuration = 0;
                    g2MediaMetadata = nil;
                    g2AnimationPending = NO;
                    g2PreparedContentLayer = nil;
                    G2WriteStatus(@"memory-pressure-frames-released", @{ @"pressure": @(pressure) });
                });
            });
            dispatch_resume(g2MemoryPressureSource);
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:G2LoadSentinelPath]) {
            G2RejectActiveGIF(@"recovered automatically after backboardd restart");
        }

        [[G2PreferencesManager sharedInstance] reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NULL,
                                         G2Reload,
                                         G2ReloadNotification,
                                         NULL,
                                         CFNotificationSuspensionBehaviorDeliverImmediately);
        if (objc_getClass("BKDisplayRenderOverlaySpinny")) %init(G2SpinnyHooks);
        G2WriteStatus(@"tweak-loaded-no-media-decode", nil);
    }
}
