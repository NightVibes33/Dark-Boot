#import "DBRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <spawn.h>

extern char **environ;

static NSString * const DBMediaDirectory = @"/var/mobile/Library/Application Support/DarkBoot";
static CFStringRef const DBReloadNotification = CFSTR("com.nightvibes33.darkboot/reload");
static CFStringRef const DBPreviewNotification = CFSTR("com.nightvibes33.darkboot/preview");

typedef NS_ENUM(NSInteger, DBImportKind) {
    DBImportKindImage,
    DBImportKindSound
};

@interface DBRootListController ()
@property (nonatomic, assign) DBImportKind importKind;
@end

@implementation DBRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Dark Boot";
}

- (void)ensureMediaDirectory {
    [[NSFileManager defaultManager] createDirectoryAtPath:DBMediaDirectory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:nil];
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importImage {
    self.importKind = DBImportKindImage;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importSound {
    self.importKind = DBImportKindSound;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    [self ensureMediaDirectory];

    NSError *error = nil;
    if (self.importKind == DBImportKindImage) {
        NSDictionary *options = @{
            (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (id)kCGImageSourceThumbnailMaxPixelSize: @2048
        };
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        CGImageRef thumbnail = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
        UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
        NSData *png = image ? UIImagePNGRepresentation(image) : nil;
        if (png) [png writeToFile:[DBMediaDirectory stringByAppendingPathComponent:@"boot-image.png"] options:NSDataWritingAtomic error:&error];
        else error = [NSError errorWithDomain:@"DarkBoot" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The selected image could not be decoded."}];
        if (thumbnail) CGImageRelease(thumbnail);
        if (source) CFRelease(source);
    } else {
        NSArray<NSString *> *oldFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DBMediaDirectory error:nil];
        for (NSString *name in oldFiles) {
            if ([name.lowercaseString hasPrefix:@"boot-sound."]) {
                [[NSFileManager defaultManager] removeItemAtPath:[DBMediaDirectory stringByAppendingPathComponent:name] error:nil];
            }
        }
        NSString *extension = url.pathExtension.lowercaseString;
        if (!extension.length) extension = @"audio";
        NSString *destination = [DBMediaDirectory stringByAppendingPathComponent:[@"boot-sound" stringByAppendingPathExtension:extension]];
        NSData *audio = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
        if (audio && !error) [audio writeToFile:destination options:NSDataWritingAtomic error:&error];
    }

    if (accessed) [url stopAccessingSecurityScopedResource];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    if (error) [self showMessage:@"Import failed" body:error.localizedDescription ?: @"Unknown error"];
    else [self showMessage:@"Imported" body:self.importKind == DBImportKindImage ? @"The boot image is ready. Tap Preview to test it." : @"The startup sound is ready. Tap Preview to test it."];
    (void)controller;
}

- (void)preview {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBPreviewNotification, NULL, NULL, YES);
}

- (void)resetMedia {
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DBMediaDirectory error:nil];
    for (NSString *name in files) {
        if ([name isEqualToString:@"boot-image.png"] || [name.lowercaseString hasPrefix:@"boot-sound."]) {
            [[NSFileManager defaultManager] removeItemAtPath:[DBMediaDirectory stringByAppendingPathComponent:name] error:nil];
        }
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DBReloadNotification, NULL, NULL, YES);
    [self showMessage:@"Reset complete" body:@"Dark-Boot will use its built-in gradient screen and fallback chime."];
}

- (void)respring {
    const char *paths[] = {"/var/jb/usr/bin/sbreload", "/usr/bin/sbreload"};
    for (NSUInteger index = 0; index < 2; index++) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:@(paths[index])]) {
            pid_t pid = 0;
            char *argv[] = {(char *)paths[index], NULL};
            if (posix_spawn(&pid, paths[index], NULL, NULL, argv, environ) == 0) return;
        }
    }
    [self showMessage:@"Unable to respring" body:@"Run sbreload from a terminal or respring from your package manager."];
}

@end
