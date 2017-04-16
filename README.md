# Bluespec PCIe library

## Environment

- Development was done on Vivado 2015.4

## Structure

Example projects are located in the examples/ directory.

When creating a new project, it's simple to start by creating a copy of
an example project. examples/simple is the easiest to start with, for now.

If creating a project outside the example directory, some variables need to be
modified for the project to build correctly.

- in hardware Makefile, change **LIBPATH**
- in software Makefile, change **LIBPATH**
- in vivado-impl.tcl, change **pciedir**

The hardware design files are located in the top level, and software related
files are located in the **cpp** directory.

## Building

### Hardware design

Before building any projects, run **make core** once to generate the Xilinx PCIe
core. This only has to be done once.

FPGA bitfile can be created by running **make**

Bluesim binaries can be created by running **make bsim**

### Software design

Software for the FPGA bitfile can be created by running **make**

Software for bluesim can be created by running **make bsim**

## Running bluesim

run **./run.sh**

A symlink to the bsim software binary (or the actual binary) should be created
at the top level, with the name **./sw** . 

## Distributing for FPGA

The directory "distribution" should be copied to the target machine. (The one
with the FPGA)

The driver, and the pcie manager need to be installed by running "make" and
"sudo make install" in both directories.

Environment variable BLUEDBM_BINARY_DIR need to be set to where the compiled
bitfiles will be copied to.

## Programming and running the FPGA

After running "make" for the FPGA, a "c.tgz" will be created in the build/
directory. Copy it to where you set $BLUEDBM_BINARY_DIR

Run ./program.sh

Run bsman

bsman is usually installed to /opt/bluespecpcie\_manager/

If the FPGA did not already have a bluespecpcie-based project programmed onto
it, the system will need to be rebooted. If this is the case,
bsman will tell you.

If the system needs to be rebooted, run "bsman r" (with the
argument 'r'). This will reboot the system.

Once system is rebooted, run bsman again.

Run the software binary

## TODO

DMA reads are wonky

Some machines are having trouble with DMA

Non-dma seems to be stable...

