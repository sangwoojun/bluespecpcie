#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <stddef.h>

#include <errno.h>

#include <fcntl.h>
#include <time.h>

#include <sys/shm.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/poll.h>


#include "bdbmpcie.h"


void interruptHandler() {
	printf( "Interrupted!\n" );
}

void* bdbmPollThread(void* arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	while (1) {
		pcie->waitInterrupt();
		interruptHandler();
	}
}

void* pciePollthread(void *arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	/*
	int bdbmregsfd = pcie->reg_fd;

	struct pollfd pfd;
	pfd.fd = bdbmregsfd;
	pfd.events = POLLIN;
	*/
	while (1) {
		//poll(&pfd, 1, -1);
		pcie->waitInterrupt();

		interruptHandler();
	}
}

BdbmPcie*
BdbmPcie::m_pInstance = NULL;

BdbmPcie*
BdbmPcie::getInstance() {
	if (m_pInstance == NULL) {
		//printf( "Initializing BdbmPcie\n" ); fflush(stdout);
		m_pInstance = new BdbmPcie();
	}

	return m_pInstance;
}

void
BdbmPcie::Init_Bluesim() {
	this->bsim = true;

	char* sserverPid = getenv("BDBM_BSIM_PID");
	if ( sserverPid == NULL && bsim ) {
		fprintf(stderr, "bsim PCIe interface initialized without providing server pid via BDBM_BSIM_PID!!\n" );
		return;
	}

	int serverPid = atoi(sserverPid);
	
	char shmname[64];
	sprintf(shmname, "/bdbm%d", serverPid);
	
	int shm_fd = shm_open(shmname, O_RDWR, 0666);
	printf( "software shm_open %s returned %d with errno %d\n", shmname, shm_fd, errno);
	fflush(stdout);
	
	int ret = ftruncate(shm_fd, SHM_SIZE);
	shm_ptr = mmap(0,SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
	if ( shm_ptr == MAP_FAILED || shm_ptr == NULL ) {
		fprintf(stderr, "bsim PCIe interface init mmap failed\n");
		return;
	}
	
	uint64_t* shm_uptr = (uint64_t*)shm_ptr;
	//in/out reversed compared to server
	infifo = new ShmFifo(shm_uptr+(DMA_BUFFER_SIZE/sizeof(uint64_t)), 1024);
	outfifo = new ShmFifo(shm_uptr+(DMA_BUFFER_SIZE/sizeof(uint64_t))+1024, 1024);
	interruptfifo = new ShmFifo(shm_uptr+(DMA_BUFFER_SIZE/sizeof(uint64_t))+(1024*2), 1024);

	//pthread_create(&pollThread, NULL, bdbmPollThread, NULL);
	printf( "bsim PCIe interface init done!\n" );
	fflush(stdout);
}

void
BdbmPcie::Init_Pcie() {
	this->bsim = false;

	int fd = open("/dev/bdbm_regs0", O_RDWR, 0);
	void* mmd = mmap(NULL, BAR0_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	void* mmdbuf = mmap(NULL, DMA_BUFFER_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, BAR0_SIZE);

	unsigned int* ummd = (unsigned int*)mmd;
	/*
	unsigned int* ummdb = (unsigned int*)mmdbuf;
	*/
	this->mmap_io = mmd;
	this->mmap_dma = mmdbuf;
	this->reg_fd = fd;

	printf( "PCIe device opened\n" ); fflush(stdout);

	// This resets the remit,wemit registers in the server
	ummd[0] = 0; // Init
	
	printf( "PCIe device init called\n" ); fflush(stdout);

	this->io_wreq = 0;
	this->io_rreq = 0;
	this->io_wbudget = 0;
	this->io_rbudget = 0;

	//pthread_create(&pollThread, NULL, bdbmPollThread, NULL);
}

BdbmPcie::BdbmPcie() {
	pthread_mutex_init(&write_lock, NULL);
	pthread_mutex_init(&read_lock, NULL);
	//pthread_cond_init(&pcie_cond, NULL);
#ifdef BLUESIM
	this->Init_Bluesim();
#else
	this->Init_Pcie();
#endif
}

void
BdbmPcie::userWriteWord(unsigned int addr, unsigned int data) {
	this->writeWord(addr+CONFIG_BUFFER_SIZE, data);
}
inline void
BdbmPcie::writeWord(unsigned int addr, unsigned int data) {
#ifdef BLUESIM
	uint64_t d1 = 1;
	d1 <<= (32+24);
	uint64_t d2 = addr;
	d2 <<= (32);
	uint64_t d = ((uint64_t)data) | d1 | d2;
	while ( outfifo->full() ) {usleep(1000);}
	
	outfifo->push(d);
#else

	pthread_mutex_lock(&write_lock);
	unsigned int* ummd = (unsigned int*)this->mmap_io;
	if ( io_wbudget > 0 ) {
		io_wbudget--;

		ummd[(addr>>2)] = data;
		pthread_mutex_unlock(&write_lock);
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
	pthread_mutex_unlock(&write_lock);
#endif
}

uint32_t
BdbmPcie::userReadWord(unsigned int addr) {
	return this->readWord(addr+CONFIG_BUFFER_SIZE);
}

uint32_t
BdbmPcie::readWord(unsigned int addr) {
#ifdef BLUESIM
	uint64_t d2 = addr;
	d2 <<= (32);
	uint64_t d = d2;
	while ( outfifo->full() ) {usleep(1000);}
	
	outfifo->push(d);

	while ( infifo->empty() ) {usleep(1000);}
	uint64_t data = infifo->tail();
	infifo->pop();

	uint32_t rd = data;
	return rd;
#else
	pthread_mutex_lock(&read_lock);
	unsigned int* ummd = (unsigned int*)this->mmap_io;

	//TODO lock?
	if ( io_rbudget > 0 ) {
		io_rreq = (0xffff & (io_rreq + 1));
		io_rbudget--;

		unsigned int data = ummd[(addr>>2)];
		pthread_mutex_unlock(&read_lock);
		return data;
	}

	unsigned int io_remit = ummd[CONFIG_BUFFER_ISIZE-2];
	io_remit = (io_remit & 0xffff);
	unsigned int iob = io_rreq;
	if ( io_remit > iob ) {
		iob += 0x10000;
	}

	while ( iob >= io_remit + IO_QUEUE_SIZE ) {
		usleep(100);
		io_remit = (ummd[CONFIG_BUFFER_ISIZE-2] & 0xffff);
	}

	this->io_rbudget = io_remit + IO_QUEUE_SIZE - iob;

	unsigned int data = ummd[(addr>>2)];
	io_rreq = (0xffff & (io_rreq + 1));
	pthread_mutex_unlock(&read_lock);
	return data;
#endif
}

void
BdbmPcie::waitInterrupt() {
	this->waitInterrupt(-1);
}

void
BdbmPcie::waitInterrupt(int timeout) {
#ifdef BLUESIM

	//while ( interruptfifo->empty() ) {usleep(1000);}
	//FIXME!
	
	while ( !interruptfifo->empty() ) {
		interruptfifo->pop();
	}

	return;
#else
	int bdbmregsfd = this->reg_fd;

	struct pollfd pfd;
	pfd.fd = bdbmregsfd;
	pfd.events = POLLIN;

	poll(&pfd, 1, timeout);

	return;
#endif
}

void*
BdbmPcie::dmaBuffer() {
#ifdef BLUESIM
return shm_ptr;
#else
return mmap_dma;
#endif
}


void 
BdbmPcie::Ioctl(unsigned int cmd, unsigned long arg) {
#ifdef BLUESIM
#else
	int res = ioctl(this->reg_fd, cmd, arg);
#endif
}
