#include "dmacircularqueue.h"

DMACircularQueue*
DMACircularQueue::m_pInstance = NULL;

DMACircularQueue*
DMACircularQueue::getInstance() {
	if ( m_pInstance == NULL ) {
		m_pInstance = new DMACircularQueue();
	}
	return m_pInstance;
}

DMACircularQueue::DMACircularQueue() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuf = pcie->dmaBuffer();
	uint32_t* ubuf = (uint32_t*)dmabuf;
	readBytes = 0;
	pcie->userWriteWord(16*4, 0); //start
}
void 
DMACircularQueue::deq(uint32_t bytes) {
	readBytes += bytes;
	BdbmPcie* pcie = BdbmPcie::getInstance();
	pcie->userWriteWord(17*4, readBytes);
}

void*
DMACircularQueue::dmaBuffer() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	return pcie->dmaBuffer();
}
