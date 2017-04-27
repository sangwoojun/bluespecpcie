#include "dmasplitter.h"

DMASplitter*
DMASplitter::m_pInstance = NULL;

DMASplitter*
DMASplitter::getInstance() {
	if (m_pInstance == NULL) {
		printf( "Initializing DMASplitter\n" ); fflush(stdout);
		m_pInstance = new DMASplitter();
	}

	return m_pInstance;
}

DMASplitter::DMASplitter() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuf = pcie->dmaBuffer();
	uint32_t* ubuf = (uint32_t*)dmabuf;

	bool found = false;
	for ( int i = 0; i < (1024*4/sizeof(uint32_t)); i++ ) {
		ubuf[i] = 0xffffffff;
	}

	//nextrecvoff = 0;
	nextrecvidx = 0;
	nextrecvoff = 0;

	pthread_mutex_init(&recv_lock, NULL);
	pthread_cond_init(&recv_cond, NULL);

	//init enqReceiveIdx
	pcie->writeWord((IO_USER_OFFSET+16)*4, 0);
	//init enqIdx
	pcie->writeWord((IO_USER_OFFSET+17)*4, 0);
	
	//pthread_create(&pollThread, NULL, dmaSplitterThread, NULL);
}


void 
DMASplitter::sendWord(PCIeWord word) {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	
	pcie->writeWord((IO_USER_OFFSET+4)*4, word.header);
	for ( int i = 3; i >= 0; i-- ) {
		pcie->writeWord((IO_USER_OFFSET+i)*4, word.d[i]);
	}
}

void 
DMASplitter::sendWord(uint32_t header, uint32_t d1, uint32_t d2, uint32_t d3, uint32_t d4) {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	pcie->writeWord((IO_USER_OFFSET+4)*4, header);
	pcie->writeWord((IO_USER_OFFSET+3)*4, d4);
	pcie->writeWord((IO_USER_OFFSET+2)*4, d3);
	pcie->writeWord((IO_USER_OFFSET+1)*4, d2);
	pcie->writeWord((IO_USER_OFFSET+0)*4, d1);
}

void 
DMASplitter::sendWord(uint32_t header, uint32_t d1, uint32_t d2) {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	pcie->writeWord((IO_USER_OFFSET+4)*4, header);
	pcie->writeWord((IO_USER_OFFSET+1)*4, d2);
	pcie->writeWord((IO_USER_OFFSET+0)*4, d1);
}


int
DMASplitter::scanReceive() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuf = pcie->dmaBuffer();
	uint32_t* ubuf = (uint32_t*)dmabuf;

	int recvd = 0;
	bool found = false;
	for ( int i = 0; i < (1024*4/32); i++ ) {
		uint32_t u32off = ((i+nextrecvoff)%(1024*4/32))*4*2;


		uint32_t nidx = ubuf[u32off+5];
		if ( nidx == nextrecvidx ) {
			PCIeWord w;
			w.d[0] = ubuf[u32off];
			w.d[1] = ubuf[u32off+1];
			w.d[2] = ubuf[u32off+2];
			w.d[3] = ubuf[u32off+3];
			w.header = ubuf[u32off+4];
			
			pthread_mutex_lock(&recv_lock);
			recvList.push_front(w);
			pthread_cond_broadcast(&recv_cond);
			pthread_mutex_unlock(&recv_lock);

			nextrecvidx++;
			recvd++;
			found = true;
		} else if ( found ) {
			break;
		}
	}

	nextrecvoff = nextrecvoff+recvd;
	//enqReceiveIdx
	if ( recvd > 0 ) {
		pcie->writeWord((IO_USER_OFFSET+16)*4, nextrecvidx);
	}
	return recvd;
}

PCIeWord
DMASplitter::recvWord() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();

	while ( recvList.empty() ) {
		pcie->waitInterrupt(0);
		dma->scanReceive();
	}
	/*
	pthread_mutex_lock(&recv_lock);
	while ( recvList.empty() ) {
		pthread_cond_wait(&recv_cond, &recv_lock);
	}
	*/
	PCIeWord w = recvList.back();
	recvList.pop_back();
	//pthread_mutex_unlock(&recv_lock);

	return w;
}

void* 
DMASplitter::dmaBuffer() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuf = pcie->dmaBuffer();
	uint8_t* bbuf = (uint8_t*)dmabuf;

	//+1024*4 because of hw->sw queue
	return (void*)(bbuf+(1024*4));
}

void* dmaSplitterThread(void* arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();

	while (1) {
		//pcie->waitInterrupt(0);
		dma->scanReceive();
	}
}
