#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"


int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);

	pcie->userWriteWord(0, 0xdeadbeef);
	pcie->userWriteWord(4, 0xcafef00d);

	for ( int i = 0; i < 8; i++ ) {
		printf( "read: %x\n", pcie->userReadWord(i*4) );
	}
	return 0;
}
