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

    // Hard limits for the 2 GB iPad. The old build could retain up to 180
    // 2048-pixel frames inside backboardd, which is enough to kill it.
    const size_t maximumDecodedFrames = 24;
    const size_t maximumPixelSize = 640;
    const size_t maximumDecodedBytes = 48ULL * 1024ULL * 1024ULL;
    size_t step = MAX((size_t)1, (size_t)ceil((double)sourceCount / (double)maximumDecodedFrames));
    NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:MIN(sourceCount, maximumDecodedFrames)];
    NSTimeInterval totalDuration = 0;
    size_t decodedBytes = 0;

    NSDictionary *thumbnailOptions = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maximumPixelSize),
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
    };

    for (size_t index = 0; index < sourceCount; index += step) {
        @autoreleasepool {
            CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, index, (__bridge CFDictionaryRef)thumbnailOptions);
            if (!imageRef) continue;

            size_t frameBytes = CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef);
            if (frameBytes == 0 || decodedBytes + frameBytes > maximumDecodedBytes) {
                CGImageRelease(imageRef);
                break;
            }

            UIImage *frame = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
            CGImageRelease(imageRef);
            if (frame) {
                [frames addObject:frame];
                decodedBytes += frameBytes;
                totalDuration += G2FrameDelay(source, index) * step;
            }
        }
    }

    if (!frames.count) return nil;
    if (frames.count == 1) return frames.firstObject;
    return [UIImage animatedImageWithImages:frames duration:MAX(0.05, totalDuration)];
}

+ (UIImage *)animatedImageWithAnimatedGIFData:(NSData *)data {
    if (!data.length || data.length > 25ULL * 1024ULL * 1024ULL) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    UIImage *image = G2AnimatedImageFromSource(source);
    if (source) CFRelease(source);
    return image;
}

+ (UIImage *)animatedImageWithAnimatedGIFURL:(NSURL *)url {
    if (!url.isFileURL) return nil;
    NSNumber *fileSize = nil;
    [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    if (fileSize.unsignedLongLongValue > 25ULL * 1024ULL * 1024ULL) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    UIImage *image = G2AnimatedImageFromSource(source);
    if (source) CFRelease(source);
    return image;
}

@end
