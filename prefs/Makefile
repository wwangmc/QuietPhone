TYPE ?= 1
ARCHS ?= arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = QuietPhonePrefs
QuietPhonePrefs_FILES = QPRootListController.m
QuietPhonePrefs_CFLAGS = -fobjc-arc
QuietPhonePrefs_FRAMEWORKS = UIKit Foundation
QuietPhonePrefs_PRIVATE_FRAMEWORKS = Preferences
QuietPhonePrefs_INSTALL_PATH = /Library/PreferenceBundles
QuietPhonePrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
