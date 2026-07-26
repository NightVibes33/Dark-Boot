#!/usr/bin/env python3
from pathlib import Path

modern = Path('gif2aniprefs/G2ModernGallery.inc')
text = modern.read_text()

storage_anchor = '''static unsigned long long G2MThemeStorageBytes(void) {
    return G2MDirectoryBytes(G2RemoteThemeCacheDirectory) +
           G2MDirectoryBytes(G2OpenThemeLibraryRoot) +
           G2MDirectoryBytes(G2ImportedPacksDirectory) +
           G2MDirectoryBytes(G2MRollbackDirectory);
}
'''
helper = storage_anchor + r'''

__attribute__((used)) static const char G2MDownloadAllNetworkMarker[] = "bounded-ephemeral-download-all";

static NSData *G2MDownloadPinnedRemoteData(NSURL *url, NSError **error) {
    if (!G2RemoteThemeURLIsAllowed(url)) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniModern" code:120 userInfo:@{NSLocalizedDescriptionKey:@"The CC0 theme URL is not on the pinned catalog host."}];
        return nil;
    }
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 60.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *downloaded = nil;
    __block NSURLResponse *finalResponse = nil;
    __block NSError *taskError = nil;
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        downloaded = data;
        finalResponse = response;
        taskError = networkError;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    long timedOut = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(65.0 * NSEC_PER_SEC)));
    if (timedOut != 0) {
        [task cancel];
        [session invalidateAndCancel];
        if (error) *error = [NSError errorWithDomain:@"Gif2AniModern" code:121 userInfo:@{NSLocalizedDescriptionKey:@"The CC0 theme download timed out safely."}];
        return nil;
    }
    [session finishTasksAndInvalidate];
    if (taskError) {
        if (error) *error = taskError;
        return nil;
    }
    NSInteger statusCode = [finalResponse isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)finalResponse statusCode] : 0;
    if (statusCode != 200 || !G2RemoteThemeURLIsAllowed(finalResponse.URL)) {
        if (error) *error = [NSError errorWithDomain:@"Gif2AniModern" code:122 userInfo:@{NSLocalizedDescriptionKey:@"The CC0 catalog returned an unexpected response or redirect."}];
        return nil;
    }
    return downloaded;
}
'''
if storage_anchor not in text:
    raise SystemExit('storage anchor missing')
text = text.replace(storage_anchor, helper, 1)

old_filter = '''    if ([self.g2mFilter isEqualToString:@"Offline"] && ![kind isEqualToString:@"builtin"]) return NO;
    if ([self.g2mFilter isEqualToString:@"Downloaded"] && cache != 1) return NO;
    if ([self.g2mFilter isEqualToString:@"Not Downloaded"] && !(([kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"]) && cache != 1)) return NO;
    if ([self.g2mFilter isEqualToString:@"Favorites"] && ![favorites containsObject:G2MThemeIdentifier(pack)]) return NO;
'''
new_filter = '''    BOOL downloadable = [kind isEqualToString:@"remote"] || [kind isEqualToString:@"sourceDeb"];
    if ([self.g2mFilter isEqualToString:@"Offline"] && ![kind isEqualToString:@"builtin"]) return NO;
    if ([self.g2mFilter isEqualToString:@"Downloaded"] && !(downloadable && cache == 1)) return NO;
    if ([self.g2mFilter isEqualToString:@"Not Downloaded"] && !(downloadable && cache != 1)) return NO;
    if ([self.g2mFilter isEqualToString:@"Favorites"] && ![favorites containsObject:G2MThemeIdentifier(pack)]) return NO;
'''
if old_filter not in text:
    raise SystemExit('filter anchor missing')
text = text.replace(old_filter, new_filter, 1)

old_download = '''                NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
                NSError *error = nil;
                NSData *data = G2RemoteThemeURLIsAllowed(url) ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error] : nil;
                if (!data || !G2RemoteDataMatchesManifest(data, pack, &error) || !G2ValidateGIFData(data, &error)) {
'''
new_download = '''                NSURL *url = [NSURL URLWithString:pack[@"downloadURL"]];
                NSError *error = nil;
                NSData *data = G2MDownloadPinnedRemoteData(url, &error);
                if (!data || !G2RemoteDataMatchesManifest(data, pack, &error) || !G2ValidateGIFData(data, &error)) {
'''
if old_download not in text:
    raise SystemExit('download anchor missing')
text = text.replace(old_download, new_download, 1)
modern.write_text(text)

control = Path('control')
control_text = control.read_text()
if 'Version: 3.5.0' not in control_text:
    raise SystemExit('unexpected control version')
control.write_text(control_text.replace('Version: 3.5.0', 'Version: 3.5.1', 1))
print('Gif2Ani 3.5.1 gallery filter and bounded download polish applied')
