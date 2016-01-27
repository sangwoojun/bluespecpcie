#include <stdio.h>
#include <stdlib.h>

#include <pthread.h>

#include "ShmFifo.h"

#ifndef __BDBM_PCIE__H__
#define __BDBM_PCIE__H__

void* bdbmPollThread(void* arg);

class BdbmPcie {
public:
	static BdbmPcie* getInstance();

	void writeWord(unsigned int addr, unsigned int data);
	uint32_t readWord(unsigned int addr);

	void waitInterrupt();
	void* dmaBuffer();
	
private:
	BdbmPcie();
	void Init_Bluesim();
	void Init_Pcie();

	BdbmPcie(BdbmPcie const&){};
	BdbmPcie& operator=(BdbmPcie const&){};

	bool bsim;


	pthread_t pollThread;

	static BdbmPcie* m_pInstance;

//#ifdef BLUESIM
	void* shm_ptr;

	unsigned int io_wreq;
	unsigned int io_rreq;
	unsigned int io_wbudget;
	unsigned int io_rbudget;

	ShmFifo* infifo;
	ShmFifo* outfifo;
	ShmFifo* interruptfifo;
//#else
	void* mmap_io;
	void* mmap_dma;
	int reg_fd;
//#endif
};

#endif
