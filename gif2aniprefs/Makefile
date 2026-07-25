ARCHS = arm64
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Gif2AniPrefs
Gif2AniPrefs_FILES = gif2ani2RootListController.m G2ThemeGalleryController.m
Gif2AniPrefs_INSTALL_PATH = /Library/PreferenceBundles
Gif2AniPrefs_FRAMEWORKS = UIKit UniformTypeIdentifiers ImageIO QuartzCore
Gif2AniPrefs_PRIVATE_FRAMEWORKS = Preferences
Gif2AniPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Gif2Ani.plist$(ECHO_END)
