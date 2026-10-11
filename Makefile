# Tube — nativer, server-freier YouTube-Client für iPod touch 4 (iOS 6.1, ARMv7), Theos.
TARGET = iphone:clang:7.1:6.0
ARCHS  = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Tube

Tube_FILES  = $(wildcard src/*.m)
Tube_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation MediaPlayer AVFoundation
Tube_CFLAGS  = -fobjc-arc -O2 -Wall -Isrc -Ivendor/mbedtls/include
Tube_LDFLAGS = -Lvendor/mbedtls/lib
Tube_LIBRARIES = mbedtls mbedx509 mbedcrypto

include $(THEOS_MAKE_PATH)/application.mk
