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
	

	pthread_mutex_init(&recv_lock, NULL);
	pthread_cond_init(&recv_cond, NULL);

	//init enqReceiveIdx
	pcie->writeWord((1024+16)*4, 0);
	//init enqIdx
	pcie->writeWord((1024+17)*4, 0);
	
	pthread_create(&pollThread, NULL, dmaSplitterThread, NULL);
}


void 
DMASplitter::sendWord(PCIeWord word) {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	for ( int i = 3; i >= 0; i-- ) {
		pcie->writeWord((1024+i)*4, word.d[i]);
	}
}

void 
DMASplitter::sendWord(uint32_t d1, uint32_t d2, uint32_t d3, uint32_t d4) {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	pcie->writeWord((1024+3)*4, d4);
	pcie->writeWord((1024+2)*4, d3);
	pcie->writeWord((1024+1)*4, d2);
	pcie->writeWord((1024+0)*4, d1);
}

void
DMASplitter::scanReceive() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuf = pcie->dmaBuffer();
	uint32_t* ubuf = (uint32_t*)dmabuf;

	bool found = false;
	for ( int i = 0; i < (1024*4/32); i++ ) {
		int u32off = i*4*2;

		uint32_t nidx = ubuf[u32off];
		if ( nidx == nextrecvidx ) {
			PCIeWord w;
			w.d[0] = ubuf[u32off+4];
			w.d[1] = ubuf[u32off+5];
			w.d[2] = ubuf[u32off+6];
			w.d[3] = ubuf[u32off+7];
			
			pthread_mutex_lock(&recv_lock);
			recvList.push_front(w);
			pthread_cond_broadcast(&recv_cond);
			pthread_mutex_unlock(&recv_lock);

			nextrecvidx++;
			found = true;
		} else if ( found ) {
			break;
		}
		//nextrecvoff = ?
	}

	//enqReceiveIdx
	pcie->writeWord((1024+16)*4, nextrecvidx);
}

PCIeWord
DMASplitter::recvWord() {
	pthread_mutex_lock(&recv_lock);
	while ( recvList.empty() ) {
		pthread_cond_wait(&recv_cond, &recv_lock);
	}
	PCIeWord w = recvList.back();
	recvList.pop_back();
	pthread_mutex_unlock(&recv_lock);

	return w;
}

void* 
DMASplitter::dmaBuffer() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuf = pcie->dmaBuffer();
	uint8_t* bbuf = (uint8_t*)dmabuf;

	return (void*)(bbuf+(1024*4));
}

void* dmaSplitterThread(void* arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();

	while (1) {
		pcie->waitInterrupt(10);
		dma->scanReceive();
	}
}
