#import "G2PreferencesManager.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const G2PreferencesPath = @"/var/mobile/Library/Preferences/com.nightvibes33.gif2ani.plist";

static UIColor *G2ColorFromHex(NSString *value) {
    NSString *hex = [[value ?: @"#000000" stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    NSArray<NSString *> *parts = [hex componentsSeparatedByString:@":"];
    hex = parts.firstObject;
    CGFloat alpha = parts.count > 1 ? MAX(0.0, MIN(1.0, parts[1].doubleValue)) : 1.0;
    if (hex.length == 8) {
        unsigned int rgba = 0;
        [[NSScanner scannerWithString:hex] scanHexInt:&rgba];
        return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0
                               green:((rgba >> 16) & 0xFF) / 255.0
                                blue:((rgba >> 8) & 0xFF) / 255.0
                               alpha:(rgba & 0xFF) / 255.0];
    }
    if (hex.length != 6) return [UIColor blackColor];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

@implementation G2PreferencesManager {
    NSDictionary *_values;
}

+ (instancetype)sharedInstance {
    static G2PreferencesManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [self new]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) [self reload];
    return self;
}

- (void)reload {
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:G2PreferencesPath];
    _values = [disk isKindOfClass:NSDictionary.class] ? [disk copy] : @{};
}

// Fail closed. A newly installed package must never activate inside backboardd
// until the user explicitly presses Apply and Respring.
- (BOOL)isEnabled { return _values[@"isEnabled"] ? [_values[@"isEnabled"] boolValue] : NO; }
- (NSString *)imageTransformation {
    NSString *value = _values[@"imageTransformation"];
    NSSet *allowed = [NSSet setWithArray:@[kCAGravityResizeAspect, kCAGravityResizeAspectFill, kCAGravityResize, kCAGravityCenter]];
    return [allowed containsObject:value] ? value : kCAGravityResizeAspect;
}
- (CGFloat)customLoop { return _values[@"customLoop"] ? [_values[@"customLoop"] doubleValue] : -1.0; }
- (CGFloat)customDuration { return _values[@"customDuration"] ? [_values[@"customDuration"] doubleValue] : -1.0; }
- (UIColor *)backgroundColor { return G2ColorFromHex(_values[@"backgroundColor"] ?: @"#000000"); }

@end
