#import "UIImage+animatedGIF.h"
#import "G2PreferencesManager.h"
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <sys/stat.h>

static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2ActiveGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Active.gif";
static NSString * const G2RejectedGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Rejected.gif";
static NSString * const G2StatusPath = @"/var/mobile/Library/Application Support/Gif2Ani/runtime-status.plist";
static NSString * const G2LoadSentinelPath = @"/var/mobile/Library/Application Support/Gif2Ani/load-in-progress";
static CFStringRef const G2ReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

static const NSUInteger G2MaximumDecodedFrames = 24;
static const NSUInteger G2MaximumPixelDimension = 640;
static const unsigned long long G2MaximumInputBytes = 25ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumEstimatedDecodedBytes = 48ULL * 1024ULL * 1024ULL;

static NSArray<UIImage *> *g2Frames;
static NSTimeInterval g2NaturalDuration;
static NSDictionary *g2MediaMetadata;

static void G2EnsureMediaDirectory(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:nil];
}

static void G2WriteStatus(NSString *event, NSDictionary *extra) {
    G2EnsureMediaDirectory();
    NSMutableDictionary *status = [@{
        @"event": event ?: @"unknown",
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"process": NSProcessInfo.processInfo.processName ?: @"unknown",
        @"BKImageSequence": @(objc_getClass("BKImageSequence") != Nil),
        @"BKDisplayRenderOverlaySpinny": @(objc_getClass("BKDisplayRenderOverlaySpinny") != Nil),
        @"gifExists": @([[NSFileManager defaultManager] fileExistsAtPath:G2ActiveGIFPath]),
        @"frameCount": @(g2Frames.count),
        @"safetyLimits": @{
            @"maximumDecodedFrames": @(G2MaximumDecodedFrames),
            @"maximumPixelDimension": @(G2MaximumPixelDimension),
            @"maximumInputBytes": @(G2MaximumInputBytes),
            @"maximumEstimatedDecodedBytes": @(G2MaximumEstimatedDecodedBytes),
        },
    } mutableCopy];
    if (g2MediaMetadata) status[@"media"] = g2MediaMetadata;
    if (extra) [status addEntriesFromDictionary:extra];
    [status writeToFile:G2StatusPath atomically:YES];
}

static void G2ClearLoadSentinel(void) {
    [[NSFileManager defaultManager] removeItemAtPath:G2LoadSentinelPath error:nil];
}

static void G2RejectActiveGIF(NSString *reason) {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtPath:G2RejectedGIFPath error:nil];
    if ([manager fileExistsAtPath:G2ActiveGIFPath]) {
        [manager moveItemAtPath:G2ActiveGIFPath toPath:G2RejectedGIFPath error:nil];
    }
    G2ClearLoadSentinel();
    g2Frames = nil;
    g2NaturalDuration = 0;
    g2MediaMetadata = nil;
    G2WriteStatus(@"gif-auto-disabled", @{ @"reason": reason ?: @"unknown" });
}

