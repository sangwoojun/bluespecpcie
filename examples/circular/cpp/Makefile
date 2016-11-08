LIBPATH=../../../

BDBMPCIEFILES=$(LIBPATH)/src/ShmFifo.cpp $(LIBPATH)/cpp/bdbmpcie.cpp $(LIBPATH)/cpp/dmacircularqueue.cpp
BDBMPCIEINCLUDE= -I $(LIBPATH)/src/ -I $(LIBPATH)/cpp/
LIB= -lrt -lpthread 


all:
	echo "building for pcie"
	mkdir -p obj
	g++ main.cpp $(BDBMPCIEFILES) $(BDBMPCIEINCLUDE) -o obj/main $(LIB) -pedantic
bsim:
	echo "building for bluesim"
	mkdir -p obj
	g++ main.cpp $(BDBMPCIEFILES) $(BDBMPCIEINCLUDE) -o obj/bsim $(LIB) -DBLUESIM -g -pedantic

clean:
	rm -rf obj
