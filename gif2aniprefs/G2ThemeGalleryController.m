#import "G2ThemeGalleryController.h"
#import "gif2ani2RootListController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSArray<NSDictionary *> *G2OfflineBuiltInPacks(void);
static BOOL G2StageGIFAtPath(NSString *sourcePath, NSDictionary *recommended, NSError **error);
static NSArray<NSDictionary *> *G2LoadCachedOpenThemeCatalog(void);
static NSArray<NSDictionary *> *G2PreferredOpenThemeCatalog(void);
static NSDictionary *G2OpenThemeCachedInfo(NSDictionary *pack);
static BOOL G2RemoteCachedThemeIsValid(NSDictionary *pack);
static BOOL G2OpenThemeURLIsAllowed(NSURL *url, BOOL indexURL);

@interface G2ThemeGalleryController (G2OpenThemeLibraryRefresh)
- (void)refreshOpenThemeLibrary;
@end

@interface NSObject (G2OpenThemeLibraryDownloadDeclaration)
- (void)g2_downloadOpenTheme;
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
#define G2LoadCachedOpenThemeCatalog G2PreferredOpenThemeCatalog
#include "G2ThemeGalleryPart5.inc"
#undef G2LoadCachedOpenThemeCatalog
#include "G2ThemeGalleryPart6.inc"

#include "G2BundledOpenThemeCatalog.inc"

static NSArray<NSDictionary *> *G2PreferredOpenThemeCatalog(void) {
    NSArray<NSDictionary *> *bundled = G2BundledOpenThemeCatalog();
    // The bundled snapshot is independently verified and must be usable even
    // when an older on-device catalog.plist is malformed or stale.
    if (bundled.count >= 48) return bundled;

    NSArray<NSDictionary *> *cached = G2LoadCachedOpenThemeCatalog();
    return cached ?: @[];
}

#include "G2ThemeStageOverride.inc"
#include "G2OpenThemeLibrary.inc"
#include "G2RemoteThemePreviewOverride.inc"
#include "G2RemoteGalleryPolish.inc"
#include "G2ModernGallery.inc"

@implementation Gif2AniRootListController (G2ThemeGalleryNavigation)

- (void)openAnimationGallery {
    G2ModernThemeGalleryController *gallery = [[G2ModernThemeGalleryController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    gallery.modalPresentationStyle = UIModalPresentationFullScreen;
    if (self.navigationController) {
        [self.navigationController pushViewController:gallery animated:YES];
    } else {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:gallery];
        [self presentViewController:navigation animated:YES completion:nil];
    }
}

@end
