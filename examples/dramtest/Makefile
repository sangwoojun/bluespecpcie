LIBPATH =../../
BOARD=kc705

BSVPATH =$(LIBPATH)/src/:
COREPATH =$(LIBPATH)/core/$(BOARD)/
DRAMPATH =$(LIBPATH)/dram/src/

BSCFLAGS = -show-schedule -aggressive-conditions --wait-for-license 

BSCFLAGS_SYNTH = -bdir ./build/obj -vdir ./build/verilog/top -simdir ./build/obj -info-dir ./build -fdir ./build -D $(BOARD)
BSCFLAGS_BSIM = -bdir ./bsim/obj -vdir ./bsim/verilog/top -simdir ./bsim/obj -info-dir ./bsim -fdir ./bsim

BSIM_CPPFILES =$(LIBPATH)/cpp/PcieBdpi.cpp \
	$(LIBPATH)/cpp/ShmFifo.cpp

DEBUGFLAGS = -D BSIM


## change txdiffctrl in auroraintra to 1100



all:
	mkdir -p build/obj
	mkdir -p build/verilog/top
	bsc  $(BSCFLAGS) $(BSCFLAGS_SYNTH) -remove-dollar -p +:$(BSVPATH) -p +:$(DRAMPATH) -verilog -u -g mkProjectTop Top.bsv 
	cp vivado-impl-$(BOARD).tcl ./build/impl.tcl
	cd build; cd verilog/top; ../../../verilogcopy.sh; cd ../../; vivado -mode batch -source impl.tcl
	tar czf c.tgz build/
	mv c.tgz build/

bsim: HwMain.bsv Top.bsv
	mkdir -p bsim
	mkdir -p bsim/obj
	mkdir -p bsim/verilog/top
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -p +:$(BSVPATH) -sim -u -g mkProjectTop_bsim Top.bsv  
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -sim -e mkProjectTop_bsim -o bsim/obj/bsim bsim/obj/*.ba $(BSIM_CPPFILES) 

clean:
	rm -rf build
	rm -rf bsim

.PHONY: all

core:
	cd $(COREPATH) ; vivado -mode batch -source core_gen_pcie.tcl -nolog -nojournal
