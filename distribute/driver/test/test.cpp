#include <sys/mman.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>

#include <sys/poll.h>

#include <pthread.h>

#define MAGIC 0xc001d001

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

int fd;
void* pollthread(void *arg) {
	struct pollfd pfd;
	pfd.fd = fd;
	pfd.events = POLLIN;
	while (1) {
		printf( "Waiting for poll\n" );
		poll(&pfd, 1, -1);
		printf( "Poll returned!\n" );
	}
}

int main() {
	fd = open("/dev/bdbm_regs0", O_RDWR, 0);
	void* mmd = mmap(NULL, 1024*1024, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	void* mmdbuf = mmap(NULL, 1024*1024, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 1024*1024);
	unsigned int* ummd = (unsigned int*)mmd;
	unsigned int* ummdb = (unsigned int*)mmdbuf;
	timespec start,end;

	unsigned int magic = ummd[0];
	printf( "Magic number: %x ?= %x\n", magic, MAGIC );

	unsigned int ioctl_alloc_dma = ummd[1];

	pthread_t pollthreadval;
	pthread_create(&pollthreadval, NULL, pollthread, NULL);

	clock_gettime(CLOCK_REALTIME, &start);
	/*
	for ( int i = 0; i < 1024*1024/4*128; i++ ) {
		//unsigned int d = ummd[i%(1024*1024/4)];
		//printf( "%d: %x\n", i, ummd[i] );
		if ( i % 2048 == 0 ) printf( "%d: %x\n", i, ummd[i%128] );
	}
	*/
	for ( int i = 0; i < 32; i++ ) {
		//unsigned int d = ummd[i%(1024*1024/4)];
		printf( "%d: %x\n", i, ummd[i] );
	}
	//printf( "%d: %x\n", 1024*4, ummd[1024*4] );

	//test dma write?
	ummd[1024] = 8;

	sleep(2);
	ummd[1024+1] = 1;

	sleep(2);
	ummd[1024+2] = 8; // test dma read
	
	// NOT ACTUALLY ALLOCING NOW
	//ioctl(fd, ioctl_alloc_dma, 32);
	//printf( "IOCTL command no: %x\n", ioctl_alloc_dma );
	
	for ( int i = 0; i < 128; i++ ) {
		printf( "%x ", ummdb[i] );
	}
	printf( "\n" );

	sleep(2);

	clock_gettime(CLOCK_REALTIME, &end);
	float totallat = timespec_diff_sec(start, end);
	printf( "%f\n", totallat );
	munmap(mmd, 1024*1024);
	munmap(mmdbuf, 1024*1024);
	close(fd);
}
