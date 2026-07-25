#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <sys/sysctl.h>

static NSString * const DBPreferencesDomain = @"com.nightvibes33.darkboot";
static NSString * const DBMediaDirectory = @"/var/mobile/Library/Application Support/DarkBoot";
static NSString * const DBSessionMarkerPath = @"/var/mobile/Library/Application Support/DarkBoot/session-active";
static CFStringRef const DBReloadNotification = CFSTR("com.nightvibes33.darkboot/reload");
static CFStringRef const DBPreviewNotification = CFSTR("com.nightvibes33.darkboot/preview");
static CFStringRef const DBSoundPreviewNotification = CFSTR("com.nightvibes33.darkboot/preview-sound");

#pragma mark - Preferences

static id DBPreference(NSString *key, id fallback) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DBPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)DBPreferencesDomain);
    if (!value) return fallback;
    return CFBridgingRelease(value);
}

static void DBSetPreference(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)DBPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)DBPreferencesDomain);
}

static BOOL DBBool(NSString *key, BOOL fallback) {
    return [DBPreference(key, @(fallback)) boolValue];
}

static NSInteger DBInteger(NSString *key, NSInteger fallback) {
    return [DBPreference(key, @(fallback)) integerValue];
}

static CGFloat DBFloat(NSString *key, CGFloat fallback) {
    return [DBPreference(key, @(fallback)) doubleValue];
}

static NSString *DBString(NSString *key, NSString *fallback) {
    id value = DBPreference(key, fallback);
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

static CGFloat DBClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(maximum, MAX(minimum, value));
}

#pragma mark - Files and boot state

static NSArray<NSString *> *DBSortedMediaFiles(void) {
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DBMediaDirectory error:nil];
    return [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] ?: @[];
}

static NSString *DBFileWithPrefix(NSString *prefix) {
    for (NSString *name in DBSortedMediaFiles()) {
        if ([name.lowercaseString hasPrefix:prefix.lowercaseString]) {
            NSString *path = [DBMediaDirectory stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] isReadableFileAtPath:path]) return path;
        }
    }
    return nil;
}

static NSString *DBCustomVisualPath(void) {
    return DBFileWithPrefix(@"boot-visual.");
}

static NSString *DBCustomSoundPath(void) {
    return DBFileWithPrefix(@"boot-sound.");
}

static BOOL DBPathIsVideo(NSString *path) {
    NSSet<NSString *> *extensions = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v"]];
    return [extensions containsObject:path.pathExtension.lowercaseString];
}

static NSTimeInterval DBBootEpoch(void) {
    struct timeval bootTime = {0};
    size_t size = sizeof(bootTime);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &bootTime, &size, NULL, 0) == 0 && bootTime.tv_sec > 0) {
        return (NSTimeInterval)bootTime.tv_sec;
    }
    return 0;
}

static void DBEnsureMediaDirectory(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:DBMediaDirectory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:nil];
}

static BOOL DBShouldSuppressForCrashGuard(void) {
    if (!DBBool(@"CrashGuard", YES)) return NO;

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:DBSessionMarkerPath error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    NSInteger count = 0;
    if (modified && fabs(modified.timeIntervalSinceNow) < 90.0) {
        count = DBInteger(@"CrashGuardCount", 0) + 1;
    }
    DBSetPreference(@"CrashGuardCount", @(count));

    if (count >= 3) {
        DBSetPreference(@"CrashGuardSuppressed", @YES);
        [[NSFileManager defaultManager] removeItemAtPath:DBSessionMarkerPath error:nil];
        return YES;
    }
    return NO;
}

static BOOL DBShouldShowForCurrentLaunch(void) {
    if (!DBBool(@"Enabled", YES)) return NO;
    if (DBShouldSuppressForCrashGuard()) return NO;
    if (DBBool(@"ShowEveryRespring", YES)) return YES;

    NSTimeInterval bootEpoch = DBBootEpoch();
    NSString *currentBoot = [NSString stringWithFormat:@"%.0f", bootEpoch];
    NSString *lastBoot = DBString(@"LastShownBootEpoch", @"");
    if (bootEpoch > 0 && [lastBoot isEqualToString:currentBoot]) return NO;
    DBSetPreference(@"LastShownBootEpoch", currentBoot);
    return YES;
}

