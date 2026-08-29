ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCAster

CCAster_FILES = Tweak.xm compat.m
CCAster_FRAMEWORKS = UIKit CoreFoundation CFNetwork QuartzCore CoreImage
CCAster_PRIVATE_FRAMEWORKS = ControlCenterServices SpringBoardUIServices
CCAster_CFLAGS = -fobjc-arc

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
