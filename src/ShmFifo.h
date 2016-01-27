#ifndef __SHM_FIFO__H__
#define __SHM_FIFO__H__

#include <stdint.h>

class ShmFifo{
public:
	ShmFifo(uint64_t* mem, int size);
	void pop();
	void push(uint64_t v);

	uint64_t tail();
	bool empty();
	bool full();

	
private:
	uint64_t* mem;
	uint64_t size;

	uint64_t* headidx;
	uint64_t* tailidx;
};


#endif
