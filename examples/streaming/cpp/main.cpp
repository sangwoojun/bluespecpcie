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
		((uint32_t*)dmabuf)[i] = 0xcc;
		//dmabuf[i] = (char)i;
	}
	for ( uint32_t i = 0; i < 4*1024/4; i++ ) {
		((uint32_t*)dmabuf)[i] = i;
		//dmabuf[i] = (char)i;
	}
	for ( int i = 0; i < 16; i++ ) {
		dmabuf[i] = 0xaa;
	}
	for ( int i = 0; i < 32; i++ ) {
		printf( "++ %d %x\n", i, ((uint32_t*)dmabuf)[i] );
	}
	/*
	for ( int i = 0; i < 8; i++ ) {
		pcie->userWriteWord(1*4,4+i);
	}
	for ( int i = 0; i < 8; i++ ) {
		pcie->userWriteWord(0,i);
	}
	*/
	int pagecnt = 1024;
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
	while (pages < pagecnt) {
		usleep(100);
		pages = pcie->userReadWord(0);
	}
	clock_gettime(CLOCK_REALTIME, & now);
	double diff = timespec_diff_sec(start, now);
	printf( "Elapsed: %f\n", diff );

	printf( "r %x\n", pcie->userReadWord(0) );
	printf( "w %x\n", pcie->userReadWord(4) );
	/*
	for ( int i = 0; i < 32; i++ ) {
		printf( "x %x\n", pcie->userReadWord(0) );
	}
	*/
	for ( int i = 0; i < 32; i++ ) {
		printf( "-- %d %x\n", i, ((uint32_t*)dmabuf)[i+1024/4*4] );
	}
	
	for ( int i = 2; i < 16; i++ ) {
		printf( "+++ %x\n", pcie->userReadWord(i*4) );
	}

	printf( "!! %x\n", pcie->readWord(4) );

	exit(0);

	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < 1024*1024*32; i++ ) {
		pcie->userWriteWord(0, 8);
	}

	clock_gettime(CLOCK_REALTIME, & now);
	diff = timespec_diff_sec(start, now);
	printf( "DMA HW->SW elapsed: %f\n", diff );
	sleep(1);

	printf( "read 0: %x\n", pcie->userReadWord(0) );
	printf( "read 4: %x\n", pcie->userReadWord(4) );
	printf( "read 8: %x\n", pcie->userReadWord(8) );


	uint32_t* buf32 = (uint32_t*)dmabuf;
	for ( int i = 0; i < 8; i++ ) {
		printf( "%d %x\n", i, buf32[i] );
		buf32[i] = i;
	}

	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < 1024*1024*32; i++ ) {
		pcie->userWriteWord(4, 8);
	}

	clock_gettime(CLOCK_REALTIME, & now);
	diff = timespec_diff_sec(start, now);
	printf( "DMA SW->HW elapsed: %f\n", diff );
	
	sleep(1);
	
	printf( "read  0: %x\n", pcie->userReadWord(0) );
	printf( "read  4: %x\n", pcie->userReadWord(4) );
	printf( "read  8: %x\n", pcie->userReadWord(8) );
	printf( "read 12: %x\n", pcie->userReadWord(12) );
	printf( "read 16: %x\n", pcie->userReadWord(16) );
	printf( "read 20: %x\n", pcie->userReadWord(20) );
	printf( "read 24: %x\n", pcie->userReadWord(24) );
	
	sleep(1);

	//printf( "Requesting memread with size %d\n", size );
	//dma->sendWord(0, size,0,0,0);

/*
	while (1) {
		PCIeWord w = dma->recvWord();
		printf( "%x %x %x %x %x\n", w.header, w.d[0], w.d[1], w.d[2], w.d[3] );
		if ( w.header == 0 ) break;
	}
*/




/*
	FlashManager* flash = FlashManager::getInstance();

	uint32_t* pageBufferW = (uint32_t*)malloc(8192+32);
	uint32_t* pageBufferR = (uint32_t*)malloc(8192+32);
	for ( int i = 0; i < 8192/4; i++ ) {
		pageBufferW[i] = i;
	}
	printf( "Sending erase message:\n" );
	flash->eraseBlock(1,1,1);
	//sleep(1);
	flash->writePage(1,1,1,0, pageBufferW);

	sleep(5);

	exit(1);

	
	printf( "\t\tSending read cmd\n" );


	flash->readPage(1,1,1,0, pageBufferR);
	
	
	printf( "\t\tStarting read\n" );
	sleep(1);
	
	for ( int i = 0; i < (8192+32)/4; i++ ) {
		int idx = i % 4;
		uint32_t r = pcie->readWord((1024+1+idx)*4);
		printf( "%d:%x ", i, r );
		if ( i % 8 == 0 ) printf( "\n" );
	}
	*/



/*
	for ( int i = 0; i < 1024; i++ ) {
		pcie->writeWord((1024+3)*4, 0);
	}
	
	pcie->writeWord((1024+1)*4, 0);

	pcie->writeWord(1024*4, 4);
	for ( int i = 0; i < 32; i++ ) {
		pcie->writeWord(1024*4, 8);
	}
	sleep(1);
	pcie->writeWord((1024+1)*4, 0);


	for ( int i = 0; i < 4096; i++ ) {
		if ( ubuf[i] != 0 ) {
			printf( "%d: %x\n", i, ubuf[i] );
		}
	}
	*/
}
