################################################################################
#
# cv610-streamer
#
################################################################################

CV610_STREAMER_VERSION = 6a41ebe6d4dd7b9700d314747a05c4eb7be36ca0
CV610_STREAMER_SITE = https://github.com/snokvist/hi3519dv500-openipc-venc.git
CV610_STREAMER_SITE_METHOD = git
CV610_STREAMER_LICENSE = MIT
CV610_STREAMER_LICENSE_FILES = LICENSE
CV610_STREAMER_DEPENDENCIES = hisilicon-opensdk hisilicon-osdrv-hi3516cv6xx

CV610_STREAMER_APP_DIR = $(@D)/src/app/cv610_streamer
CV610_STREAMER_SENSOR_DIR = $(@D)/src/sensor/hi3516cv6xx/sony_imx662
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
	$(INSTALL) -D -m 644 $(CV610_STREAMER_PKGDIR)/files/load-hisilicon.conf \
		$(TARGET_DIR)/etc/load-hisilicon.conf
	$(INSTALL) -D -m 755 $(CV610_STREAMER_PKGDIR)/files/S95cv610-streamer \
		$(TARGET_DIR)/etc/init.d/S95cv610-streamer
endef

$(eval $(generic-package))
