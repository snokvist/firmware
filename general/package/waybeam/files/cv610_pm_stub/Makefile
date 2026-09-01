# Registration-only PM shim for the Hi3516CV610 B051 MPP stack.

KDIR ?= /lib/modules/$(shell uname -r)/build
CROSS_COMPILE ?= arm-openipc-linux-musleabi-
ARCH ?= arm
MPP_SYMVERS ?=

obj-m := open_pm_stub.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		KBUILD_EXTRA_SYMBOLS=$(MPP_SYMVERS) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) clean

.PHONY: all clean
