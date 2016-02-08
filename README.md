Bluespec PCIe library

Development was done on Vivado 2015.4

NOTE:
	DMA buffer starting from 0 to 4096 bytes are reserved for hw->sw FIFO interface.
	I should figure out a way to make this region unusable to the user.

Run "make core" to generate the PCIe core before running "make" or "make bsim"

The target machine should have the driver copied somwhere
After programming the bitfile for the first time, you must do a reboot so the BIOS can discover the device.
After the reboot, run "sudo make configbackup" to back up the PCIe config data structure. (Must run as root)
All subsequent programming do not require reboots. "make rmmod" and "make insmod" is enough.

DMA buffer is only 2MB. Maybe it needs to be larger. 8MB?


