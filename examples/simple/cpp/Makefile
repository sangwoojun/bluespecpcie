LIBROOT=../../../
LIBPATH=$(LIBROOT)/cpp/obj/

BDBMPCIEINCLUDE= -I$(LIBROOT)/cpp/
LIB= -lrt -lpthread -lbluespecpcie -L$(LIBPATH)


all:
	echo "building for pcie"
	mkdir -p obj
	g++ main.cpp  $(BDBMPCIEINCLUDE) -o obj/main $(LIB) -pedantic -g -O2
bsim:
	echo "building for bluesim"
	mkdir -p obj
	g++ main.cpp $(BDBMPCIEINCLUDE) -o obj/bsim $(LIB) -DBLUESIM -g -pedantic