static UIColor *DBAccentColor(void) {
    NSString *accent = DBString(@"AccentColor", @"cyan");
    if ([accent isEqualToString:@"purple"]) return [UIColor colorWithRed:0.59 green:0.32 blue:1.0 alpha:1.0];
    if ([accent isEqualToString:@"red"]) return [UIColor colorWithRed:1.0 green:0.20 blue:0.25 alpha:1.0];
    if ([accent isEqualToString:@"gold"]) return [UIColor colorWithRed:1.0 green:0.69 blue:0.18 alpha:1.0];
    if ([accent isEqualToString:@"green"]) return [UIColor colorWithRed:0.18 green:0.90 blue:0.48 alpha:1.0];
    return [UIColor colorWithRed:0.12 green:0.78 blue:1.0 alpha:1.0];
}

#pragma mark - Animated image decoding

static NSTimeInterval DBFrameDelay(CGImageSourceRef source, size_t index) {
    CFDictionaryRef propertiesRef = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    NSDictionary *properties = CFBridgingRelease(propertiesRef);
    NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSNumber *delay = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    if (!delay || delay.doubleValue < 0.02) delay = gif[(NSString *)kCGImagePropertyGIFDelayTime];
    return MAX(0.02, delay.doubleValue ?: 0.10);
}

static UIImage *DBAnimatedImageAtPath(NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;

    size_t frameCount = CGImageSourceGetCount(source);
    if (frameCount <= 1) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        UIImage *image = imageRef ? [UIImage imageWithCGImage:imageRef scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp] : nil;
        if (imageRef) CGImageRelease(imageRef);
        CFRelease(source);
        return image;
    }

    size_t maximumFrames = 120;
    size_t step = MAX((size_t)1, (size_t)ceil((double)frameCount / (double)maximumFrames));
    NSMutableArray<UIImage *> *frames = [NSMutableArray array];
    NSTimeInterval duration = 0;

    for (size_t index = 0; index < frameCount; index += step) {
        @autoreleasepool {
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, index, NULL);
            if (imageRef) {
                [frames addObject:[UIImage imageWithCGImage:imageRef scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]];
                duration += DBFrameDelay(source, index) * step;
                CGImageRelease(imageRef);
            }
        }
    }
    CFRelease(source);
    if (!frames.count) return nil;
    return [UIImage animatedImageWithImages:frames duration:MAX(0.1, duration)];
}

#pragma mark - Boot content controller

@interface DBBootViewController : UIViewController
@property (nonatomic, strong) AVPlayer *videoPlayer;
@property (nonatomic, strong) AVPlayerLayer *videoLayer;
@property (nonatomic, strong) id videoLoopObserver;
@property (nonatomic, strong) CALayer *progressFillLayer;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) CAEmitterLayer *emitterLayer;
- (void)beginProgressWithDuration:(NSTimeInterval)duration;
- (void)stopMedia;
@end

@implementation DBBootViewController

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (UIImage *)particleImage {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(12, 12)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [DBAccentColor() setFill];
        [context fillEllipseInRect:CGRectMake(1, 1, 10, 10)];
    }];
}

