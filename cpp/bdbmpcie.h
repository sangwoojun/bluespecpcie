#include <stdio.h>
#include <stdlib.h>

#include <pthread.h>

#include "ShmFifo.h"

#ifndef __BDBM_PCIE__H__
#define __BDBM_PCIE__H__

#define DMA_BUFFER_SIZE (1024*1024*4)
#define BAR0_SIZE (1024*1024)
//For BSIM
#define SHM_SIZE ((1024*8*3) + DMA_BUFFER_SIZE)
#define IO_QUEUE_SIZE 512
#define CONFIG_BUFFER_SIZE (1024*16)
#define CONFIG_BUFFER_ISIZE (CONFIG_BUFFER_SIZE/4)

void* bdbmPollThread(void* arg);

class BdbmPcie {
public:
	static BdbmPcie* getInstance();

	void writeWord(unsigned int addr, unsigned int data);
	uint32_t readWord(unsigned int addr);
	
	void userWriteWord(unsigned int addr, unsigned int data);
	uint32_t userReadWord(unsigned int addr);

	void waitInterrupt(int timeout);
	void waitInterrupt();
	void* dmaBuffer();

	void Ioctl(unsigned int cmd, unsigned long arg);
	
private:
	BdbmPcie();
	void Init_Bluesim();
	void Init_Pcie();

	BdbmPcie(BdbmPcie const&) = delete;
	BdbmPcie& operator=(BdbmPcie const&) = delete;

	bool bsim;


	pthread_t pollThread;

	static BdbmPcie* m_pInstance;

//#ifdef BLUESIM
	void* shm_ptr;

	uint32_t io_wreq;
	uint32_t io_rreq;
	uint32_t io_wbudget;
	uint32_t io_rbudget;

	ShmFifo* infifo;
	ShmFifo* outfifo;
	ShmFifo* interruptfifo;
//#else
	void* mmap_dma;
	void* mmap_io;
	int reg_fd;
//#endif

	pthread_mutex_t write_lock;
	pthread_mutex_t read_lock;

	//pthread_cond_t pcie_cond;
};


#endif
