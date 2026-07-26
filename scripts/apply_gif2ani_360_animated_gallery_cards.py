#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODERN = ROOT / "gif2aniprefs/G2ModernGallery.inc"
CONTROL = ROOT / "control"
ROOT_PLIST = ROOT / "gif2aniprefs/Resources/Root.plist"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing {label} source block")
    return text.replace(old, new, 1)


def patch_modern_gallery() -> None:
    text = MODERN.read_text()

    text = replace_once(
        text,
        '''@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, copy) void (^favoriteHandler)(void);
@end
''',
        '''@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, copy) void (^favoriteHandler)(void);
@property (nonatomic, copy) NSString *previewIdentity;
@end
''',
        "cell preview identity property",
    )

    text = replace_once(
        text,
        '''- (void)prepareForReuse {
    [super prepareForReuse];
    self.favoriteHandler = nil;
    self.themeImageView.image = nil;
}
''',
        '''- (void)prepareForReuse {
    [super prepareForReuse];
    self.favoriteHandler = nil;
    self.previewIdentity = nil;
    [self.themeImageView stopAnimating];
    self.themeImageView.animationImages = nil;
    self.themeImageView.animationDuration = 0;
    self.themeImageView.animationRepeatCount = 0;
    self.themeImageView.image = nil;
}
''',
        "cell reuse cleanup",
    )

    text = replace_once(
        text,
        '''@property (nonatomic, strong) NSMutableArray<UIButton *> *g2mCategoryButtons;
@property (nonatomic, strong) NSMutableArray<UIButton *> *g2mFilterButtons;
@end
''',
        '''@property (nonatomic, strong) NSMutableArray<UIButton *> *g2mCategoryButtons;
@property (nonatomic, strong) NSMutableArray<UIButton *> *g2mFilterButtons;
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *g2mAnimatedCardPreviewCache;
@end
''',
        "controller animation cache property",
    )

    text = replace_once(
        text,
        '''    self.g2mCategory = @"All";
    self.g2mFilter = @"All";

    self.g2mSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
''',
        '''    self.g2mCategory = @"All";
    self.g2mFilter = @"All";
    self.g2mAnimatedCardPreviewCache = [NSCache new];
    self.g2mAnimatedCardPreviewCache.countLimit = 24;
    self.g2mAnimatedCardPreviewCache.totalCostLimit = 12 * 1024 * 1024;

    self.g2mSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
''',
        "controller animation cache initialization",
    )

    anchor = '''- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
'''
    helpers = '''- (void)g2m_applyAnimatedCardEntry:(NSDictionary *)entry toCell:(G2ModernThemeCell *)cell identity:(NSString *)identity {
    if (![cell.previewIdentity isEqualToString:identity]) return;
    NSArray<UIImage *> *frames = [entry[@"frames"] isKindOfClass:NSArray.class] ? entry[@"frames"] : @[];
    if (frames.count < 2) return;
    [cell.themeImageView stopAnimating];
    cell.themeImageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.themeImageView.image = frames.firstObject;
    cell.themeImageView.animationImages = frames;
    cell.themeImageView.animationDuration = MAX(0.8, [entry[@"duration"] doubleValue]);
    cell.themeImageView.animationRepeatCount = 0;
    [cell.themeImageView startAnimating];
}

- (BOOL)g2m_configureBundledAnimatedCardForCell:(G2ModernThemeCell *)cell
                                           pack:(NSDictionary *)pack
                                       identity:(NSString *)identity
                                      indexPath:(NSIndexPath *)indexPath {
    NSString *previewPath = G2BundledThemePreviewAnimationPath(pack);
    if (!previewPath.length) return NO;

    cell.previewIdentity = identity;
    [cell.themeImageView stopAnimating];
    cell.themeImageView.animationImages = nil;
    cell.themeImageView.animationDuration = 0;
    cell.themeImageView.animationRepeatCount = 0;
    cell.themeImageView.contentMode = UIViewContentModeScaleAspectFit;
    UIImage *staticPreview = G2BundledThemePreview(pack);
    cell.themeImageView.image = staticPreview ?: [UIImage systemImageNamed:@"photo.on.rectangle"];

    NSDictionary *cached = [self.g2mAnimatedCardPreviewCache objectForKey:identity];
    if (cached) {
        [self g2m_applyAnimatedCardEntry:cached toCell:cell identity:identity];
        return YES;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSArray<UIImage *> *frames = G2FramesFromGIF(previewPath, 176);
            if (frames.count < 2) return;
            NSTimeInterval duration = MAX(0.8, G2NaturalGIFDuration(previewPath));
            NSUInteger cost = 0;
            for (UIImage *frame in frames) {
                CGSize size = frame.size;
                CGFloat scale = MAX(1.0, frame.scale);
                cost += (NSUInteger)ceil(size.width * scale) * (NSUInteger)ceil(size.height * scale) * 4;
            }
            NSDictionary *entry = @{@"frames":frames, @"duration":@(duration)};
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf.g2mAnimatedCardPreviewCache setObject:entry forKey:identity cost:cost];
                G2ModernThemeCell *visible = (G2ModernThemeCell *)[strongSelf.tableView cellForRowAtIndexPath:indexPath];
                if (![visible isKindOfClass:G2ModernThemeCell.class]) return;
                [strongSelf g2m_applyAnimatedCardEntry:entry toCell:visible identity:identity];
            });
        }
    });
    return YES;
}

'''
    if "g2m_configureBundledAnimatedCardForCell" not in text:
        if anchor not in text:
            raise RuntimeError("missing modern cellForRow anchor")
        text = text.replace(anchor, helpers + anchor, 1)

    old_cell_setup = '''    NSString *cacheKey = [NSString stringWithFormat:@"modern-%@-%@", G2MThemeIdentifier(pack), pack[@"sha256"] ?: @""];
    UIImage *cached = [self.thumbnailCache objectForKey:cacheKey];
    if (cached) {
        cell.themeImageView.image = cached;
    } else {
        NSString *kind = pack[@"kind"];
        if ([kind isEqualToString:@"legacy"]) cell.themeImageView.image = [UIImage systemImageNamed:@"archivebox"];
        else if (([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"]) && state != 1) {
            UIImage *bundledPreview = G2BundledThemePreview(pack);
            cell.themeImageView.contentMode = bundledPreview ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
            cell.themeImageView.image = bundledPreview ?: [UIImage systemImageNamed:state == 2 ? @"arrow.triangle.2.circlepath.icloud" : @"icloud.and.arrow.down"];
        }
        else {
            cell.themeImageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                UIImage *thumb = nil;
                if ([kind isEqualToString:@"builtin"]) thumb = G2RenderBuiltInFrame(pack[@"style"], 0, 24, CGSizeMake(120, 120));
                else if ([kind isEqualToString:@"remote"]) thumb = G2ThumbnailFromGIF(G2RemoteThemeCachePath(pack), 140);
                else if ([kind isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(pack[@"path"], 140);
                else if ([kind isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(pack[@"path"], 140);
                else if ([kind isEqualToString:@"sourceDeb"]) {
                    NSDictionary *info = G2OpenThemeCachedInfo(pack);
                    if ([info[@"kind"] isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(info[@"path"], 140);
                    else if ([info[@"kind"] isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(info[@"path"], 140);
                }
                if (!thumb) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.thumbnailCache setObject:thumb forKey:cacheKey];
                    G2ModernThemeCell *visible = (G2ModernThemeCell *)[weakSelf.tableView cellForRowAtIndexPath:indexPath];
                    if ([visible isKindOfClass:G2ModernThemeCell.class]) visible.themeImageView.image = thumb;
                });
            });
        }
    }
'''
    new_cell_setup = '''    NSString *cacheKey = [NSString stringWithFormat:@"modern-%@-%@", G2MThemeIdentifier(pack), pack[@"sha256"] ?: @""];
    NSString *kind = pack[@"kind"];
    cell.previewIdentity = nil;
    [cell.themeImageView stopAnimating];
    cell.themeImageView.animationImages = nil;
    cell.themeImageView.animationDuration = 0;
    cell.themeImageView.animationRepeatCount = 0;

    BOOL downloadable = [kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"];
    BOOL animatedCard = downloadable && [self g2m_configureBundledAnimatedCardForCell:cell pack:pack identity:cacheKey indexPath:indexPath];
    if (!animatedCard) {
        UIImage *cached = [self.thumbnailCache objectForKey:cacheKey];
        if (cached) {
            cell.themeImageView.contentMode = UIViewContentModeScaleAspectFill;
            cell.themeImageView.image = cached;
        } else if ([kind isEqualToString:@"legacy"]) {
            cell.themeImageView.contentMode = UIViewContentModeCenter;
            cell.themeImageView.image = [UIImage systemImageNamed:@"archivebox"];
        } else {
            cell.themeImageView.contentMode = UIViewContentModeCenter;
            cell.themeImageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                UIImage *thumb = nil;
                if ([kind isEqualToString:@"builtin"]) thumb = G2RenderBuiltInFrame(pack[@"style"], 0, 24, CGSizeMake(120, 120));
                else if ([kind isEqualToString:@"remote"]) thumb = G2ThumbnailFromGIF(G2RemoteThemeCachePath(pack), 140);
                else if ([kind isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(pack[@"path"], 140);
                else if ([kind isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(pack[@"path"], 140);
                else if ([kind isEqualToString:@"sourceDeb"]) {
                    NSDictionary *info = G2OpenThemeCachedInfo(pack);
                    if ([info[@"kind"] isEqualToString:@"gif"]) thumb = G2ThumbnailFromGIF(info[@"path"], 140);
                    else if ([info[@"kind"] isEqualToString:@"frames"]) thumb = G2ThumbnailFromDirectory(info[@"path"], 140);
                }
                if (!thumb) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.thumbnailCache setObject:thumb forKey:cacheKey];
                    G2ModernThemeCell *visible = (G2ModernThemeCell *)[weakSelf.tableView cellForRowAtIndexPath:indexPath];
                    if (![visible isKindOfClass:G2ModernThemeCell.class] || visible.previewIdentity.length) return;
                    visible.themeImageView.contentMode = UIViewContentModeScaleAspectFill;
                    visible.themeImageView.image = thumb;
                });
            });
        }
    }
'''
    text = replace_once(text, old_cell_setup, new_cell_setup, "modern card image setup")

    did_select_anchor = '''- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
'''
    end_displaying = '''- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if (![cell isKindOfClass:G2ModernThemeCell.class]) return;
    G2ModernThemeCell *modernCell = (G2ModernThemeCell *)cell;
    modernCell.previewIdentity = nil;
    [modernCell.themeImageView stopAnimating];
    modernCell.themeImageView.animationImages = nil;
    modernCell.themeImageView.animationDuration = 0;
    modernCell.themeImageView.animationRepeatCount = 0;
}

'''
    if "didEndDisplayingCell" not in text:
        if did_select_anchor not in text:
            raise RuntimeError("missing didSelect anchor")
        text = text.replace(did_select_anchor, end_displaying + did_select_anchor, 1)

    marker_anchor = 'static const char *G2ModernGalleryMarker'
    if marker_anchor in text and "visible-card-bundled-animation-v360" not in text:
        # Preserve the existing marker layout while adding a searchable binary marker.
        marker_pos = text.index(marker_anchor)
        semicolon = text.index(";", marker_pos)
        text = text[: semicolon + 1] + '\nstatic const char *G2AnimatedCardPreviewMarker = "visible-card-bundled-animation-v360";' + text[semicolon + 1 :]

    MODERN.write_text(text)