- (void)addBuiltInBackground {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.015 green:0.02 blue:0.05 alpha:1.0].CGColor,
        (id)[DBAccentColor() colorWithAlphaComponent:0.24].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.01 blue:0.04 alpha:1.0].CGColor,
        (id)UIColor.blackColor.CGColor
    ];
    gradient.locations = @[@0.0, @0.38, @0.72, @1.0];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    [self.view.layer addSublayer:gradient];
    self.gradientLayer = gradient;

    UIView *orb = [UIView new];
    orb.translatesAutoresizingMaskIntoConstraints = NO;
    orb.backgroundColor = [DBAccentColor() colorWithAlphaComponent:0.14];
    orb.layer.cornerRadius = 130.0;
    orb.layer.shadowColor = DBAccentColor().CGColor;
    orb.layer.shadowOpacity = 0.75;
    orb.layer.shadowRadius = 65.0;
    [self.view addSubview:orb];
    [NSLayoutConstraint activateConstraints:@[
        [orb.widthAnchor constraintEqualToConstant:260.0],
        [orb.heightAnchor constraintEqualToConstant:260.0],
        [orb.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [orb.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-25.0]
    ]];

    [UIView animateWithDuration:2.4 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseInOut animations:^{
        orb.transform = CGAffineTransformMakeScale(1.16, 1.16);
        orb.alpha = 0.58;
    } completion:nil];
}

