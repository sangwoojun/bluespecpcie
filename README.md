# Bluespec PCIe library

BluespecPCIe is a PCIe library for the Bluespec language.
It includes a Bluespec wrapper for the Xilinx PCIe core, device driver for Linux, as well as a userspace library for easily communicating with the FPGA device.
It supports DMA as well as memory-mapped I/O over PCIe.
It also supports reprogramming the FPGA and using the PCIe without rebooting in between.

The biggest strength of BluespecPCIe over other PCIe implementations is its simplicity.
A DMA memcpy demo builds in 5 minutes using vivado, and everything is designed to be plugged into a bluespec design as a module. BluespecPCIe does not need a special build tool, script or a meta language. 

BluespecPCIe currently supports the KC705 and VC707 boards.

BluespecPCIe is still under active development. If you discover bugs, or has feature requests, please let me know!

## Getting Started

### Clone bluelib
BluespecPCIe depends on the bluelib library, which can be found here [https://github.com/sangwoojun/bluelib](https://github.com/sangwoojun/bluelib).

By default, bluelib must be cloned at the same level as BluespecPCIe (e.g., ~/bluespecpcie and ~/bluelib). 
However, you can always change the individual Makefiles to point to different locations.

### Installing the software
- Driver: In **distribution/driver**, run **make**, and **sudo make install**.
- Rescan tool: **bsrescan** lets the BIOS recognize the PCIe device without system reboot between re-programming the FPGA. In **distribution/bsrescan**, run **make**, and **sudo make install**. This installs **bsrescan** to **/opt/bluespecpcie_manager/**. You may want to add **/opt/bluespecpcie_manager/** to your **PATH**.

### Building and running a demo
- Example designs are in **examples/**. For the basic demo, go to **examples/simple**.
- Generate the Xilinx core by running **make core BOARD=vc707** or **make core BOARD=kc705**, depending on the target board. This only needs to be done once.
- Build the demo by running **make BOARD=vc707** or **make BOARD=kc705**.
- Program the FPGA by running **vivado -mode batch -source ../../distribute/program.tcl**
- **_If_** this is the first time programming this FPGA device after board power-on, the system must be rebooted.
- **_If_** this device has been programmed and rebooted before, run **/opt/bluespecpcie_manager/bsrescan**. This will re-discover the device and reload the driver.
- The device is programmed and ready to communicate with. 
- Go to **./cpp** and run **make**.
- Run **./obj/main** to run the software demo.

## Working examples

- **example/simple**: Memory-mapped I/O example
- **example/dmatest**: DMA example
- **example/dramtest**: Uses the 1 GB on-board DRAM on both VC707 and KC705
- **example/float**: Floating point example


## Developing custom designs

When creating a new project, it's simple to start by creating a copy of an example project. 
If creating a project outside the example directory, some variables need to be modified for the project to build correctly.

- in hardware Makefile, change **LIBPATH**
- in software Makefile, change **LIBPATH**
- in vivado-impl.tcl, change **pciedir**

**Top.bsv** contains the top level module. The interface **interface PcieImportPins pcie_pins** and the top level input clocks and resets including **pcie_clk_p** neet to be maintaind.

Software related files are located in the **cpp** directory.

### Using more cores

You are free to copy and modify Makefile.base in the buildtools directory, as well as the vivado-impl\*.tcl files.

However, it may be simpler to add cores and other functionality using the **user-ip.tcl** file, which is included by the implementation tcl script before synthesis starts.
For example on how to use this, please look at the examples **dramtest** and **float**.


## Simulation using Bluesim.

BluespecPCIe emulates the PCIe using a shared memory FIFO.

When building the hardware, run **make bsim**.
When building the software, also run **make bsim**.

A symlink to the bsim software binary (or the actual binary) should be created at the top level (where the Makefile is), with the name **./sw**. 

To execute the hardware bsim simulation and software, run **./run.sh**.

**Note**: The shared memory files may not be correctly deleted after a run. You may have to delete them using **rm /dev/shm/bdbm\***

## Environment

- Development was done on Vivado 2018.2

