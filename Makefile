TARGET := iphone:clang:latest:17.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME := AudioCoexistServer
AudioCoexistServer_FILES := Server.mm
AudioCoexistServer_FRAMEWORKS := Foundation
AudioCoexistServer_LIBRARIES := roothide
AudioCoexistServer_CFLAGS := -fobjc-arc -Wall -Wextra
include $(THEOS_MAKE_PATH)/tweak.mk
TOOL_NAME := audio-coexist
audio-coexist_FILES := Control.m
audio-coexist_FRAMEWORKS := Foundation
audio-coexist_LIBRARIES := roothide
audio-coexist_CFLAGS := -fobjc-arc
audio-coexist_INSTALL_PATH := /usr/libexec/AudioCoexistServer
audio-coexist_CODESIGN_FLAGS := -SEntitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