- (void)addVisualMedia {
    NSString *path = DBCustomVisualPath();
    if (!path.length) {
        [self addBuiltInBackground];
        return;
    }

    if (DBPathIsVideo(path)) {
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
        AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
        player.muted = !DBBool(@"VideoAudioEnabled", NO);
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
        NSString *mode = DBString(@"ContentMode", @"fill");
        if ([mode isEqualToString:@"fit"]) layer.videoGravity = AVLayerVideoGravityResizeAspect;
        else if ([mode isEqualToString:@"stretch"]) layer.videoGravity = AVLayerVideoGravityResize;
        else layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.view.layer addSublayer:layer];
        self.videoPlayer = player;
        self.videoLayer = layer;
        __weak typeof(self) weakSelf = self;
        self.videoLoopObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                                  object:item
                                                                                   queue:NSOperationQueue.mainQueue
                                                                              usingBlock:^(__unused NSNotification *note) {
            [weakSelf.videoPlayer seekToTime:kCMTimeZero];
            [weakSelf.videoPlayer play];
        }];
        [player play];
        return;
    }

    UIImage *image = DBAnimatedImageAtPath(path);
    if (!image) {
        [self addBuiltInBackground];
        return;
    }
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *mode = DBString(@"ContentMode", @"fill");
    if ([mode isEqualToString:@"fit"]) imageView.contentMode = UIViewContentModeScaleAspectFit;
    else if ([mode isEqualToString:@"stretch"]) imageView.contentMode = UIViewContentModeScaleToFill;
    else imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    [self.view addSubview:imageView];
    [NSLayoutConstraint activateConstraints:@[
        [imageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [imageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)addVisualEffects {
    CGFloat blurAmount = DBClamp(DBFloat(@"BlurAmount", 0.0), 0.0, 1.0);
    if (blurAmount > 0.01) {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.translatesAutoresizingMaskIntoConstraints = NO;
        blur.alpha = blurAmount;
        [self.view addSubview:blur];
        [NSLayoutConstraint activateConstraints:@[
            [blur.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [blur.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [blur.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [blur.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
    }

    CGFloat dim = DBClamp(DBFloat(@"DimAmount", 0.12), 0.0, 0.85);
    if (dim > 0.0) {
        UIView *dimmer = [UIView new];
        dimmer.translatesAutoresizingMaskIntoConstraints = NO;
        dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:dim];
        [self.view addSubview:dimmer];
        [NSLayoutConstraint activateConstraints:@[
            [dimmer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [dimmer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [dimmer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [dimmer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
    }

    if (DBBool(@"ParticleEffects", YES)) {
        CAEmitterLayer *emitter = [CAEmitterLayer layer];
        emitter.emitterShape = kCAEmitterLayerLine;
        emitter.emitterMode = kCAEmitterLayerSurface;
        emitter.birthRate = 0.65;
        CAEmitterCell *cell = [CAEmitterCell emitterCell];
        cell.contents = (id)[self particleImage].CGImage;
        cell.birthRate = 5.0;
        cell.lifetime = 7.0;
        cell.lifetimeRange = 2.0;
        cell.velocity = 22.0;
        cell.velocityRange = 12.0;
        cell.yAcceleration = -5.0;
        cell.scale = 0.16;
        cell.scaleRange = 0.12;
        cell.alphaSpeed = -0.12;
        emitter.emitterCells = @[cell];
        [self.view.layer addSublayer:emitter];
        self.emitterLayer = emitter;
    }
}

- (void)addBranding {
    if (!DBBool(@"ShowBranding", YES)) return;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10.0;

    UILabel *title = [UILabel new];
    title.text = DBString(@"TitleText", @"DARK BOOT");
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:DBFloat(@"TitleSize", 48.0) weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.35;
    title.layer.shadowColor = UIColor.blackColor.CGColor;
    title.layer.shadowOpacity = 0.7;
    title.layer.shadowRadius = 12.0;

    UILabel *subtitle = [UILabel new];
    subtitle.text = DBString(@"SubtitleText", @"INITIALIZING SYSTEM");
    subtitle.textColor = [UIColor colorWithWhite:0.86 alpha:1.0];
    subtitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.adjustsFontSizeToFitWidth = YES;
    subtitle.minimumScaleFactor = 0.5;

    [stack addArrangedSubview:title];
    if (subtitle.text.length) [stack addArrangedSubview:subtitle];
    [self.view addSubview:stack];

    NSString *position = DBString(@"TextPosition", @"center");
    NSLayoutYAxisAnchor *anchor = [position isEqualToString:@"lower"] ? self.view.safeAreaLayoutGuide.bottomAnchor : self.view.centerYAnchor;
    NSLayoutConstraint *vertical = [position isEqualToString:@"lower"]
        ? [stack.bottomAnchor constraintEqualToAnchor:anchor constant:-90.0]
        : [stack.centerYAnchor constraintEqualToAnchor:anchor constant:10.0];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:34.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-34.0],
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        vertical
    ]];
}

- (void)addProgressBar {
    if (!DBBool(@"ShowProgress", YES)) return;
    UIView *track = [UIView new];
    track.translatesAutoresizingMaskIntoConstraints = NO;
    track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    track.layer.cornerRadius = 2.0;
    track.clipsToBounds = YES;
    [self.view addSubview:track];
    [NSLayoutConstraint activateConstraints:@[
        [track.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.42],
        [track.heightAnchor constraintEqualToConstant:4.0],
        [track.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [track.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-42.0]
    ]];

    CALayer *fill = [CALayer layer];
    fill.backgroundColor = DBAccentColor().CGColor;
    fill.cornerRadius = 2.0;
    fill.anchorPoint = CGPointMake(0.0, 0.5);
    fill.transform = CATransform3DMakeScale(0.0, 1.0, 1.0);
    [track.layer addSublayer:fill];
    self.progressFillLayer = fill;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [self addVisualMedia];
    [self addVisualEffects];
    [self addBranding];
    [self addProgressBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.gradientLayer.frame = self.view.bounds;
    self.videoLayer.frame = self.view.bounds;
    self.emitterLayer.frame = self.view.bounds;
    self.emitterLayer.emitterPosition = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) + 10.0);
    self.emitterLayer.emitterSize = CGSizeMake(CGRectGetWidth(self.view.bounds), 1.0);
    if (self.progressFillLayer.superlayer) self.progressFillLayer.frame = self.progressFillLayer.superlayer.bounds;
}

- (void)beginProgressWithDuration:(NSTimeInterval)duration {
    if (!self.progressFillLayer) return;
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.scale.x"];
    animation.fromValue = @0.0;
    animation.toValue = @1.0;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    [self.progressFillLayer addAnimation:animation forKey:@"darkboot-progress"];
}

- (void)stopMedia {
    [self.videoPlayer pause];
    self.videoPlayer = nil;
    self.videoLayer.player = nil;
    if (self.videoLoopObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.videoLoopObserver];
        self.videoLoopObserver = nil;
    }
}

- (void)dealloc {
    [self stopMedia];
}

@end

#pragma mark - Presenter

@interface DBBootPresenter : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) DBBootViewController *contentController;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL previousIdleTimerDisabled;
+ (instancetype)sharedPresenter;
- (void)scheduleStartup;
- (void)presentPreview:(BOOL)isPreview;
- (void)playSoundOnly;
- (void)dismissNow;
@end

@implementation DBBootPresenter

+ (instancetype)sharedPresenter {
    static DBBootPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ presenter = [DBBootPresenter new]; });
    return presenter;
}

- (UIWindow *)currentKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) return candidate;
            }
        }
    }
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) return candidate;
    }
    return nil;
}

