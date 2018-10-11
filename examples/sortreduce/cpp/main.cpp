#include <stdio.h>
#include <unistd.h>
#include <algorithm>

#include "bdbmpcie.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	srand(time(NULL));
	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);

	
	uint8_t* dmabuf8 = (uint8_t*)pcie->dmaBuffer();
	uint32_t* dmabuf32 = (uint32_t*)dmabuf8;

	int writeStatOff = 256*4;
	int readStatOff = 257*4;
	int pages = 128;
	int pageCnt = (1024/4)*1024/pages;

	uint32_t writeDoneCnt = pcie->userReadWord(writeStatOff);
	uint32_t readDoneCnt = pcie->userReadWord(readStatOff);

	for ( int s = 0; s < 16; s++ ) {
		for ( int i = 0; i < 1024*256; i++ ) { // 1MB
			//dmabuf32[i] = rand();
			dmabuf32[i] = 0;
		}
		//std::sort(dmabuf32, dmabuf32+(1024*256));
		pcie->userWriteWord(256*4, 0); // host mem page
		pcie->userWriteWord(257*4, s*1024/4);// fpga mem page
		pcie->userWriteWord(258*4, 1024/4); // 1MB
	}
	while ( writeDoneCnt + 16 > pcie->userReadWord(writeStatOff) );
	writeDoneCnt = pcie->userReadWord(writeStatOff);
	printf( "Random/sorted data written to 16 buffers\n" );
	fflush(stdout);

/*
	for ( int s = 0; s < 1; s++ ) {
		pcie->userWriteWord(0*4, 0);
		pcie->userWriteWord(1*4, 1024*64);
		pcie->userWriteWord(8*4, s);// start reader
	}
*/
	for ( int i = 0; i < 1; i++ ) {
		for ( int s = 0; s < 8; s++ ) {
			pcie->userWriteWord(0*4, 0);
			pcie->userWriteWord(1*4, 1024*32*s); //FIXME
			pcie->userWriteWord(2*4, 1024);
			pcie->userWriteWord(9*4, s);// Add buffer to reader
		}
	}
	for ( int s = 0; s < 8; s++ ) {
		// indicates input done
		pcie->userWriteWord(0*4, 0);
		pcie->userWriteWord(1*4, 0);
		pcie->userWriteWord(2*4, 0);
		pcie->userWriteWord(9*4, s);// Add buffer to reader
	}

	while (true) {
		uint32_t cnt = pcie->userReadWord(0);
		uint32_t done = pcie->userReadWord(1*4);
		printf( "%d %d\n", cnt, done );
		for ( int i = 0; i < 8; i++ ) {
			printf( "%x ", pcie->userReadWord((i+2)*4));
		}
		printf( "\n" );
		sleep(1);
	}




	exit(0);



	for ( int i = 0; i < 1024*256; i++ ) { // 1MB
		//dmabuf32[i] = i;// | (0xcc<<24);
		dmabuf32[i] = (i/1024)<<24 | i;
	}

	timespec start;
	timespec now;
	double diff = 0;


	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < pageCnt; i++ ) {
		pcie->userWriteWord(256*4, 0); // host mem page
		pcie->userWriteWord(257*4, 4);// fpga mem page
		pcie->userWriteWord(258*4, pages); 
	}

	while ( writeDoneCnt + pageCnt > pcie->userReadWord(writeStatOff) );

	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %lf\n", timespec_diff_sec(start,now));
	
	sleep(1);

	for ( int i = 0; i < 1024*256; i++ ) { // 1MB
		dmabuf32[i] = 0;
	}

	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < pageCnt; i++ ) {
		pcie->userWriteWord(256*4, 0);
		pcie->userWriteWord(257*4, 4);
		pcie->userWriteWord(259*4, pages); 
	}
	
	while ( readDoneCnt + pageCnt > pcie->userReadWord(readStatOff) );

	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %lf\n", timespec_diff_sec(start,now));

	sleep(1);

	for ( int i = 0; i < 1024; i++ ) {
		printf( "%x\n", dmabuf32[i+1024]);
	}

	printf( "%x -- %x\n", pcie->userReadWord(writeStatOff), pcie->userReadWord(readStatOff) );
	//printf( "%x -- %x\n", pcie->userReadWord(256*4), pcie->userReadWord(257*4) );

}
