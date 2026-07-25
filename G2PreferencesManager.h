#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface G2PreferencesManager : NSObject
@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) NSString *imageTransformation;
@property (nonatomic, readonly) CGFloat customLoop;
@property (nonatomic, readonly) CGFloat customDuration;
@property (nonatomic, readonly) UIColor *backgroundColor;
+ (instancetype)sharedInstance;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
