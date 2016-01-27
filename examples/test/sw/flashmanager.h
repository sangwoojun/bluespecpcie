#include "bdbmpcie.h"

#ifndef __FLASHMANAGER__H__
#define __FLASHMANAGER__H__
class FlashManager {
public:
FlashManager();
void eraseBlock(int bus, int chip, int block);
void writePage(int bus, int chip, int block, int page, void* buffer);
void readPage(int bus, int chip, int block, int page, void* buffer);

	static FlashManager* getInstance();

private:
	pthread_t flashThread;
	static FlashManager* m_pInstance;

public:
	//FIXME use dma Buffer instead
	void* storebuffer;
};
#endif

