#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "dmacircularqueue.h"


int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMACircularQueue* dma = DMACircularQueue::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);

	for ( int i = 0; i < 8; i++ ) {
		printf( "read: %x\n", ((char*)dma->dmaBuffer())[i]);
	}
	sleep (2);
	printf( "\n" ); fflush(stdout);
	for ( int i = 0; i < 8; i++ ) {
		printf( "read: %x\n", ((uint64_t*)dma->dmaBuffer())[i]);
	}
	return 0;
}