- (UIWindow *)newOverlayWindow {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState != UISceneActivationStateUnattached) {
                window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                break;
            }
        }
    }
    if (!window) window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.frame = UIScreen.mainScreen.bounds;
    window.windowLevel = UIWindowLevelAlert + 1500.0;
    window.backgroundColor = UIColor.blackColor;
    window.accessibilityViewIsModal = YES;
    return window;
}

- (void)configureAudioSession {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    BOOL respectSilent = DBBool(@"RespectSilentSwitch", NO);
    AVAudioSessionCategory category = respectSilent ? AVAudioSessionCategoryAmbient : AVAudioSessionCategoryPlayback;
    AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionMixWithOthers;
    if (DBBool(@"DuckOtherAudio", YES)) options |= AVAudioSessionCategoryOptionDuckOthers;
    [session setCategory:category mode:AVAudioSessionModeDefault options:options error:nil];
    [session setActive:YES error:nil];
}

- (void)playStartupSound {
    [self.audioPlayer stop];
    self.audioPlayer = nil;
    if (!DBBool(@"SoundEnabled", YES)) return;

    [self configureAudioSession];
    NSString *path = DBCustomSoundPath();
    if (path.length) {
        NSError *error = nil;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
        if (player && !error) {
            player.volume = DBClamp(DBFloat(@"Volume", 0.85), 0.0, 1.0);
            [player prepareToPlay];
            [player play];
            self.audioPlayer = player;
            return;
        }
    }
    if (DBBool(@"FallbackChime", YES)) AudioServicesPlaySystemSound(1007);
}

- (void)playSoundOnly {
    dispatch_async(dispatch_get_main_queue(), ^{ [self playStartupSound]; });
}

- (void)applyEntranceAnimationToWindow:(UIWindow *)window {
    NSString *animation = DBString(@"EntryAnimation", @"cinematic");
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    window.alpha = 0.0;
    window.transform = CGAffineTransformIdentity;

    if (!reduceMotion) {
        if ([animation isEqualToString:@"zoom"]) window.transform = CGAffineTransformMakeScale(1.10, 1.10);
        else if ([animation isEqualToString:@"pulse"]) window.transform = CGAffineTransformMakeScale(0.90, 0.90);
        else if ([animation isEqualToString:@"slide"]) window.transform = CGAffineTransformMakeTranslation(0.0, 90.0);
        else if ([animation isEqualToString:@"cinematic"]) window.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.06, 1.06), CGAffineTransformMakeTranslation(0.0, 20.0));
    }

    [UIView animateWithDuration:reduceMotion ? 0.25 : 0.62
                          delay:0
         usingSpringWithDamping:[animation isEqualToString:@"pulse"] ? 0.68 : 0.90
          initialSpringVelocity:0.25
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        window.alpha = 1.0;
        window.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)animateDismissalForWindow:(UIWindow *)window completion:(dispatch_block_t)completion {
    NSString *animation = DBString(@"ExitAnimation", @"fade");
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:reduceMotion ? 0.22 : 0.52 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        window.alpha = 0.0;
        if (!reduceMotion) {
            if ([animation isEqualToString:@"zoom"]) window.transform = CGAffineTransformMakeScale(1.08, 1.08);
            else if ([animation isEqualToString:@"shrink"]) window.transform = CGAffineTransformMakeScale(0.88, 0.88);
            else if ([animation isEqualToString:@"slide"]) window.transform = CGAffineTransformMakeTranslation(0.0, -85.0);
        }
    } completion:^(__unused BOOL finished) {
        if (completion) completion();
    }];
}

