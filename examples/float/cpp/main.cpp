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

float fixed_to_float_2i(uint32_t fixed) {
	fixed = (fixed&((1<<16)-1));
	// 16 bits, 2 bits integer
	bool sign = (fixed>>15);

	float ret = 0;
	if ( sign ) {
		uint32_t fixedneg = ((~fixed)+1)&((1<<16)-1);
		//uint32_t fixedneg = (~fixed)+1;
		ret = -((float)fixedneg)/(1<<14);
	}
	else {
		ret = ((float)fixed)/(1<<14);
	}

	return ret;
}

uint32_t float_to_fixed_3i(float radian) {
	// 16 bits, 3 bits integer
	uint32_t integer_portion = (uint32_t)radian;
	uint32_t frac_portion = (uint32_t)((radian - integer_portion) * (1<<13));
	uint32_t fixed = (integer_portion<<13)|frac_portion;

	return fixed;
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

	float radian = 4.71238898; // 180 + 90 degrees
	pcie->userWriteWord(16, float_to_fixed_3i(radian));



	sleep(1);

	uint64_t a1 = pcie->userReadWord(0);
	uint64_t a2 = pcie->userReadWord(4);
	uint64_t ar = (a2<<32)|a1;
	uint64_t b1 = pcie->userReadWord(8);
	uint64_t b2 = pcie->userReadWord(12);
	uint64_t br = (b2<<32)|b1;

	printf( "%f %f\n", *(double*)&ar, *(double*)&br );

	uint32_t sincos = pcie->userReadWord(16);
	uint32_t cos = (sincos&0xffff);
	uint32_t sin = ((sincos>>16)&0xffff);
	printf( "sin: %f cos: %f\n", fixed_to_float_2i(sin), fixed_to_float_2i(cos) );

	for ( int i = 0; i < 6; i++ ) {
		pcie->userWriteWord(16, float_to_fixed_3i((3.14159/180)*30*i));

		usleep(10000);

		uint32_t sincos = pcie->userReadWord(16);
		uint32_t cos = (sincos&0xffff);
		uint32_t sin = ((sincos>>16)&0xffff);
		printf( "%d sin: %f cos: %f\n", i, fixed_to_float_2i(sin), fixed_to_float_2i(cos) );
	}

	exit(0);
}
