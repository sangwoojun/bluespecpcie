#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <pthread.h>

#include <list>
#include <string.h>

#include "bdbmpcie.h"

#define IO_USER_OFFSET 4096

#ifndef __CIRCULAR_QUEUE__H__
#define __CIRCULAR_QUEUE__H__

class DMACircularQueue {
public:
	static DMACircularQueue* getInstance();
	void* dmaBuffer();
	void deq(uint32_t bytes);
private:
	uint32_t readBytes;


	static DMACircularQueue* m_pInstance;
	DMACircularQueue();
	DMACircularQueue(DMACircularQueue const&){};
	DMACircularQueue& operator=(DMACircularQueue const&){};
};

#endif
