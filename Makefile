ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DarkBoot
DarkBoot_FILES = Tweak.xm
DarkBoot_CFLAGS = -fobjc-arc -Wall -Wextra
DarkBoot_FRAMEWORKS = UIKit AVFoundation AudioToolbox QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "sbreload"
