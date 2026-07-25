#import "G2ThemeGalleryController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <math.h>
#import <stdio.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>
#import <fcntl.h>

extern char **environ;

static NSString * const G2PreferencesDomain = @"com.nightvibes33.gif2ani";
static NSString * const G2PreferencesPath = @"/var/mobile/Library/Preferences/com.nightvibes33.gif2ani.plist";
static NSString * const G2MediaDirectory = @"/var/mobile/Library/Application Support/Gif2Ani";
static NSString * const G2PendingGIFPath = @"/var/mobile/Library/Application Support/Gif2Ani/Pending.gif";
static NSString * const G2PendingMetadataPath = @"/var/mobile/Library/Application Support/Gif2Ani/pending-metadata.plist";
static NSString * const G2ImportedPacksDirectory = @"/var/mobile/Library/Application Support/Gif2Ani/Packs";
static const NSUInteger G2MaximumSourceFrames = 240;
static const NSUInteger G2MaximumDecodedFrames = 24;
static const NSUInteger G2MaximumPixelDimension = 640;
static const unsigned long long G2MaximumInputBytes = 25ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumEstimatedDecodedBytes = 48ULL * 1024ULL * 1024ULL;
static const NSUInteger G2MaximumImportedFiles = 5000;
static const unsigned long long G2MaximumArchiveBytes = 100ULL * 1024ULL * 1024ULL;
static const unsigned long long G2MaximumExtractedBytes = 150ULL * 1024ULL * 1024ULL;

static NSArray<NSDictionary *> *G2BuiltInPacks(void) {
    return @[
        @{@"identifier":@"pulse-rings", @"name":@"Pulse Rings", @"subtitle":@"Expanding neon rings", @"kind":@"builtin", @"style":@"pulse", @"background":@"#000000:1.000"},
        @{@"identifier":@"orbit-dots", @"name":@"Orbit Dots", @"subtitle":@"Eight orbiting light points", @"kind":@"builtin", @"style":@"orbit", @"background":@"#000000:1.000"},
        @{@"identifier":@"neon-bars", @"name":@"Neon Bars", @"subtitle":@"Rhythmic vertical light bars", @"kind":@"builtin", @"style":@"bars", @"background":@"#000000:1.000"},
        @{@"identifier":@"radar-sweep", @"name":@"Radar Sweep", @"subtitle":@"Rotating radar beam", @"kind":@"builtin", @"style":@"radar", @"background":@"#001008:1.000"},
        @{@"identifier":@"cyber-grid", @"name":@"Cyber Grid", @"subtitle":@"Scrolling perspective grid", @"kind":@"builtin", @"style":@"grid", @"background":@"#000000:1.000"},
        @{@"identifier":@"square-tunnel", @"name":@"Square Tunnel", @"subtitle":@"Infinite glowing tunnel", @"kind":@"builtin", @"style":@"tunnel", @"background":@"#000000:1.000"},
        @{@"identifier":@"equalizer", @"name":@"Equalizer", @"subtitle":@"Animated audio-style bars", @"kind":@"builtin", @"style":@"equalizer", @"background":@"#000000:1.000"},
        @{@"identifier":@"spark-burst", @"name":@"Spark Burst", @"subtitle":@"Radial energy particles", @"kind":@"builtin", @"style":@"spark", @"background":@"#000000:1.000"},
        @{@"identifier":@"halo-spinner", @"name":@"Halo Spinner", @"subtitle":@"Segmented luminous halo", @"kind":@"builtin", @"style":@"spinner", @"background":@"#000000:1.000"},
        @{@"identifier":@"glitch-blocks", @"name":@"Glitch Blocks", @"subtitle":@"Digital block distortion", @"kind":@"builtin", @"style":@"glitch", @"background":@"#000000:1.000"},
        @{@"identifier":@"energy-wave", @"name":@"Energy Wave", @"subtitle":@"Moving neon waveform", @"kind":@"builtin", @"style":@"wave", @"background":@"#000000:1.000"},
        @{@"identifier":@"rotating-cube", @"name":@"Rotating Cube", @"subtitle":@"Minimal rotating cube illusion", @"kind":@"builtin", @"style":@"cube", @"background":@"#000000:1.000"}
    ];
}

