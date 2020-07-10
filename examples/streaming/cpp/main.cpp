#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
//#include "dmasplitter.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	//DMASplitter* dma = DMASplitter::getInstance();

	//uint32_t size = 128*128;

/*
	if ( argc > 1 ) {
		size = atoi(argv[1]);
	}
*/
	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);
	d = pcie->readWord(32);
	printf( "Dma Addr 0: %x\n", d );
	fflush(stdout);
	
	for ( int i = 0; i < 4; i++ ) {
		printf( "+++ %x\n", pcie->userReadWord((2+i)*4) );
	}

	printf( "r %x\n", pcie->userReadWord(0) );
	printf( "w %x\n", pcie->userReadWord(4) );

	//uint8_t* dmabuf = (uint8_t*)dma->dmaBuffer();
	uint8_t* dmabuf = (uint8_t*)pcie->dmaBuffer();
	for ( uint32_t i = 0; i < 32*1024/4; i++ ) {
		((uint32_t*)dmabuf)[i] = i;
		//dmabuf[i] = (char)i;
	}
	for ( uint32_t i = 0; i < 4*1024/4; i++ ) {
		((uint32_t*)dmabuf)[i] = i;
		//dmabuf[i] = (char)i;
	}
	/*
	for ( int i = 0; i < 16; i++ ) {
		dmabuf[i] = 0xaa;
	}
	*/
	/*
	for ( int i = 0; i < 32; i++ ) {
		printf( "++ %d %x\n", i, ((uint32_t*)dmabuf)[i] );
	}
	*/
	/*
	for ( int i = 0; i < 8; i++ ) {
		pcie->userWriteWord(1*4,4+i);
	}
	for ( int i = 0; i < 8; i++ ) {
		pcie->userWriteWord(0,i);
	}
	*/
	int pagecnt = 4;
	timespec start;
	timespec now;
	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < pagecnt; i++ ) {
		pcie->userWriteWord(1*4,4+(i%4));
		pcie->userWriteWord(0,(i%4));
	}
	//sleep(1);
	/*
	for ( int i = 0; i < 8; i++ ) {
		printf( "r %x\n", pcie->userReadWord(0) );
		printf( "w %x\n", pcie->userReadWord(4) );
	}
	*/
	printf( "----\n" );
	/*
	for ( int i = 0; i < 8; i++ ) {
		printf( "r %x\n", pcie->userReadWord(0) );
		printf( "w %x\n", pcie->userReadWord(4) );
	}
	*/
	//sleep(2);
	uint32_t pages = 0;
	int sleepcnt = 0;
	while (pages < pagecnt) {
		pages = pcie->userReadWord(4);
		if ( pages >= pagecnt ) break;

		sleepcnt ++;
		if ( sleepcnt % 10000 == 0 ) {
			printf( "Pages-- %d\n", pages );
			printf( "!! %x\n", pcie->readWord(4) );
			printf( ">> %x\n", ((uint32_t*)dmabuf)[1024/4*4] );
		}
		usleep(10);
	}
	clock_gettime(CLOCK_REALTIME, & now);
	double diff = timespec_diff_sec(start, now);
	printf( "Elapsed: %f\n", diff );

	printf( "r %x\n", pcie->userReadWord(0) );
	printf( "w %x\n", pcie->userReadWord(4) );
	/*
	for ( int i = 0; i < 32; i++ ) {
		printf( "-- %d %x\n", i, ((uint32_t*)dmabuf)[i+1024/4*4] );
	}
	*/


	int incorrects = 0;
	for ( uint32_t i = 0; i < 1024*4/4; i++ ) {
		uint32_t d = ((uint32_t*)dmabuf)[i+1024/4*4];
		if ( i%8 == 0 ) {
			if (d != 0xdeadbeef) {
				printf ( "Data incorrect! %x != %x\n", 0xdeadbeef, d );
				incorrects ++;
			}
		} else {
			if (d != i) {
				printf ( "Data incorrect! %x != %x\n", i, d );
				incorrects++;
			}
		}
	}

	printf( "Incorrect datas: %d\n", incorrects );
	
	/*
	for ( int i = 2; i < 16; i++ ) {
		printf( "Data in BRAM: %x\n", pcie->userReadWord(i*4) );
	}
	*/

	printf( "DebugCode: %x\n", pcie->readWord(4) );

}
