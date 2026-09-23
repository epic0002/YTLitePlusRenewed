TARGET := iphone:clang:16.5:14.0
THEOS ?= ../../theos
ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTLitePlusRenewed
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unused-function "-I." "-I.." "-I../../YouTubeHeader" "-I../../"
$(TWEAK_NAME)_FILES = \
Tweak.processed.xm

include YTScript/YTScript.mk
include $(THEOS_MAKE_PATH)/tweak.mk