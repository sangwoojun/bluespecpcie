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

	double a = 0.13;
	double b = 99.15;
	uint64_t av = *(uint64_t*)&a;
	uint64_t bv = *(uint64_t*)&b;

	pcie->userWriteWord(0, (uint32_t)(av));
	pcie->userWriteWord(4, (uint32_t)(av>>32));
	pcie->userWriteWord(8, (uint32_t)(bv));
	pcie->userWriteWord(12, (uint32_t)(bv>>32));

	sleep(1);

	uint64_t a1 = pcie->userReadWord(0);
	uint64_t a2 = pcie->userReadWord(4);
	uint64_t ar = (a2<<32)|a1;
	uint64_t b1 = pcie->userReadWord(8);
	uint64_t b2 = pcie->userReadWord(12);
	uint64_t br = (b2<<32)|b1;

	printf( "%f %f\n", *(double*)&ar, *(double*)&br );

	exit(0);
}
