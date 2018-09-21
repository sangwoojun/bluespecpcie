#include <stdio.h>
#include <stdlib.h>

#include <pthread.h>

#include "ShmFifo.h"

#ifndef __BDBM_PCIE__H__
#define __BDBM_PCIE__H__

#define DMA_BUFFER_SIZE (1024*1024*8)
//For BSIM
#define SHM_SIZE ((1024*8*3) + DMA_BUFFER_SIZE)
#define IO_QUEUE_SIZE 4096
#define CONFIG_BUFFER_SIZE (1024*16)
#define CONFIG_BUFFER_ISIZE (CONFIG_BUFFER_SIZE/4)

void* bdbmPollThread(void* arg);

class BdbmPcie {
public:
	static BdbmPcie* getInstance();

	inline void writeWord(unsigned int addr, unsigned int data) {
	#ifdef BLUESIM
		uint64_t d1 = 1;
		d1 <<= (32+24);
		uint64_t d2 = addr;
		d2 <<= (32);
		uint64_t d = ((uint64_t)data) | d1 | d2;
		while ( outfifo->full() ) {usleep(1000);}
		
		outfifo->push(d);
	#else

		//pthread_mutex_lock(&write_lock);
		unsigned int* ummd = (unsigned int*)this->mmap_io;
		if ( io_wbudget > 0 ) {
			io_wbudget--;

			ummd[(addr>>2)] = data;
			//pthread_mutex_unlock(&write_lock);
			return;
		}
		unsigned int io_wemit = ummd[CONFIG_BUFFER_ISIZE-1];

		int waitcount = 0;
		while ( io_wreq - io_wemit >= IO_QUEUE_SIZE/2 ) {
			//usleep(50);
			io_wemit = ummd[CONFIG_BUFFER_ISIZE-1];

			if ( waitcount <= 1024*1024*128) {
				waitcount ++;
			} else {
				printf( "\t!! writeWord waiting... %d %d %d\n", io_wbudget, io_wreq, io_wemit );
				waitcount = 0;
			}
		}
		
		this->io_wbudget = IO_QUEUE_SIZE - ( io_wreq - io_wemit);
		this->io_wreq += IO_QUEUE_SIZE - ( io_wreq - io_wemit)+1;

		ummd[(addr>>2)] = data;
		//pthread_mutex_unlock(&write_lock);
	#endif
	};
	uint32_t readWord(unsigned int addr);
	
	inline void userWriteWord(unsigned int addr, unsigned int data) {
		this->writeWord(addr+CONFIG_BUFFER_SIZE, data);
	};
	uint32_t userReadWord(unsigned int addr);

	void waitInterrupt(int timeout);
	void waitInterrupt();
	void* dmaBuffer();

	void Ioctl(unsigned int cmd, unsigned long arg);
	
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
