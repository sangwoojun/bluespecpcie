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

	int writeStatOff = 256*4;
	int readStatOff = 257*4;
	int pageCnt = 1024*4;

	uint32_t writeDoneCnt = pcie->userReadWord(writeStatOff);
	uint32_t readDoneCnt = pcie->userReadWord(readStatOff);

	for ( int i = 0; i < 1024*256; i++ ) { // 1MB
		dmabuf32[i] = i;// | (0xcc<<24);
	}

	timespec start;
	timespec now;
	double diff = 0;


	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < pageCnt; i++ ) {
		pcie->userWriteWord(256*4, 0); // host mem page 1 
		pcie->userWriteWord(257*4, 4); // fpga mem page 2
		pcie->userWriteWord(258*4, 64); // copy 256 Pages host->fpga
	}

	while ( writeDoneCnt + pageCnt > pcie->userReadWord(writeStatOff) );

	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %lf\n", timespec_diff_sec(start,now));
	
	sleep(1);

	for ( int i = 0; i < 1024*256; i++ ) { // 1MB
		dmabuf32[i] = 0;
	}

	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < 1024*4; i++ ) {
		pcie->userWriteWord(256*4, 0); // host mem page 1 
		pcie->userWriteWord(257*4, 12); // fpga mem page 2
		pcie->userWriteWord(259*4, 64); // copy 256 Pages fpga->host
	}
	
	while ( readDoneCnt + pageCnt > pcie->userReadWord(readStatOff) );

	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %lf\n", timespec_diff_sec(start,now));

	sleep(1);

	for ( int i = 0; i < 1024; i++ ) {
		printf( "%x\n", dmabuf32[i]);
	}

	printf( "%x -- %x\n", pcie->userReadWord(writeStatOff), pcie->userReadWord(readStatOff) );
	//printf( "%x -- %x\n", pcie->userReadWord(256*4), pcie->userReadWord(257*4) );

}
