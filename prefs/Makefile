ARCHS = arm64
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DarkBootPrefs
DarkBootPrefs_FILES = DBRootListController.m
DarkBootPrefs_FRAMEWORKS = UIKit UniformTypeIdentifiers ImageIO AVFoundation QuartzCore
DarkBootPrefs_PRIVATE_FRAMEWORKS = Preferences
DarkBootPrefs_INSTALL_PATH = /Library/PreferenceBundles
DarkBootPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
