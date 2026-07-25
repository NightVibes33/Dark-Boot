@implementation G2ThemeGalleryController (G2DownloadableCatalogPolish)

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Built-In Themes • 12 Offline + 54 Downloadable";
    if (section == 1) return @"Installed or Imported Packs";
    return @"Legacy Source Catalog • 54 Known Packs";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Offline themes preview instantly. Downloadable themes are pinned CC0 GIFs: tap one, download and preview it, stage it, choose your settings, then Apply and Respring.";
    if (section == 1) return self.discovered.count
        ? @"Springy, SnowBoard Respring, GIF, frame-folder, ZIP, and DEB packs detected on this device appear here."
        : @"Tap + to import a compatible GIF, ZIP, DEB, or theme folder.";
    return @"These are compatibility references to older free packages. Free does not automatically grant redistribution rights, so their artwork is not silently rehosted or bundled.";
}

@end
