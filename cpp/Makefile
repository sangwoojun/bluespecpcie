CC=g++

SRCDIR=.
CPPFILES=$(wildcard $(SRCDIR)/*.cpp)
INCDIR=../src

CFLAGS=-static -Wall -pedantic --std=c++11 -march=native -O2 -I$(INCDIR) -lrt

OUTPUTDIR=./obj
OBJ=$(patsubst $(SRCDIR)%,$(OUTPUTDIR)%, $(CPPFILES:.cpp=.o))

$(OUTPUTDIR)/libbluespecpcie.a : $(OBJ)
	ar rcs $(OUTPUTDIR)/libbluespecpcie.a $(OBJ)

$(OUTPUTDIR)/%.o : $(SRCDIR)/%.cpp | $(OUTPUTDIR)
	$(CC) -c -o $@ $< $(CFLAGS) 

$(OUTPUTDIR):
	mkdir -p $(OUTPUTDIR)

.PHONY: clean
clean:
	rm -r $(OUTPUTDIR)
