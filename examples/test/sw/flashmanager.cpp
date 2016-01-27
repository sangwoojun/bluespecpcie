#include <stdio.h>
#include <unistd.h>

#include "flashmanager.h"

FlashManager*
FlashManager::m_pInstance = NULL;

FlashManager*
FlashManager::getInstance() {
	if ( m_pInstance == NULL ) m_pInstance = new FlashManager();

	return m_pInstance;
}

void* flashManagerThread(void* arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	void* dmabuffer = pcie->dmaBuffer();
	unsigned int* ubuf = (unsigned int*)dmabuffer;

	FlashManager* flash = FlashManager::getInstance();

	while(1) {
		pcie->waitInterrupt();
		for ( int i = 0; i < 32; i++ ) {
			printf( " %x", ubuf[i] );
			if ( i % 4 == 3 ) printf( "\n");
		}
	}
	while(1) {
		usleep(1000);
		uint32_t stat = pcie->readWord(1024*4);
		if ( (stat>>24) > 0 ) {
			uint8_t type = (0xff & (stat>>16));
			uint16_t val = (0xffff & stat);

			switch ( type ) {
				case 0: printf( "read done\n" ); break;
				case 1: printf( "write done\n" ); break;
				case 2: printf( "erase done!\n" ); break;
				case 3: printf( "erase failed!\n" ); break;
				case 4: {
					printf( "write ready\n" );
					
					uint32_t* b = (uint32_t*)flash->storebuffer;
					for ( int i = 0; i < (8192+32)/4; i++ ) {
						int idx = i % 4;
						pcie->writeWord((1024+4+idx)*4, i);
						//printf( "Writing %x\n", b[i] );
					}
					printf( "written\n" );
					break;
				}
			}
		}
	}
}

FlashManager::FlashManager() {
	pthread_create(&flashThread, NULL, flashManagerThread, NULL);
	
}

/*
0: op
1: blockpagetag
2: buschip
*/
void FlashManager::eraseBlock(int bus, int chip, int block) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	int page = 0;
	int tag = 0;
	uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	uint32_t buschip = (bus<<8) | chip;
	pcie->writeWord((1024+2)*4, buschip);
	pcie->writeWord((1024+1)*4, blockpagetag);
	pcie->writeWord(1024*4, 0); // triggers erase

}
void FlashManager::writePage(int bus, int chip, int block, int page, void* buffer) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	int tag = 0;
	uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	uint32_t buschip = (bus<<8) | chip;
	pcie->writeWord((1024+2)*4, buschip);
	pcie->writeWord((1024+1)*4, blockpagetag);
	pcie->writeWord(1024*4, 2); // triggers write
	this->storebuffer = buffer;
}
void FlashManager::readPage(int bus, int chip, int block, int page, void* buffer) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	int tag = 0;
	uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	uint32_t buschip = (bus<<8) | chip;
	pcie->writeWord((1024+2)*4, buschip);
	pcie->writeWord((1024+1)*4, blockpagetag);
	pcie->writeWord(1024*4, 1); // triggers read
	this->storebuffer = buffer;

}
