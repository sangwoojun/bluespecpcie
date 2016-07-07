# If KERNELRELEASE is defined, we've been invoked from the
# kernel build system and can use its language.
# Otherwise we were called directly from the command
# line; invoke the kernel build system.

ifneq ($(KERNELRELEASE),)
	obj-m := bdbmpcie.o
else
	KERNELDIR ?= /lib/modules/$(shell uname -r)/build
	PWD := $(shell pwd)

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
endif

install:
	sudo cp ./bdbmpcie.ko /lib/modules/`uname -r`/
	sudo depmod -a
	sudo cp 99-bscpcie.rules /etc/udev/rules.d/

#insmod:
#	cp pcieconfig /sys/bus/pci/devices/0000:03:00.0/config
#	insmod ./bdbmpcie.ko
#	chmod agu+rw /dev/bdbm_regs0
#
#rmmod:
#	rmmod bdbmpcie
#
#configbackup:
#	cp pcieconfig _pcieconfig
#	cp /sys/bus/pci/devices/0000:03:00.0/config pcieconfig
