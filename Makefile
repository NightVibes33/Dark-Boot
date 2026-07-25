ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DarkBoot
DarkBoot_FILES = Tweak.xm DBGraphicsCompat.m
DarkBoot_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations -Wno-error=missing-field-initializers -include $(THEOS_PROJECT_DIR)/DBGraphicsCompat.h
DarkBoot_FRAMEWORKS = UIKit AVFoundation AudioToolbox QuartzCore ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/DEBIAN
	@install -m 0755 packaging/postinst $(THEOS_STAGING_DIR)/DEBIAN/postinst
	@install -m 0755 packaging/prerm $(THEOS_STAGING_DIR)/DEBIAN/prerm

after-install::
	install.exec "killall -9 Preferences 2>/dev/null || true; sbreload"
