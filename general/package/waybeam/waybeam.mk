################################################################################
#
# waybeam
#
################################################################################

WAYBEAM_VERSION = 0c660fc5d301bfa2235a6a7b5da40480fa0c7a3f
WAYBEAM_SITE = https://github.com/OpenIPC/waybeam.git
WAYBEAM_SITE_METHOD = git
WAYBEAM_GIT_SUBMODULES = YES
# The waybeam sources are MIT.  files/libbin.so is a third-party HiSilicon PQ
# library redistributed unmodified for the CV610 backend; it is not ours and
# not MIT, so the declaration names both rather than quietly widening MIT to
# cover a proprietary blob.
WAYBEAM_LICENSE = MIT, PROPRIETARY (files/libbin.so)
WAYBEAM_LICENSE_FILES = LICENSE

# Waybeam has one source tree with a backend per SoC. Keep the existing
# SigmaStar package behavior and add the CV610 backend used by waybeam_lite-ng.
WAYBEAM_DEPENDENCIES = linux

ifeq ($(BR2_PACKAGE_HISILICON_OSDRV_HI3516CV6XX),y)

WAYBEAM_DEPENDENCIES += hisilicon-opensdk hisilicon-osdrv-hi3516cv6xx opus-openipc
WAYBEAM_SDK_DIR = $(BUILD_DIR)/hisilicon-opensdk-$(HISILICON_OPENSDK_VERSION)
WAYBEAM_PM_STUB_DIR = $(WAYBEAM_PKGDIR)/files/cv610_pm_stub

define WAYBEAM_BUILD_CMDS
	# Waybeam's own CV610 stage builds its integrated/improved IMX662
	# userspace sensor driver; do not use the legacy VENC checkout here.
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) stage \
		SOC_BUILD=cv610 \
		CV610_CC="$(TARGET_CC)" \
		CV610_SDK_INC="$(WAYBEAM_SDK_DIR)" \
		CV610_SDK_LIB="$(TARGET_DIR)/usr/lib" \
		CV610_PQ_LIB="$(WAYBEAM_PKGDIR)/files/libbin.so"
	$(TARGET_MAKE_ENV) $(MAKE) -C $(WAYBEAM_PM_STUB_DIR) clean \
		KDIR="$(LINUX_DIR)" \
		CROSS_COMPILE="$(TARGET_CROSS)"
	$(TARGET_MAKE_ENV) $(MAKE) -C $(WAYBEAM_PM_STUB_DIR) \
		KDIR="$(LINUX_DIR)" \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		MPP_SYMVERS="$(WAYBEAM_SDK_DIR)/kernel/Module.symvers"
endef

define WAYBEAM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 755 $(@D)/out/cv610/waybeam \
		$(TARGET_DIR)/usr/bin/waybeam
	$(INSTALL) -D -m 755 $(@D)/out/cv610/load-cv610-online \
		$(TARGET_DIR)/usr/bin/load-cv610-online
	$(INSTALL) -D -m 755 $(@D)/out/cv610/S95waybeam \
		$(TARGET_DIR)/etc/init.d/S95waybeam
	$(INSTALL) -D -m 644 $(WAYBEAM_PKGDIR)/files/waybeam-cv610.conf \
		$(TARGET_DIR)/etc/waybeam-cv610.conf
	$(INSTALL) -D -m 644 $(WAYBEAM_PKGDIR)/files/waybeam-cv610.json \
		$(TARGET_DIR)/etc/waybeam.json
	$(INSTALL) -D -m 755 $(@D)/out/cv610/sensors/libsns_imx662.so \
		$(TARGET_DIR)/usr/lib/sensors/libsns_imx662.so
	$(INSTALL) -D -m 644 $(WAYBEAM_PM_STUB_DIR)/open_pm_stub.ko \
		$(TARGET_DIR)/usr/lib/cv610/open_pm_stub.ko
	$(INSTALL) -D -m 644 $(WAYBEAM_SDK_DIR)/kernel/open_sys_config.ko \
		$(TARGET_DIR)/usr/lib/cv610/open_sys_config_imx662.ko
	# Vendor PQ library.  Without it isp.sensorBin and /api/v1/iq/export_bin
	# warn and no-op; the craft still boots.  Staged by waybeam's own make
	# from CV610_PQ_LIB above, so there is one source of truth for the file.
	$(INSTALL) -D -m 755 $(@D)/out/cv610/lib/libbin.so \
		$(TARGET_DIR)/usr/lib/libbin.so
	# IQ restore point for this sensor.  Installed, but deliberately NOT
	# named by the default config: importing a bin at boot is opt-in, and
	# this one only reproduces the sensor plugin's own cold-boot state.
	$(INSTALL) -D -m 644 $(@D)/out/cv610/isp-bins/imx662.bin \
		$(TARGET_DIR)/etc/sensors/imx662.bin
endef

else

# The SigmaStar implementation remains the fork's existing package path.
WAYBEAM_SOC = star6e
WAYBEAM_MAKE_OPTS = SOC_BUILD=star6e STAR6E_CC="$(TARGET_CC)" CC_BIN="$(TARGET_CC)"
WAYBEAM_DEPENDENCIES += sigmastar-osdrv-sensors sigmastar-osdrv-infinity6e

define WAYBEAM_BUILD_CMDS
	$(MAKE) -C $(@D) build json_cli $(WAYBEAM_MAKE_OPTS)
	$(MAKE) -C $(@D)/drivers sensor SOC=$(WAYBEAM_SOC) \
		KSRC="$(LINUX_DIR)" CROSS="$(TARGET_CROSS)"
endef

define WAYBEAM_INSTALL_SENSOR_MODULES
	$(INSTALL) -m 0644 -D $(@D)/drivers/sensor_imx335_$(WAYBEAM_SOC).ko \
		$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/sigmastar/sensor_imx335_mipi.ko
	$(INSTALL) -m 0644 -D $(@D)/drivers/sensor_imx415_$(WAYBEAM_SOC).ko \
		$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/sigmastar/sensor_imx415_mipi.ko
endef
WAYBEAM_POST_INSTALL_TARGET_HOOKS += WAYBEAM_INSTALL_SENSOR_MODULES

define WAYBEAM_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/out/$(WAYBEAM_SOC)/waybeam \
		$(TARGET_DIR)/usr/bin/waybeam
	$(INSTALL) -m 0755 -D $(@D)/out/$(WAYBEAM_SOC)/json_cli \
		$(TARGET_DIR)/usr/bin/json_cli
	$(INSTALL) -m 0644 -D $(WAYBEAM_PKGDIR)/files/waybeam.json \
		$(TARGET_DIR)/etc/waybeam.json
	$(INSTALL) -m 0755 -D $(WAYBEAM_PKGDIR)/files/S95waybeam \
		$(TARGET_DIR)/etc/init.d/S95waybeam
endef

endif

$(eval $(generic-package))
