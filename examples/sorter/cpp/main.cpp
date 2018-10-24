#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

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

	uint32_t cur_write_buf_idx = 128;
	for ( int i = 0; i < 4; i++ ) {
		pcie->userWriteWord(1*4,cur_write_buf_idx);
		cur_write_buf_idx++;
	}


	int buffercnt[32] = {0};
	uint32_t* dmabuf = (uint32_t*)pcie->dmaBuffer();
	for ( int idx = 0; idx < 32; idx++ ) {
		uint32_t* idxd = dmabuf + (2048*idx);
		for ( int i = 0; i < 2048; i++ ) idxd[i] = 0;
		for ( int i = 0; i < 340; i++ ) {
			uint64_t* u = ((uint64_t*)(idxd+(i*3)));
			*((uint64_t*)(idxd+(i*3))) = (uint64_t)i*(idx+1);
			*(idxd+(i*3+2)) = 1;
		}
		for ( int i = 340*3; i < 2048; i++ ) {
			idxd[i] = 0xffffffff;
		}
	}

	for ( int idx = 0; idx < 32; idx++ ) {
		uint32_t cmd = (idx<<16)|(idx*2);
		pcie->userWriteWord(0,cmd);
		buffercnt[idx] ++;
	}
	/*
	for ( int idx = 0; idx < 16; idx++ ) {
		uint32_t cmd = (idx<<16)|(idx*2+1);
		pcie->userWriteWord(0,cmd);
	}*/
	/*
	for ( int idx = 0; idx < 16; idx++ ) {
		pcie->userWriteWord(0,(idx<<16)|0xffff);
	}
	*/

	printf("Buffers sent\n");

	while(true) {
		uint32_t done = pcie->userReadWord(0);
		while ( done != 0xffffffff ) {
			printf( "Done signal from %d\n", done );

			if ( buffercnt[done] == 1 ) {
				uint32_t cmd = (done<<16)|(done*2+1);
				pcie->userWriteWord(0,cmd);
				buffercnt[done] ++;
			} else if ( buffercnt[done] ==2 ) {
				pcie->userWriteWord(0,(done<<16)|0xffff);
				buffercnt[done] ++;
			} else if ( buffercnt[done] == 3){
			} else {
				printf( "ANOTHER done signal from %d\n", done );
			}


			done = pcie->userReadWord(0);
		}
		uint32_t res0 = pcie->userReadWord(32*4);
		uint32_t res1 = pcie->userReadWord(33*4);
		uint32_t res2 = pcie->userReadWord(34*4);
		while ( res0 != 0xffffffff || res1 != 0xffffffff || res2 != 0xffffffff ) {
			
			printf( "Sort result %x - %x : %d\n", res0, res1, res2 );

			res0 = pcie->userReadWord(32*4);
			res1 = pcie->userReadWord(33*4);
			res2 = pcie->userReadWord(34*4);
		}

		uint32_t donew = pcie->userReadWord(1*4);
		while (donew != 0xffffffff) {
			uint32_t idx = (donew>>16);
			uint32_t bytes = (donew & 0xffff);
			printf( "Write buffer done! %d 0x%x\n", idx, bytes );
			uint32_t* wbuf = (dmabuf+(idx<<10));
			for ( int i = 0; i < 8; i++ ) {
				printf( "%x ", wbuf[i] );
			}
			printf( "\n" );

			pcie->userWriteWord(1*4,cur_write_buf_idx++);
			if ( cur_write_buf_idx >= 256 ) cur_write_buf_idx = 128;

			donew = pcie->userReadWord(1*4);
		}
		sleep(1);
		printf( "--\n" );
		fflush(stdout);
	}




}
