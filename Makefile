ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Gif2Ani
Gif2Ani_FILES = Tweak.xm UIImage+animatedGIF.m G2PreferencesManager.m
Gif2Ani_FRAMEWORKS = UIKit ImageIO QuartzCore
Gif2Ani_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += gif2aniprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/DEBIAN
	@install -m 0755 packaging/postinst $(THEOS_STAGING_DIR)/DEBIAN/postinst
	@install -m 0755 packaging/prerm $(THEOS_STAGING_DIR)/DEBIAN/prerm

after-install::
	install.exec "killall -9 Preferences 2>/dev/null || true; /var/jb/usr/bin/sbreload 2>/dev/null || sbreload"