static NSArray<NSDictionary *> *G2LegacyCatalog(void) {
    return @[
        @{@"name":@"Alone", @"package":@"io.github.virenmohindra.alone"},
        @{@"name":@"Apple Glitch", @"package":@"io.github.virenmohindra.apple-glitch"},
        @{@"name":@"Bipolar Balls", @"package":@"io.github.virenmohindra.bipolar-balls"},
        @{@"name":@"Black Hole", @"package":@"io.github.virenmohindra.black-hole"},
        @{@"name":@"Blue", @"package":@"io.github.virenmohindra.blue"},
        @{@"name":@"Boo", @"package":@"io.github.virenmohindra.boo"},
        @{@"name":@"Bubbles", @"package":@"io.github.virenmohindra.bubbles"},
        @{@"name":@"Columns", @"package":@"io.github.virenmohindra.columns"},
        @{@"name":@"Complicated", @"package":@"io.github.virenmohindra.complicated"},
        @{@"name":@"Donuts", @"package":@"io.github.virenmohindra.donuts"},
        @{@"name":@"Ducky", @"package":@"io.github.virenmohindra.ducky"},
        @{@"name":@"Fall Leaves", @"package":@"io.github.virenmohindra.fall-leaves"},
        @{@"name":@"Fluid", @"package":@"io.github.virenmohindra.fluid"},
        @{@"name":@"Fragments", @"package":@"io.github.virenmohindra.fragments"},
        @{@"name":@"Funny Computer", @"package":@"io.github.virenmohindra.funny-computer"},
        @{@"name":@"Game Boy Advance", @"package":@"io.github.virenmohindra.gameboy-advance"},
        @{@"name":@"Glitchy", @"package":@"io.github.virenmohindra.glitchy-reuploaded"},
        @{@"name":@"Hello Again", @"package":@"io.github.virenmohindra.hello-again"},
        @{@"name":@"InfiniCube", @"package":@"io.github.virenmohindra.infinicube"},
        @{@"name":@"Joker", @"package":@"io.github.virenmohindra.joker"},
        @{@"name":@"Lines", @"package":@"io.github.virenmohindra.lines"},
        @{@"name":@"Loading", @"package":@"io.github.virenmohindra.loading"},
        @{@"name":@"Mograph", @"package":@"io.github.virenmohindra.mograph"},
        @{@"name":@"Particules Head", @"package":@"io.github.virenmohindra.particules-head"},
        @{@"name":@"Pizza", @"package":@"io.github.virenmohindra.pizza"},
        @{@"name":@"Pokémon", @"package":@"io.github.virenmohindra.pokemon"},
        @{@"name":@"Prismatic Head", @"package":@"io.github.virenmohindra.prismatic-head"},
        @{@"name":@"Rainy", @"package":@"io.github.virenmohindra.rainy"},
        @{@"name":@"Routine", @"package":@"io.github.virenmohindra.routine"},
        @{@"name":@"Spikey", @"package":@"io.github.virenmohindra.spikey"},
        @{@"name":@"Sploosh", @"package":@"io.github.virenmohindra.sploosh"},
        @{@"name":@"Super Mario", @"package":@"io.github.virenmohindra.super-mario"},
        @{@"name":@"Time And Money", @"package":@"io.github.virenmohindra.time-and-money"},
        @{@"name":@"Upload", @"package":@"io.github.virenmohindra.upload"},
        @{@"name":@"Yin And Yang", @"package":@"io.github.virenmohindra.yin-and-yang"}
    ];
}

