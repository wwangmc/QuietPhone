# Dopamine rootless only.
TYPE ?= 1
DEBUG = 0
FINALPACKAGE = 1

ifeq ($(TYPE),1)
ARCHS ?= arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
else
$(error QuietPhone supports TYPE=1 for Dopamine rootless)
endif

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QuietPhone
QuietPhone_FILES = Tweak.xm
QuietPhone_CFLAGS = -fobjc-arc
QuietPhone_CCFLAGS = -std=c++17
QuietPhone_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
