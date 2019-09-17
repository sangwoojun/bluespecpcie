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

	
	pcie->userWriteWord(24, 0); // dram write start off

	//uint32_t istripe = (1024*1024*256/16)/64;
	//uint32_t bufferwords = (1024*1024*256)/64; // 256MB scratchpad
	uint32_t buffermb = 256;
	uint32_t outstripemb = 1;
	uint32_t bufferwords = (1024*1024*buffermb)/64; // 256MB scratchpad
	uint32_t istripe = (1024*1024*outstripemb)/16/64; // each output stripe adding up to ...
	uint32_t stripecnt = buffermb/outstripemb;

	pcie->userWriteWord(0, bufferwords); // output stripe offset
	pcie->userWriteWord(4, bufferwords*2); // output stripe limit
	pcie->userWriteWord(16, istripe*16); // output stripe words

	for ( int b = 0; b < 16; b++ ) {
		printf( "Writing buffer %d\n",b ); fflush(stdout);
		uint32_t kvcnt = istripe*8; // 8 kvpairs per DRAM word
		for ( int s = 0; s < bufferwords/16/istripe; s++ ) {
			uint32_t* buffer = (uint32_t*)malloc(kvcnt*sizeof(uint32_t)); 
			for ( int i = 0; i < kvcnt; i++ ){
				//buffer[i] = rand() % (1<<24);
				buffer[i] = rand() % (1<<24);
			}
			//std::sort(buffer, buffer+kvcnt);
			buffer[kvcnt/2] = 0xffffffff;

			for ( int i = 0; i < kvcnt; i++ ){
				if ( buffer[i] == 0xffffffff ) {
					pcie->userWriteWord(20, 0xffffffff);
					pcie->userWriteWord(20, buffer[i]);
				} else {
					pcie->userWriteWord(20, 1);
					pcie->userWriteWord(20, buffer[i]);
				}
			}
			free(buffer);
		}
	}
	
	for ( int b = 0; b < 16; b++ ) {
		pcie->userWriteWord(0, b);
		pcie->userWriteWord(4, (bufferwords/16)*b);
		pcie->userWriteWord(8, (bufferwords/16)*(b+1));
		pcie->userWriteWord(12, istripe);
	}

	

	//sleep(5);
	uint32_t donestripes = 0;
	uint32_t elapsed = 0;
	while (donestripes < stripecnt ) {
		uint32_t gdonestripes = pcie->userReadWord(4);
		while (elapsed == 0 || gdonestripes <= donestripes) {
			elapsed = pcie->userReadWord(0);
			gdonestripes = pcie->userReadWord(4);
		}
		donestripes = gdonestripes;
		printf( "elapsed: %d cycles (%lf s) for %d\n", elapsed, ((double)elapsed)/250000000.0, donestripes );
	}

}