def patch_version() -> None:
    lines = CONTROL.read_text().splitlines()
    description = (
        "Description: Crash-safe custom respring animations for BackBoard on rootless iOS 15 and 16. "
        "Gif2Ani 3.6.0 makes every downloadable CC0, Springy, and SnowBoard gallery card display its bundled animated preview before the source package is downloaded. "
        "Only visible cards decode frames; off-screen cells stop and release their animations, while a 12 MB bounded cache keeps scrolling responsive on 2 GB devices. "
        "It retains the 3.5.9 rootless archive environment fix, all 262 bundled animated downloadable previews, the 274-theme gallery, and pinned source integrity verification."
    )
    output = []
    for line in lines:
        if line.startswith("Version:"):
            output.append("Version: 3.6.0")
        elif line.startswith("Description:"):
            output.append(description)
        else:
            output.append(line)
    CONTROL.write_text("\n".join(output) + "\n")

    text = ROOT_PLIST.read_text().replace("GIF2ANI 3.5.9", "GIF2ANI 3.6.0")
    text = text.replace(
        "Expanded verified gallery with animated previews:",
        "Expanded verified gallery with animated card previews:",
    )
    ROOT_PLIST.write_text(text)


def verify() -> None:
    text = MODERN.read_text()
    control = CONTROL.read_text()
    root = ROOT_PLIST.read_text()
    required = [
        "g2mAnimatedCardPreviewCache",
        "G2BundledThemePreviewAnimationPath(pack)",
        "G2FramesFromGIF(previewPath, 176)",
        "visible-card-bundled-animation-v360",
        "didEndDisplayingCell",
        "animationImages = nil",
        "totalCostLimit = 12 * 1024 * 1024",
    ]
    for marker in required:
        assert marker in text, marker
    assert "Version: 3.6.0" in control
    assert "GIF2ANI 3.6.0" in root
    print("gif2ani_360_animated_gallery_cards=success")
    print("visible_only_animation=enabled")
    print("animation_cache_limit_bytes=12582912")


def main() -> None:
    patch_modern_gallery()
    patch_version()
    verify()


if __name__ == "__main__":
    main()
