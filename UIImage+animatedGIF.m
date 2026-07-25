#import "UIImage+animatedGIF.h"
#import <ImageIO/ImageIO.h>

@implementation UIImage (animatedGIF)

static NSTimeInterval G2FrameDelay(CGImageSourceRef source, size_t index) {
    NSTimeInterval delay = 0.10;
    CFDictionaryRef propertiesRef = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    NSDictionary *properties = CFBridgingRelease(propertiesRef);
    NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSNumber *value = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    if (!value || value.doubleValue < 0.02) value = gif[(NSString *)kCGImagePropertyGIFDelayTime];
    if (value.doubleValue >= 0.02) delay = value.doubleValue;
    return delay;
}

static UIImage *G2AnimatedImageFromSource(CGImageSourceRef source) {
    if (!source) return nil;
    size_t sourceCount = CGImageSourceGetCount(source);
    if (sourceCount == 0) return nil;

    const size_t maximumDecodedFrames = 180;
    size_t step = MAX((size_t)1, (size_t)ceil((double)sourceCount / (double)maximumDecodedFrames));
    NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:MIN(sourceCount, maximumDecodedFrames)];
    NSTimeInterval totalDuration = 0;

    NSDictionary *thumbnailOptions = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @2048,
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
    };

    for (size_t index = 0; index < sourceCount; index += step) {
        @autoreleasepool {
            CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, index, (__bridge CFDictionaryRef)thumbnailOptions);
            if (!imageRef) imageRef = CGImageSourceCreateImageAtIndex(source, index, NULL);
            if (!imageRef) continue;
            UIImage *frame = [UIImage imageWithCGImage:imageRef scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp];
            CGImageRelease(imageRef);
            if (frame) {
                [frames addObject:frame];
                totalDuration += G2FrameDelay(source, index) * step;
            }
        }
    }

    if (!frames.count) return nil;
    if (frames.count == 1) return frames.firstObject;
    return [UIImage animatedImageWithImages:frames duration:MAX(0.05, totalDuration)];
}

+ (UIImage *)animatedImageWithAnimatedGIFData:(NSData *)data {
    if (!data.length) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    UIImage *image = G2AnimatedImageFromSource(source);
    if (source) CFRelease(source);
    return image;
}

+ (UIImage *)animatedImageWithAnimatedGIFURL:(NSURL *)url {
    if (!url.isFileURL) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    UIImage *image = G2AnimatedImageFromSource(source);
    if (source) CFRelease(source);
    return image;
}

@end
