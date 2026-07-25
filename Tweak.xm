#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const DBPreferencesDomain = @"com.nightvibes33.darkboot";
static NSString * const DBMediaDirectory = @"/var/mobile/Library/Application Support/DarkBoot";
static CFStringRef const DBReloadNotification = CFSTR("com.nightvibes33.darkboot/reload");
static CFStringRef const DBPreviewNotification = CFSTR("com.nightvibes33.darkboot/preview");

static id DBPreference(NSString *key, id fallback) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:DBPreferencesDomain];
    id value = [defaults objectForKey:key];
    return value ?: fallback;
}

static BOOL DBBool(NSString *key, BOOL fallback) {
    return [DBPreference(key, @(fallback)) boolValue];
}

static CGFloat DBFloat(NSString *key, CGFloat fallback) {
    return [DBPreference(key, @(fallback)) doubleValue];
}

static NSString *DBString(NSString *key, NSString *fallback) {
    id value = DBPreference(key, fallback);
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

static NSString *DBCustomSoundPath(void) {
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DBMediaDirectory error:nil];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        if ([name.lowercaseString hasPrefix:@"boot-sound."]) {
            NSString *path = [DBMediaDirectory stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] isReadableFileAtPath:path]) return path;
        }
    }
    return nil;
}

@interface DBBootPresenter : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, assign) NSUInteger generation;
+ (instancetype)sharedPresenter;
- (void)presentPreview:(BOOL)isPreview;
- (void)dismissNow;
@end

@implementation DBBootPresenter

+ (instancetype)sharedPresenter {
    static DBBootPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ presenter = [DBBootPresenter new]; });
    return presenter;
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
    window.windowLevel = UIWindowLevelAlert + 1000.0;
    window.backgroundColor = UIColor.blackColor;
    return window;
}

- (UIViewController *)contentController {
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.blackColor;

    NSString *imagePath = [DBMediaDirectory stringByAppendingPathComponent:@"boot-image.png"];
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    if (image) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        NSString *mode = DBString(@"ContentMode", @"fill");
        if ([mode isEqualToString:@"fit"]) imageView.contentMode = UIViewContentModeScaleAspectFit;
        else if ([mode isEqualToString:@"stretch"]) imageView.contentMode = UIViewContentModeScaleToFill;
        else imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        [controller.view addSubview:imageView];
        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
            [imageView.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
            [imageView.topAnchor constraintEqualToAnchor:controller.view.topAnchor],
            [imageView.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor]
        ]];
    } else {
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = UIScreen.mainScreen.bounds;
        gradient.colors = @[
            (id)[UIColor colorWithRed:0.025 green:0.03 blue:0.055 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.08 green:0.10 blue:0.18 alpha:1.0].CGColor,
            (id)UIColor.blackColor.CGColor
        ];
        gradient.startPoint = CGPointMake(0.1, 0.0);
        gradient.endPoint = CGPointMake(0.9, 1.0);
        [controller.view.layer addSublayer:gradient];

        UILabel *title = [UILabel new];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = @"DARK BOOT";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont systemFontOfSize:52.0 weight:UIFontWeightBlack];
        title.textAlignment = NSTextAlignmentCenter;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.45;

        UILabel *subtitle = [UILabel new];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.text = @"ROOTLESS • iOS 16";
        subtitle.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
        subtitle.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        subtitle.textAlignment = NSTextAlignmentCenter;

        [controller.view addSubview:title];
        [controller.view addSubview:subtitle];
        [NSLayoutConstraint activateConstraints:@[
            [title.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
            [title.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor constant:-20.0],
            [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:controller.view.leadingAnchor constant:40.0],
            [title.trailingAnchor constraintLessThanOrEqualToAnchor:controller.view.trailingAnchor constant:-40.0],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:18.0],
            [subtitle.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor]
        ]];
    }
    return controller;
}

- (void)playStartupSound {
    [self.audioPlayer stop];
    self.audioPlayer = nil;
    if (!DBBool(@"SoundEnabled", YES)) return;

    NSString *path = DBCustomSoundPath();
    if (path.length) {
        NSError *error = nil;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
        if (player && !error) {
            player.volume = MIN(1.0, MAX(0.0, DBFloat(@"Volume", 0.8)));
            [player prepareToPlay];
            [player play];
            self.audioPlayer = player;
            return;
        }
    }
    if (DBBool(@"FallbackChime", YES)) AudioServicesPlaySystemSound(1007);
}

- (void)presentPreview:(BOOL)isPreview {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self presentPreview:isPreview]; });
        return;
    }
    if (!isPreview && !DBBool(@"Enabled", YES)) return;

    [self dismissNow];
    self.generation += 1;
    NSUInteger currentGeneration = self.generation;
    self.previousKeyWindow = UIApplication.sharedApplication.keyWindow;

    UIWindow *window = [self newOverlayWindow];
    window.rootViewController = [self contentController];
    self.window = window;

    if (DBBool(@"TapToDismiss", YES)) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissNow)];
        [window addGestureRecognizer:tap];
    }

    NSString *animation = DBString(@"Animation", @"zoom");
    window.alpha = 0.0;
    if ([animation isEqualToString:@"zoom"]) window.transform = CGAffineTransformMakeScale(1.08, 1.08);
    else if ([animation isEqualToString:@"pulse"]) window.transform = CGAffineTransformMakeScale(0.94, 0.94);

    [window makeKeyAndVisible];
    [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        window.alpha = 1.0;
        window.transform = CGAffineTransformIdentity;
    } completion:nil];

    [self playStartupSound];

    NSTimeInterval duration = MIN(15.0, MAX(1.0, DBFloat(@"Duration", 4.0)));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.generation != currentGeneration || self.window != window) return;
        [UIView animateWithDuration:0.55 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            window.alpha = 0.0;
            window.transform = CGAffineTransformMakeScale(1.025, 1.025);
        } completion:^(__unused BOOL finished) {
            if (self.generation == currentGeneration) [self dismissNow];
        }];
    });
}

- (void)dismissNow {
    [self.audioPlayer stop];
    self.audioPlayer = nil;
    self.window.hidden = YES;
    self.window.rootViewController = nil;
    self.window = nil;
    if (self.previousKeyWindow) [self.previousKeyWindow makeKeyWindow];
    self.previousKeyWindow = nil;
}

@end

static void DBNotificationCallback(__unused CFNotificationCenterRef center,
                                   __unused void *observer,
                                   CFStringRef name,
                                   __unused const void *object,
                                   __unused CFDictionaryRef userInfo) {
    BOOL preview = CFEqual(name, DBPreviewNotification);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (preview) [[DBBootPresenter sharedPresenter] presentPreview:YES];
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[DBBootPresenter sharedPresenter] presentPreview:NO];
    });
}
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DBNotificationCallback,
                                        DBReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DBNotificationCallback,
                                        DBPreviewNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
