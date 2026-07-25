#import "DBGraphicsCompat.h"

@implementation UIGraphicsImageRendererContext (DarkBootEllipse)
- (void)fillEllipseInRect:(CGRect)rect {
    CGContextFillEllipseInRect(self.CGContext, rect);
}
@end
