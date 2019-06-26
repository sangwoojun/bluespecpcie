LIBPATH=../../../
#LIBOBJ=$(LIBPATH)/cpp/obj/

BDBMPCIEINCLUDE= -I$(LIBPATH)/cpp/
BDBMPCIECPP= $(LIBPATH)/cpp/bdbmpcie.cpp $(LIBPATH)/cpp/ShmFifo.cpp $(LIBPATH)/cpp/DRAMHostDMA.cpp
LIB= -lrt


all:
	echo "building for pcie"
	mkdir -p obj
	g++ main.cpp $(BDBMPCIECPP) $(BDBMPCIEINCLUDE) -o obj/main $(LIB) -pedantic -g
bsim:
	echo "building for bluesim"
	mkdir -p obj
	g++ main.cpp $(BDBMPCIECPP) $(BDBMPCIEINCLUDE) -o obj/bsim $(LIB) -DBLUESIM -g -pedantic
