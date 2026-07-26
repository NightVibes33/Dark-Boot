#import "G2ThemeGalleryController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSArray<NSDictionary *> *G2OfflineBuiltInPacks(void);
static BOOL G2StageGIFAtPath(NSString *sourcePath, NSDictionary *recommended, NSError **error);
static NSArray<NSDictionary *> *G2LoadCachedOpenThemeCatalog(void);

@interface G2ThemeGalleryController (G2OpenThemeLibraryRefresh)
- (void)refreshOpenThemeLibrary;
@end

#include "G2RemoteThemeCatalog.inc"

#define G2BuiltInPacks G2OfflineBuiltInPacks
#include "G2ThemeGalleryPart1.inc"
#undef G2BuiltInPacks
#include "G2ThemeGalleryPart1Tail.inc"
#include "G2ThemeGalleryPart2.inc"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#define G2StageGIFAtPath G2LegacyStageGIFAtPath
#include "G2ThemeGalleryPart3.inc"
#undef G2StageGIFAtPath
#pragma clang diagnostic pop

#include "G2ThemeGalleryPart4.inc"

@interface G2ThemePreviewController (G2OpenThemeLibraryDownload)
- (void)g2_downloadOpenTheme;
@end

#include "G2ThemeGalleryPart5.inc"
#include "G2ThemeGalleryPart6.inc"

#include "G2ThemeStageOverride.inc"
#include "G2OpenThemeLibrary.inc"
#include "G2RemoteThemePreviewOverride.inc"
#include "G2RemoteGalleryPolish.inc"
