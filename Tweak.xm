#import "UIImage+animatedGIF.h"
#import "G2PreferencesManager.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2GIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Respring.gif";
static NSString * const G2StatusPath = @"/var/mobile/Library/Application Support/Gif2Ani/runtime-status.plist";
static CFStringRef const G2ReloadNotification = CFSTR("com.nightvibes33.gif2ani/ReloadPrefs");

static NSArray<UIImage *> *g2Frames;
static NSTimeInterval g2NaturalDuration;

static void G2WriteStatus(NSString *event, NSDictionary *extra) {
    [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:nil];
    NSMutableDictionary *status = [@{
        @"event": event ?: @"unknown",
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"process": NSProcessInfo.processInfo.processName ?: @"unknown",
        @"BKImageSequence": @(objc_getClass("BKImageSequence") != Nil),
        @"BKDisplayRenderOverlaySpinny": @(objc_getClass("BKDisplayRenderOverlaySpinny") != Nil),
        @"gifExists": @([[NSFileManager defaultManager] fileExistsAtPath:G2GIFPath]),
        @"frameCount": @(g2Frames.count),
    } mutableCopy];
    if (extra) [status addEntriesFromDictionary:extra];
    [status writeToFile:G2StatusPath atomically:YES];
}

static BOOL G2LoadGIF(void) {
    g2Frames = nil;
    g2NaturalDuration = 0;
    NSURL *url = [NSURL fileURLWithPath:G2GIFPath];
    UIImage *animation = [UIImage animatedImageWithAnimatedGIFURL:url];
    if (!animation) {
        G2WriteStatus(@"gif-load-failed", nil);
        return NO;
    }
    NSArray<UIImage *> *frames = animation.images;
    if (!frames.count) frames = @[animation];
    if (!frames.count) return NO;
    g2Frames = [frames copy];
    g2NaturalDuration = MAX(0.05, animation.duration);
    G2WriteStatus(@"gif-loaded", @{@"duration": @(g2NaturalDuration)});
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
    G2LoadGIF();
    G2WriteStatus(@"preferences-reloaded", nil);
}

@interface CADisplay : NSObject
- (CGRect)safeBounds;
@end

@interface BKDisplayRenderOverlaySpinny : NSObject
@property (nonatomic, readonly) CALayer *contentLayer;
@property (nonatomic, readonly, retain) CADisplay *display;
@end

%group G2ImageSequenceHooks
%hook BKImageSequence

- (CGImageRef)imageAtIndex:(long long)index {
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (preferences.isEnabled && g2Frames.count) {
        NSUInteger safeIndex = (NSUInteger)llabs(index) % g2Frames.count;
        CGImageRef image = g2Frames[safeIndex].CGImage;
        if (image) return image;
    }
    return %orig;
}

- (id)initWithBasename:(id)basename bundle:(id)bundle imageCount:(long long)imageCount scale:(double)scale {
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (preferences.isEnabled && (g2Frames.count || G2LoadGIF())) {
        G2WriteStatus(@"image-sequence-hooked", @{@"requestedImageCount": @(imageCount)});
        return %orig(basename, bundle, (long long)g2Frames.count, scale);
    }
    return %orig;
}

%end
%end

%group G2SpinnyHooks
%hook BKDisplayRenderOverlaySpinny

- (void)_startAnimating {
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (!preferences.isEnabled || (!g2Frames.count && !G2LoadGIF())) {
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
    G2WriteStatus(@"custom-animation-started", @{@"duration": @(animation.duration), @"repeatCount": @(animation.repeatCount)});
}

- (CALayer *)_prepareContentLayerForPresentation:(id)presentation {
    CALayer *layer = %orig;
    G2PreferencesManager *preferences = [G2PreferencesManager sharedInstance];
    if (!preferences.isEnabled || !layer) return layer;
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
        [[NSFileManager defaultManager] createDirectoryAtPath:G2MediaDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0755}
                                                        error:nil];
        [[G2PreferencesManager sharedInstance] reload];
        G2LoadGIF();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        G2Reload,
                                        G2ReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        if (objc_getClass("BKImageSequence")) %init(G2ImageSequenceHooks);
        if (objc_getClass("BKDisplayRenderOverlaySpinny")) %init(G2SpinnyHooks);
        G2WriteStatus(@"tweak-loaded", nil);
    }
}
