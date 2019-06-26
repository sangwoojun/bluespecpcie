#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stddef.h>

#include <errno.h>

#include <fcntl.h>
#include <sys/shm.h>
#include <sys/stat.h>
#include <sys/mman.h>

#include "ShmFifo.h"

#define DMA_BUFFER_SIZE (1024*1024*4)
#define SHM_SIZE (1024*8*3 + DMA_BUFFER_SIZE)

ShmFifo* infifo = NULL;
ShmFifo* outfifo = NULL;
ShmFifo* interruptfifo = NULL;
void* shm_ptr = NULL;
bool shm_ready = false;
bool shmReady() {
	if ( shm_ready == true ) {
		return true;
	}
	
	pid_t mypid = getpid();
	char shmname[64];
	sprintf(shmname, "/bdbm%d", mypid);

	int shm_fd = shm_open(shmname, O_CREAT | O_RDWR, 0666);
	printf( "hardware shm_open %s returned %d with errno %d\n", shmname, shm_fd, errno);
	int ret = ftruncate(shm_fd, SHM_SIZE);
	shm_ptr = mmap(0,SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
	if ( shm_ptr == MAP_FAILED || shm_ptr == NULL ) 
	{
		shm_ptr = NULL;
		shm_ready = false;
		return false;
	}
	shm_ready = true;
	//printf( "shmReady Called %x\n", (unsigned int)shm_ptr ); fflush(stdout);

	uint64_t* shm_uptr = (uint64_t*)shm_ptr;
	outfifo = new ShmFifo(shm_uptr+(DMA_BUFFER_SIZE/sizeof(uint64_t)), 1024);
	infifo = new ShmFifo(shm_uptr+(DMA_BUFFER_SIZE/sizeof(uint64_t))+1024, 1024);
	interruptfifo = new ShmFifo(shm_uptr+(DMA_BUFFER_SIZE/sizeof(uint64_t))+(1024*2), 1024);
	
	return true;
}

extern "C" bool bdpiDmaWriteData(unsigned int addr, uint64_t data1, uint64_t data2) {
	//TODO.....
	if ( !shmReady() ) return false;

	uint64_t *llptr = (uint64_t*)shm_ptr;
	
	llptr[addr>>3] = data1;
	llptr[(addr>>3)+1] = data2;

	return true;
}

unsigned int dmaReadStartAddr;
unsigned int dmaReadWordsRemain;
unsigned int dmaReadWordsOffset;
extern "C" bool bdpiDmaReadReq(unsigned int addr, int words) {
	if ( !shmReady() ) return false;

	dmaReadStartAddr = addr;
	dmaReadWordsRemain = words*4; // 128 bit words, instead of 32
	dmaReadWordsOffset = 0;
	return true;
}

extern "C" bool bdpiDmaReadReady() {
	if ( !shmReady() ) return false;

	if ( dmaReadWordsRemain > 0 ) return true;

	return false;
}

extern "C" uint32_t bdpiDmaReadData() {
	uint32_t *lptr = (uint32_t *)shm_ptr;
	//printf( "%d %d %x\n", dmaReadStartAddr>>2, dmaReadWordsOffset, );
	uint32_t r = lptr[(dmaReadStartAddr>>2)+dmaReadWordsOffset];
	dmaReadWordsRemain --;
	dmaReadWordsOffset++;
	return r;
}

extern "C" bool bdpiIOReady() {
	if ( !shmReady() ) return false;
	if ( infifo->empty() ) return false;

	printf( "bdpiIOReady returning true!\n" );
	return true;
}

extern "C" uint64_t bdpiIOData() {
	if ( !shmReady() ) {
		uint64_t r = 1;
		r <<= (32+31);
		return r;
	}
	if ( infifo->empty() ) {
		//fprintf(stderr, "bdpiIOData called while infifo is empty!\n" );
		uint64_t r = 1;
		r <<= (32+31);
		return r;
	}

	uint64_t d = infifo->tail();
	infifo->pop();

	//printf("returning data %lx\n", d );
	return d;
}

extern "C" bool bdpiIOReadRespReady() {
	if ( !shmReady() ) return false;
	if ( outfifo->full() ) return false;

	return true;
}

extern "C" bool bdpiIOReadResp(uint64_t dat) {
	if ( !shmReady() ) return false;
	if ( outfifo->full() ) return false; //THIS SHOULD NOT HAPPEN

	outfifo->push(dat);

	return true;
}

extern "C" bool bdpiInterruptReady() {
	if ( !shmReady() ) return false;
	if ( interruptfifo->full() ) return false;

	return true;
}
extern "C" void bdpiAssertInterrupt() {
	if ( !shmReady() ) return;//THIS SHOULD NOT HAPPEN
	if ( interruptfifo->full() ) return; //THIS SHOULD NOT HAPPEN

	interruptfifo->push(0);
}




