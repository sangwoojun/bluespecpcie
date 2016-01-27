BSCFLAGS = -show-schedule -aggressive-conditions --wait-for-license 

BSCFLAGS_SYNTH = -bdir ./build/obj -vdir ./build/verilog/top -simdir ./build/obj -info-dir ./build -fdir ./build
BSCFLAGS_BSIM = -bdir ./build_bsim/obj -vdir ./build_bsim/verilog/top -simdir ./build_bsim/obj -info-dir ./build_bsim -fdir ./build_bsim

BSVPATH =../../../src/:
BSIM_CPPFILES =../../../src/PcieBdpi.cpp \
	../../../src/ShmFifo.cpp

DEBUGFLAGS = -D BSIM


## change txdiffctrl in auroraintra to 1100



all:
	mkdir -p build/obj
	mkdir -p build/verilog/top
	bsc  $(BSCFLAGS) $(BSCFLAGS_SYNTH) -remove-dollar -p +:$(BSVPATH) -verilog -u -g mkProjectTop Top.bsv
	cp vivado-impl.tcl ./build/impl.tcl
	cd build; cd verilog/top; ../../../verilogcopy.sh; cd ../../; vivado -mode batch -source impl.tcl
	tar czf c.tgz build/
	mv c.tgz build/

bsim: HwMain.bsv Top.bsv
	mkdir -p build_bsim
	mkdir -p build_bsim/obj
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -p +:$(BSVPATH) -sim -u -g mkProjectTop_bsim Top.bsv  
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -sim -e mkProjectTop_bsim -o build_bsim/obj/bsim build_bsim/obj/*.ba $(BSIM_CPPFILES) 

clean:
	rm -rf build
	rm -rf build_bsim

.PHONY: all

core:
	cd ../../../core/ ; vivado -mode batch -source core_gen_pcie.tcl -nolog -nojournal
