# TYPE=0: rootful iOS 14+, TYPE=1: rootless iOS 15+.
TYPE ?= 1
ARCHS ?= arm64 arm64e

ifeq ($(TYPE),0)
QP_MIN_IOS = 14.0
THEOS_PACKAGE_SCHEME =
else ifeq ($(TYPE),1)
QP_MIN_IOS = 15.0
THEOS_PACKAGE_SCHEME = rootless
else
$(error Unsupported TYPE '$(TYPE)'; use 0 for rootful or 1 for rootless)
endif

TARGET = iphone:clang:16.5:$(QP_MIN_IOS)
