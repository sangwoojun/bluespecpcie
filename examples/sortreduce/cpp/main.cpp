#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);

	
	uint8_t* dmabuf8 = (uint8_t*)pcie->dmaBuffer();
	uint32_t* dmabuf32 = (uint32_t*)dmabuf8;


	for ( int i = 0; i < 1024*256; i++ ) { // 1MB
		dmabuf32[i] = i;// | (0xcc<<24);
	}

	pcie->userWriteWord(256*4, 2); // host mem page 1 
	pcie->userWriteWord(257*4, 4); // fpga mem page 2
	pcie->userWriteWord(258*4, 32); // copy 32 KB host->fpga
	
	sleep(1);

	for ( int i = 0; i < 1024*256; i++ ) { // 1MB
		dmabuf32[i] = 0;
	}

	pcie->userWriteWord(256*4, 0); // host mem page 1 
	pcie->userWriteWord(257*4, 12); // fpga mem page 2
	pcie->userWriteWord(259*4, 32); // copy 32 KB fpga->host

	sleep(1);

	for ( int i = 0; i < 1024; i++ ) {
		printf( "%x\n", dmabuf32[i]);
	}

	printf( "%x -- %x\n", pcie->userReadWord(256*4), pcie->userReadWord(257*4) );

}
