include Config.mk
DEBUG = 0
FINALPACKAGE = 1

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

# Theos generates staged control before this hook. Keep each package's
# firmware dependency aligned with its own deployment target.
before-package::
	$(ECHO_NOTHING)sed -e 's/firmware (>= 14.0)/firmware (>= $(QP_MIN_IOS))/g' "$(THEOS_STAGING_DIR)/DEBIAN/control" > "$(THEOS_STAGING_DIR)/DEBIAN/control.quietphone"$(ECHO_END)
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/DEBIAN/control.quietphone" "$(THEOS_STAGING_DIR)/DEBIAN/control"$(ECHO_END)
