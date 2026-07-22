################################################################################
#
# cv610-streamer
#
################################################################################

CV610_STREAMER_VERSION = b7897a3597c688b78790f3a660a3f2c90d7a40a9
CV610_STREAMER_SITE = https://github.com/snokvist/hi3519dv500-openipc-venc.git
CV610_STREAMER_SITE_METHOD = git
CV610_STREAMER_LICENSE = MIT
CV610_STREAMER_LICENSE_FILES = LICENSE
CV610_STREAMER_DEPENDENCIES = linux hisilicon-opensdk hisilicon-osdrv-hi3516cv6xx

CV610_STREAMER_APP_DIR = $(@D)/src/app/cv610_streamer
CV610_STREAMER_SENSOR_DIR = $(@D)/src/sensor/hi3516cv6xx/sony_imx662
CV610_STREAMER_PM_STUB_DIR = $(@D)/src/kernel/cv610_pm_stub
CV610_STREAMER_PERSISTENT_DIR = $(@D)/tools/cv610/persistent
CV610_STREAMER_SDK_DIR = $(BUILD_DIR)/hisilicon-opensdk-$(HISILICON_OPENSDK_VERSION)

define CV610_STREAMER_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(CV610_STREAMER_APP_DIR) clean
	$(TARGET_MAKE_ENV) $(MAKE) -C $(CV610_STREAMER_APP_DIR) \
		CC="$(TARGET_CC)" \
		SDK_INC="$(CV610_STREAMER_SDK_DIR)" \
		SDK_LIB="$(TARGET_DIR)/usr/lib"
	$(TARGET_MAKE_ENV) $(MAKE) -C $(CV610_STREAMER_SENSOR_DIR) clean
	$(TARGET_MAKE_ENV) $(MAKE) -C $(CV610_STREAMER_SENSOR_DIR) \
		CC="$(TARGET_CC)" AR="$(TARGET_AR)" \
		ISP_DIR="$(CV610_STREAMER_SDK_DIR)/libraries/isp" \
		KO_DIR="$(CV610_STREAMER_SDK_DIR)/kernel" \
		COMMON="$(CV610_STREAMER_SDK_DIR)/libraries/sensor/hi3516cv6xx/common"
	$(TARGET_MAKE_ENV) $(MAKE) -C $(CV610_STREAMER_PM_STUB_DIR) clean \
		KDIR="$(LINUX_DIR)" \
		CROSS_COMPILE="$(TARGET_CROSS)"
	$(TARGET_MAKE_ENV) $(MAKE) -C $(CV610_STREAMER_PM_STUB_DIR) \
		KDIR="$(LINUX_DIR)" \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		MPP_SYMVERS="$(CV610_STREAMER_SDK_DIR)/kernel/Module.symvers"
endef

define CV610_STREAMER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 755 $(CV610_STREAMER_APP_DIR)/cv610_streamer \
		$(TARGET_DIR)/usr/bin/cv610_streamer
	$(INSTALL) -D -m 755 $(CV610_STREAMER_APP_DIR)/cv610_venc_ctl \
		$(TARGET_DIR)/usr/bin/cv610_venc_ctl
	$(INSTALL) -D -m 755 $(CV610_STREAMER_APP_DIR)/cv610_isp_ctl \
		$(TARGET_DIR)/usr/bin/cv610_isp_ctl
	$(INSTALL) -D -m 755 $(CV610_STREAMER_SENSOR_DIR)/libsns_imx662.so \
		$(TARGET_DIR)/usr/lib/sensors/libsns_imx662.so
	$(INSTALL) -D -m 644 $(CV610_STREAMER_PKGDIR)/files/cv610-streamer.conf \
		$(TARGET_DIR)/etc/cv610-streamer.conf
	$(INSTALL) -D -m 755 $(CV610_STREAMER_PERSISTENT_DIR)/S70vendor \
		$(TARGET_DIR)/etc/init.d/S70vendor
	$(INSTALL) -D -m 755 $(CV610_STREAMER_PERSISTENT_DIR)/S95cv610-streamer \
		$(TARGET_DIR)/etc/init.d/S95cv610-streamer
	$(INSTALL) -D -m 755 $(CV610_STREAMER_PERSISTENT_DIR)/load-cv610-online \
		$(TARGET_DIR)/usr/bin/load-cv610-online
	$(INSTALL) -D -m 644 $(CV610_STREAMER_PM_STUB_DIR)/open_pm_stub.ko \
		$(TARGET_DIR)/usr/lib/cv610/open_pm_stub.ko
	$(INSTALL) -D -m 644 $(CV610_STREAMER_SDK_DIR)/kernel/open_sys_config.ko \
		$(TARGET_DIR)/usr/lib/cv610/open_sys_config_imx662.ko
endef

$(eval $(generic-package))