static NSDictionary *G2ValidateActiveGIF(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [manager attributesOfItemAtPath:G2ActiveGIFPath error:nil];
    unsigned long long inputBytes = [attributes fileSize];
    if (!attributes || inputBytes == 0 || inputBytes > G2MaximumInputBytes) return nil;

    NSURL *url = [NSURL fileURLWithPath:G2ActiveGIFPath];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;

    size_t sourceFrames = CGImageSourceGetCount(source);
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSUInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CFRelease(source);

    if (sourceFrames == 0 || width == 0 || height == 0) return nil;
    NSUInteger decodedFrames = MIN((NSUInteger)sourceFrames, G2MaximumDecodedFrames);
    double maxDimension = (double)MAX(width, height);
    double scale = MIN(1.0, (double)G2MaximumPixelDimension / MAX(1.0, maxDimension));
    NSUInteger decodedWidth = MAX((NSUInteger)1, (NSUInteger)ceil(width * scale));
    NSUInteger decodedHeight = MAX((NSUInteger)1, (NSUInteger)ceil(height * scale));
    unsigned long long estimatedBytes = (unsigned long long)decodedWidth * (unsigned long long)decodedHeight * 4ULL * (unsigned long long)decodedFrames;
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

static BOOL G2LoadGIF(void) {
    g2Frames = nil;
    g2NaturalDuration = 0;
    g2MediaMetadata = nil;

    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:G2ActiveGIFPath]) {
        G2WriteStatus(@"no-active-gif", nil);
        return NO;
    }

    if ([manager fileExistsAtPath:G2LoadSentinelPath]) {
        NSDictionary *attributes = [manager attributesOfItemAtPath:G2LoadSentinelPath error:nil];
        NSDate *modified = attributes[NSFileModificationDate];
        NSTimeInterval age = modified ? -modified.timeIntervalSinceNow : 0;
        if (age >= 0 && age < 300) {
            G2RejectActiveGIF(@"previous backboardd load did not complete");
            return NO;
        }
        G2ClearLoadSentinel();
    }

    NSDictionary *metadata = G2ValidateActiveGIF();
    if (!metadata) {
        G2RejectActiveGIF(@"GIF exceeded the safe size, frame, dimension, or memory limits");
        return NO;
    }
    g2MediaMetadata = metadata;

    G2EnsureMediaDirectory();
    [@"loading" writeToFile:G2LoadSentinelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    UIImage *animation = [UIImage animatedImageWithAnimatedGIFURL:[NSURL fileURLWithPath:G2ActiveGIFPath]];
    if (!animation) {
        G2RejectActiveGIF(@"ImageIO could not decode the active GIF");
        return NO;
    }

    NSArray<UIImage *> *frames = animation.images;
    if (!frames.count) frames = @[animation];
    if (!frames.count || frames.count > G2MaximumDecodedFrames) {
        G2RejectActiveGIF(@"decoded frame count was invalid");
        return NO;
    }

    g2Frames = [frames copy];
    g2NaturalDuration = MAX(0.05, animation.duration);
    G2WriteStatus(@"gif-loaded-safely", @{ @"duration": @(g2NaturalDuration) });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        G2ClearLoadSentinel();
        G2WriteStatus(@"gif-load-stable", nil);
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

static void G2Reload(__unused CFNotificationCenterRef center,
                     __unused void *observer,
                     __unused CFStringRef name,
                     __unused const void *object,
                     __unused CFDictionaryRef userInfo) {
    [[G2PreferencesManager sharedInstance] reload];
    G2WriteStatus(@"preferences-reloaded-without-media-decode", nil);
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
    if (!preferences.isEnabled || !g2Frames.count) {
        %orig;
        return;
    }

    NSArray *values = G2CGImageValues();
    if (!values.count) {
        %orig;
        return;
    }

    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    animation.values = values;
    animation.calculationMode = kCAAnimationDiscrete;
    CGFloat loops = preferences.customLoop;
    animation.repeatCount = loops < 0 ? HUGE_VALF : MAX(0.0, loops);
    CGFloat duration = preferences.customDuration;
    animation.duration = duration < 0 ? g2NaturalDuration : MAX(0.05, duration);
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeBoth;
    [self.contentLayer addAnimation:animation forKey:@"com.nightvibes33.gif2ani.animation"];
    G2WriteStatus(@"custom-animation-started", @{ @"duration": @(animation.duration), @"repeatCount": @(animation.repeatCount) });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        G2ClearLoadSentinel();
        G2WriteStatus(@"custom-animation-stable", nil);
    });
}

- (CALayer *)_prepareContentLayerForPresentation:(id)presentation {
    CALayer *layer = %orig;
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (!preferences.isEnabled || !g2Frames.count || !layer) return layer;
    layer.contentsGravity = preferences.imageTransformation;
    if ([self.display respondsToSelector:@selector(safeBounds)]) layer.bounds = [self.display safeBounds];
    layer.backgroundColor = preferences.backgroundColor.CGColor;
    return layer;
}

%end
%end

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"backboardd"]) return;
        G2EnsureMediaDirectory();
        [[G2PreferencesManager sharedInstance] reload];
        if ([G2PreferencesManager sharedInstance].isEnabled) G2LoadGIF();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        G2Reload,
                                        G2ReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        if (objc_getClass("BKDisplayRenderOverlaySpinny")) %init(G2SpinnyHooks);
        G2WriteStatus([G2PreferencesManager sharedInstance].isEnabled ? @"tweak-loaded-enabled" : @"tweak-loaded-disabled", nil);
    }
}
