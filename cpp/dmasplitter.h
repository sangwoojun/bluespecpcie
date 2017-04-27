#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <pthread.h>

#include <list>
#include <string.h>

#include "bdbmpcie.h"

#define IO_USER_OFFSET 4096

#ifndef __DMA_SPLITTER__H__
#define __DMA_SPLITTER__H__

void* dmaSplitterThread(void* arg);

typedef struct PCIeWord {
	uint32_t d[4];
	uint32_t header;
} PCIeWord;

class DMASplitter {
public:
	static DMASplitter* getInstance();

	//sends 16 bytes (128 bits)
	void sendWord(uint32_t header, uint32_t d1, uint32_t d2, uint32_t d3, uint32_t d4);
	void sendWord(uint32_t header, uint32_t d1, uint32_t d2);
	void sendWord(PCIeWord word);
	PCIeWord recvWord();
	
	int scanReceive();

	void* dmaBuffer();

private:
	static DMASplitter* m_pInstance;
	DMASplitter();
	DMASplitter(DMASplitter const&){};
	DMASplitter& operator=(DMASplitter const&){};

	//int nextrecvoff;
	int nextrecvidx;
	uint32_t nextrecvoff;
	std::list<PCIeWord> recvList;
	pthread_mutex_t recv_lock;
	pthread_cond_t recv_cond;
	
	pthread_t pollThread;
};

#endif