- (void)scheduleStartup {
    if (!DBShouldShowForCurrentLaunch()) return;
    NSTimeInterval delay = DBClamp(DBFloat(@"InitialDelay", 0.35), 0.0, 8.0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self presentPreview:NO];
    });
}

- (void)presentPreview:(BOOL)isPreview {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self presentPreview:isPreview]; });
        return;
    }
    if (!isPreview && !DBBool(@"Enabled", YES)) return;

    [self dismissNow];
    DBEnsureMediaDirectory();
    [@"active" writeToFile:DBSessionMarkerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    self.generation += 1;
    NSUInteger currentGeneration = self.generation;
    self.previousKeyWindow = [self currentKeyWindow];
    self.previousIdleTimerDisabled = UIApplication.sharedApplication.idleTimerDisabled;
    if (DBBool(@"KeepScreenAwake", YES)) UIApplication.sharedApplication.idleTimerDisabled = YES;

    DBBootViewController *controller = [DBBootViewController new];
    UIWindow *window = [self newOverlayWindow];
    window.rootViewController = controller;
    self.contentController = controller;
    self.window = window;

    if (DBBool(@"TapToDismiss", YES)) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissNow)];
        [window addGestureRecognizer:tap];
    }
    if (DBBool(@"SwipeToDismiss", YES)) {
        UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismissNow)];
        swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
        [window addGestureRecognizer:swipeUp];
        UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismissNow)];
        swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
        [window addGestureRecognizer:swipeDown];
    }

    [window makeKeyAndVisible];
    [self applyEntranceAnimationToWindow:window];
    [self playStartupSound];

    if (DBBool(@"HapticOnStart", NO)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [feedback prepare];
        [feedback impactOccurred];
    }

    NSTimeInterval duration = DBClamp(DBFloat(@"Duration", 4.5), 1.0, 30.0);
    [controller beginProgressWithDuration:duration];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.generation != currentGeneration || self.window != window) return;
        if (DBBool(@"FadeSound", YES) && self.audioPlayer.isPlaying) {
            [self.audioPlayer setVolume:0.0 fadeDuration:0.45];
        }
        [self animateDismissalForWindow:window completion:^{
            if (self.generation == currentGeneration) [self dismissNow];
        }];
    });
}

- (void)dismissNow {
    self.generation += 1;
    [self.audioPlayer stop];
    self.audioPlayer = nil;
    [self.contentController stopMedia];
    self.contentController = nil;
    self.window.hidden = YES;
    self.window.rootViewController = nil;
    self.window = nil;
    if (self.previousKeyWindow) [self.previousKeyWindow makeKeyWindow];
    self.previousKeyWindow = nil;
    UIApplication.sharedApplication.idleTimerDisabled = self.previousIdleTimerDisabled;
    [[NSFileManager defaultManager] removeItemAtPath:DBSessionMarkerPath error:nil];
    DBSetPreference(@"CrashGuardCount", @0);
    DBSetPreference(@"CrashGuardSuppressed", @NO);
}

@end

#pragma mark - Darwin notifications and SpringBoard hook

static void DBNotificationCallback(__unused CFNotificationCenterRef center,
                                   __unused void *observer,
                                   CFStringRef name,
                                   __unused const void *object,
                                   __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (CFEqual(name, DBPreviewNotification)) {
            [[DBBootPresenter sharedPresenter] presentPreview:YES];
        } else if (CFEqual(name, DBSoundPreviewNotification)) {
            [[DBBootPresenter sharedPresenter] playSoundOnly];
        }
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[DBBootPresenter sharedPresenter] scheduleStartup];
}
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        DBEnsureMediaDirectory();
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(center, NULL, DBNotificationCallback, DBReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, DBNotificationCallback, DBPreviewNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, DBNotificationCallback, DBSoundPreviewNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
