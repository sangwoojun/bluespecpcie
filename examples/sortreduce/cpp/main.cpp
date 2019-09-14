#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <time.h>

#include <algorithm>

#include "bdbmpcie.h"
//#include "dmasplitter.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	srand(time(NULL));

	
	pcie->userWriteWord(20, 0);

	for ( int b = 0; b < 16; b++ ) {
		printf( "Writing buffer %d\n",b ); fflush(stdout);
		uint32_t* buffer = (uint32_t*)malloc(8*1024*1024);
		for ( int i = 0; i < 1024*1024*2; i++ ){
			buffer[i] = rand();
		}
		std::sort(buffer, buffer+1024*1024*2);


		for ( int i = 0; i < 1024*1024*2; i++ ){
			pcie->userWriteWord(16, 1);
			pcie->userWriteWord(16, buffer[i]);
			//pcie->userWriteWord(16, i*16+b);
		}
	}
	
	for ( int b = 0; b < 16; b++ ) {
		pcie->userWriteWord(0, b);
		pcie->userWriteWord(4, ((1024*1024*256)/64/16)*b);
		pcie->userWriteWord(8, ((1024*1024*256)/64/16)*(b+1));
		pcie->userWriteWord(12, (1024*1024*256)/64/16);
	}

	

	uint32_t elapsed = 0;
	while (elapsed == 0 ) {
		elapsed = pcie->userReadWord(0);
	}
	printf( "elapsed: %d cycles\n", elapsed );

}
