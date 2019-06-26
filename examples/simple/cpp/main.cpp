#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}


int main(int argc, char** argv) {
	//printf( "Software startec\n" ); fflush(stdout);
	BdbmPcie* pcie = BdbmPcie::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);

	pcie->userWriteWord(4, 0xdeadbeef);
	pcie->userWriteWord(0, 0xcafef00d);

	pcie->userWriteWord(12, 0);
	pcie->Ioctl(1,0); // refresh link
	sleep(1);
	for ( int i = 0; i < 8; i++ ) {
		printf( "read: %x\n", pcie->userReadWord(i*4) );
		//sleep(1);
	}

	printf( "Starting performance testing\n" );
	timespec start;
	timespec now;
	
	clock_gettime(CLOCK_REALTIME, & start);
	//for ( int i = 0; i < 1024*1024*256/4; i++ ) { // 256MB
	for ( int i = 0; i < 1024; i++ ) { // 256MB
		pcie->userWriteWord(8, 0xcccccaaf);
		//usleep(1001);
	}
	clock_gettime(CLOCK_REALTIME, & now);
	double diff = timespec_diff_sec(start, now);

	printf( "read: %x\n", pcie->userReadWord(4) );
	printf( "Write elapsed: %f\n", diff );
	fflush(stdout);

	clock_gettime(CLOCK_REALTIME, & start);
	
	//for ( int i = 0; i < 1024*1024*256/4; i++ ) { // 256MB
	for ( int i = 0; i < 1024; i++ ) { // 256MB
		pcie->userReadWord(4);
	}
	clock_gettime(CLOCK_REALTIME, & now);
	diff = timespec_diff_sec(start, now);
	printf( "Read elapsed: %f\n", diff );
	return 0;
}
