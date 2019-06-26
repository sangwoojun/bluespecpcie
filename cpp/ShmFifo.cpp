#include <stdio.h>
#include "ShmFifo.h"

/*
thread safety is not enforced, because it's going to be used for shmem
MAKE SURE THERE IS ONLY ONE SOURCE AND ONE DRAIN!
*/

ShmFifo::ShmFifo(uint64_t* mem_, int size) {
	this->mem = mem_+3;
	this->size = (uint64_t)size-3;

	headidx = &mem_[0];
	tailidx = &mem_[1];

	// Check magic number so that only one host inits 
	if ( mem_[2] != 0xc001d00d ) {
		*headidx = 0;
		*tailidx = 0;
		printf( "Initializing shared memory fifo structures\n" );
		mem_[2] = 0xc001d00d;
	}
}

void
ShmFifo::pop() {
	if ( *tailidx == *headidx ) return;

	//printf( "Popped data from %ld\n", *tailidx );

	(*tailidx)++;
	if (*tailidx >= this->size ) *tailidx = 0;


	return;
}

void
ShmFifo::push(uint64_t v) {
	uint64_t nexthead = *headidx + 1;
	if ( nexthead >= this->size ) nexthead = 0;
	if ( nexthead == *tailidx ) return;

	mem[*headidx] = v;
	(*headidx) = nexthead;

	//printf( "Pushed %lx to idx %ld\n", v, *headidx-1 );
	//fflush(stdout);

	return;
}

uint64_t
ShmFifo::tail() {
	return mem[*tailidx];
}

bool
ShmFifo::empty() {
	if ( *tailidx == *headidx ) return true;
	return false;
}

bool
ShmFifo::full() {
	uint64_t nexthead = *headidx + 1;
	if ( nexthead >= this->size ) nexthead = 0;
	if ( nexthead == *tailidx ) return true;

	return false;
}


/*
void shmfifo_init(unsigned int* mem, int size);
bool shmfifo_push(int v);
unsigned int shmfifo_tail();
bool shmfifo_pop();
bool shmfifo_empty();
bool shmfifo_full();

unsigned int* shmfifo_mem = NULL;
int shmfifo_size = 0;
int shmfifo_headidx = 0;
int shmfifo_tailidx = 0;

void shmfifo_init(unsigned int* mem, int size) {
	shmfifo_mem = mem;
	if ( size > 0 ) shmfifo_size = size;
}

bool shmfifo_push(int v) {
	int nexthead = shmfifo_headidx + 1;
	if ( nexthead >= shmfifo_size ) nexthead = 0;
	if ( nexthead == shmfifo_tailidx ) return false;

	shmfifo_mem[shmfifo_headidx] = v;
	shmfifo_headidx++;

	return true;
}

unsigned int shmfifo_tail() {
	return shmfifo_mem[shmfifo_tailidx];
}

bool shmfifo_pop() {
	if ( shmfifo_tailidx == shmfifo_headidx ) return false;

	shmfifo_tailidx++;
	if (shmfifo_tailidx >= shmfifo_size ) shmfifo_tailidx = 0;

	return true;
}

bool shmfifo_empty() {
	if ( shmfifo_tailidx == shmfifo_headidx ) return true;
	return false;
}

bool shmfifo_full() {
	int nexthead = shmfifo_headidx + 1;
	if ( nexthead >= shmfifo_size ) nexthead = 0;
	if ( nexthead == shmfifo_tailidx ) return true;

	return false;
}
*/