static UIColor *G2RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIImage *G2ScaledImage(UIImage *image, CGFloat maximumDimension) {
    if (!image) return nil;
    CGSize source = image.size;
    CGFloat maximum = MAX(source.width, source.height);
    if (maximum <= maximumDimension || maximum <= 0) return image;
    CGFloat scale = maximumDimension / maximum;
    CGSize target = CGSizeMake(MAX(1.0, floor(source.width * scale)), MAX(1.0, floor(source.height * scale)));
    UIGraphicsBeginImageContextWithOptions(target, NO, 1.0);
    [image drawInRect:(CGRect){CGPointZero, target}];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static UIImage *G2RenderBuiltInFrame(NSString *style, NSUInteger index, NSUInteger count, CGSize size) {
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor blackColor] setFill];
    CGContextFillRect(ctx, (CGRect){CGPointZero, size});
    CGFloat t = count > 0 ? (CGFloat)index / (CGFloat)count : 0;
    CGPoint c = CGPointMake(size.width / 2.0, size.height / 2.0);
    CGFloat m = MIN(size.width, size.height);

    if ([style isEqualToString:@"pulse"]) {
        for (NSUInteger ring = 0; ring < 4; ring++) {
            CGFloat phase = fmod(t + ring * 0.25, 1.0);
            CGFloat radius = m * (0.08 + phase * 0.42);
            UIColor *color = G2RGB(0.1, 0.65 + ring * 0.06, 1.0, 1.0 - phase);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 5.0);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x-radius, c.y-radius, radius*2, radius*2));
        }
    } else if ([style isEqualToString:@"orbit"]) {
        for (NSUInteger dot = 0; dot < 8; dot++) {
            CGFloat angle = (CGFloat)(M_PI * 2.0 * (t + dot / 8.0));
            CGFloat radius = m * 0.30;
            CGPoint p = CGPointMake(c.x + cos(angle) * radius, c.y + sin(angle) * radius);
            CGFloat alpha = 0.25 + 0.75 * ((dot + index) % 8) / 7.0;
            [G2RGB(0.65, 0.25 + dot * 0.06, 1.0, alpha) setFill];
            CGContextFillEllipseInRect(ctx, CGRectMake(p.x-10, p.y-10, 20, 20));
        }
    } else if ([style isEqualToString:@"bars"] || [style isEqualToString:@"equalizer"]) {
        NSUInteger bars = [style isEqualToString:@"bars"] ? 9 : 13;
        CGFloat gap = 6.0;
        CGFloat width = (m * 0.72 - gap * (bars - 1)) / bars;
        CGFloat left = c.x - (width * bars + gap * (bars - 1)) / 2.0;
        for (NSUInteger i = 0; i < bars; i++) {
            CGFloat wave = (sin((t * M_PI * 2.0) + i * 0.72) + 1.0) / 2.0;
            CGFloat height = m * (0.12 + wave * 0.52);
            UIColor *color = [style isEqualToString:@"bars"] ? G2RGB(0.0, 0.85, 1.0, 1.0) : G2RGB(0.25 + i * 0.04, 1.0, 0.55, 1.0);
            [color setFill];
            UIBezierPath *bar = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(left + i * (width + gap), c.y-height/2.0, width, height) cornerRadius:width/2.0];
            [bar fill];
        }
    } else if ([style isEqualToString:@"radar"]) {
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.0, 0.9, 0.35, 0.45).CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        for (NSUInteger r = 1; r <= 4; r++) {
            CGFloat radius = m * 0.1 * r;
            CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x-radius, c.y-radius, radius*2, radius*2));
        }
        CGFloat angle = t * M_PI * 2.0;
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.1, 1.0, 0.45, 1.0).CGColor);
        CGContextSetLineWidth(ctx, 5.0);
        CGContextMoveToPoint(ctx, c.x, c.y);
        CGContextAddLineToPoint(ctx, c.x + cos(angle) * m * 0.42, c.y + sin(angle) * m * 0.42);
        CGContextStrokePath(ctx);
    } else if ([style isEqualToString:@"grid"]) {
        CGContextSetStrokeColorWithColor(ctx, G2RGB(0.0, 0.65, 1.0, 0.75).CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        for (NSInteger i = -6; i <= 6; i++) {
            CGFloat x = c.x + i * m * 0.07;
            CGContextMoveToPoint(ctx, c.x, c.y - m * 0.05);
            CGContextAddLineToPoint(ctx, x, size.height);
            CGContextStrokePath(ctx);
        }
        for (NSUInteger row = 0; row < 12; row++) {
            CGFloat phase = fmod((CGFloat)row / 12.0 + t, 1.0);
            CGFloat y = c.y + phase * c.y;
            CGFloat half = phase * m * 0.48;
            CGContextMoveToPoint(ctx, c.x-half, y);
            CGContextAddLineToPoint(ctx, c.x+half, y);
            CGContextStrokePath(ctx);
        }
    } else if ([style isEqualToString:@"tunnel"]) {
        for (NSUInteger square = 0; square < 8; square++) {
            CGFloat phase = fmod(t + square / 8.0, 1.0);
            CGFloat side = m * (0.08 + phase * 0.78);
            CGContextSetStrokeColorWithColor(ctx, G2RGB(0.8, 0.2 + 0.7 * phase, 1.0, 1.0-phase*0.55).CGColor);
            CGContextSetLineWidth(ctx, 4.0);
            CGContextStrokeRect(ctx, CGRectMake(c.x-side/2.0, c.y-side/2.0, side, side));
        }
    } else if ([style isEqualToString:@"spark"]) {
        for (NSUInteger ray = 0; ray < 18; ray++) {
            CGFloat angle = ray / 18.0 * M_PI * 2.0 + t * M_PI * 2.0;
