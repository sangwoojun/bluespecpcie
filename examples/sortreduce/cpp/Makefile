LIBPATH=../../../
LIBOBJ=$(LIBPATH)/cpp/obj/

BDBMPCIEINCLUDE= -I$(LIBPATH)/cpp/
LIB= -lpthread -lbluespecpcie -L$(LIBOBJ) -lrt


all:
	echo "building for pcie"
	mkdir -p obj
	g++ main.cpp  $(BDBMPCIEINCLUDE) -o obj/main $(LIB) -pedantic -g -O2
bsim:
	echo "building for bluesim"
	mkdir -p obj
	g++ main.cpp $(BDBMPCIEINCLUDE) -o obj/bsim $(LIB) -DBLUESIM -g -pedantic
clean:
	rm -r obj
