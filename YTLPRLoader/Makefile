TARGET := iphone:clang:latest:14.0
THEOS ?= ../../theos
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = YTLPRLoader
YTLPRLoader_FILES = Loader.m Settings.m
YTLPRLoader_FRAMEWORKS = UIKit Foundation
YTLPRLoader_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
YTLPRLoader_LDFLAGS = -Wl,-install_name,@rpath/YTLPRLoader.dylib
YTLPRLoader_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk
