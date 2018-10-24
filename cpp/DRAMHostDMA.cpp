/****
For use with dram/src/DRAMHostDMA.bsv
****/



#include "DRAMHostDMA.h"

DRAMHostDMA*
DRAMHostDMA::m_pInstance = NULL;

DRAMHostDMA*
DRAMHostDMA::GetInstance() {
	if ( m_pInstance == NULL ) {
		m_pInstance = new DRAMHostDMA();
	}
	return m_pInstance;
}

DRAMHostDMA::DRAMHostDMA() {
	BdbmPcie* pcie = BdbmPcie::getInstance();

	m_read_done_cnt = 0;
	m_write_done_cnt = 0;
	m_write_done_total = pcie->userReadWord(m_fpga_write_stat_off);
	m_read_done_total = pcie->userReadWord(m_fpga_read_stat_off);
}

// offset: in FPGA mem (in bytes)
bool 
DRAMHostDMA::CopyToFPGA(size_t offset, void* buffer, size_t bytes) {
	m_mutex.lock();
	BdbmPcie* pcie = BdbmPcie::getInstance();

	size_t offset_frag = offset % m_fpga_alignment;
	if ( offset_frag != 0 ) {
		offset = (offset/m_fpga_alignment)*m_fpga_alignment;
		//io is simply shifted to align
		//bytes += offset_frag;
	}
	size_t src_bytes = bytes;
	size_t bytes_frag = bytes % m_fpga_alignment;
	if ( bytes_frag != 0 ) {
		bytes = (bytes/m_fpga_alignment+1)*m_fpga_alignment;
	}
	size_t writes_cnt = ( bytes/(m_max_dma_bytes/2) );
	if ( bytes%(m_max_dma_bytes/2) != 0 ) writes_cnt ++;

	size_t host_offset = 0;
	uint8_t* dmabuf8 = (uint8_t*)pcie->dmaBuffer();

	//printf( "Starting write with %ld chunks\n", writes_cnt ); fflush(stdout);
	for ( size_t i = 0; i < writes_cnt; i++ ) {
		size_t curbyte = m_max_dma_bytes/2;
		if ( m_max_dma_bytes/2 > bytes ) curbyte = bytes;

		size_t bufoff = 0;
		if ( i%2 != 0 ) bufoff = m_max_dma_bytes/2;
		if ( src_bytes < curbyte ) {
			memcpy(dmabuf8+bufoff, ((uint8_t*)buffer)+host_offset, src_bytes);
			memset(dmabuf8+bufoff+src_bytes, 0xFF, (curbyte-src_bytes));
		} else {
			memcpy(dmabuf8+bufoff, ((uint8_t*)buffer)+host_offset, curbyte);
		}

		size_t hostpageoff = bufoff/m_fpga_alignment;
		size_t pages = curbyte/m_fpga_alignment;
		size_t pageoff = offset/m_fpga_alignment;

		//printf( "Writing %lx pages from %lx to %lx\n", pages, hostpageoff, pageoff );

		pcie->userWriteWord(m_host_mem_arg, hostpageoff); // host mem page
		pcie->userWriteWord(m_fpga_mem_arg, pageoff);// fpga mem page
		pcie->userWriteWord(m_to_fpga_cmd, pages);

	
		uint32_t writecnt = pcie->userReadWord(m_fpga_write_stat_off);
		//printf( "Waiting for %d to reach %ld\n", writecnt, m_write_done_total + i );
		while ( writecnt < m_write_done_total + i ) {
			writecnt = pcie->userReadWord(m_fpga_write_stat_off);
		}
		//printf( "Write done!\n" );

		host_offset += curbyte;
		offset += curbyte;
		bytes -= curbyte;
		src_bytes -= curbyte;
	}

	if ( bytes != 0 ) {
		fprintf( stderr, "DRAMHostDMA CopyToFPGA bytes remaining after write! %ld %s:%d\n", bytes, __FILE__, __LINE__ );
	}

	uint32_t writecnt = pcie->userReadWord(m_fpga_write_stat_off);
	//printf( "Waiting for %d to reach %ld\n", writecnt, m_write_done_total +writes_cnt );
	while ( writecnt < m_write_done_total + writes_cnt ) {
		writecnt = pcie->userReadWord(m_fpga_write_stat_off);
	}
	m_write_done_total = writecnt;
	//printf( "Write done!\n" );


	m_mutex.unlock();
	return true;
}

bool 
DRAMHostDMA::CopyFromFPGA(size_t offset, void* buffer, size_t bytes) {
	m_mutex.lock();
	BdbmPcie* pcie = BdbmPcie::getInstance();
	//m_read_done_total = pcie->userReadWord(m_fpga_read_stat_off);

	size_t dst_bytes = bytes;
	size_t offset_frag = offset % m_fpga_alignment;
	if ( offset_frag != 0 ) {
		offset = (offset/m_fpga_alignment)*m_fpga_alignment;
		//io is simply shifted to align
		//bytes += offset_frag;
	}
	size_t bytes_frag = bytes % m_fpga_alignment;
	if ( bytes_frag != 0 ) {
		bytes = (bytes/m_fpga_alignment+1)*m_fpga_alignment;
	}
	size_t reads_cnt = ( bytes/(m_max_dma_bytes/2) ); //DOUBLE BUFFERING!
	if ( bytes%(m_max_dma_bytes/2) != 0 ) reads_cnt ++;

	size_t host_offset = 0;
	uint8_t* dmabuf8 = (uint8_t*)pcie->dmaBuffer();
	size_t curbyte = 0;
	size_t lastbyte = 0;
	//printf( "Starting write with %ld chunks\n", reads_cnt ); fflush(stdout);
	for ( size_t i = 0; i < reads_cnt; i++ ) {
		curbyte = m_max_dma_bytes/2;
		if ( m_max_dma_bytes/2 > bytes ) curbyte = bytes;


		size_t hostbufoff = 0;
		if ( i%2 != 0 ) hostbufoff = m_max_dma_bytes/2;
		size_t hostpageoff = hostbufoff/m_fpga_alignment;
		size_t pages = curbyte/m_fpga_alignment;
		size_t pageoff = offset/m_fpga_alignment;

		//printf( "%lx,%lx,%lx\n", hostpageoff, pageoff, pages );
		pcie->userWriteWord(m_host_mem_arg, hostpageoff);
		pcie->userWriteWord(m_fpga_mem_arg, pageoff);
		pcie->userWriteWord(m_to_host_cmd, pages);
		
		uint32_t readcnt = pcie->userReadWord(m_fpga_read_stat_off);
		//printf( "Waiting for %d to be %ld\n", readcnt, m_read_done_total + i );
		while ( readcnt < m_read_done_total + i ) {
			readcnt = pcie->userReadWord(m_fpga_read_stat_off);
		}

		if ( i > 0 ) {
			size_t bufoff = 0;
			if ( i%2 == 0 ) bufoff = m_max_dma_bytes/2;
			memcpy(((uint8_t*)buffer)+host_offset, dmabuf8 + bufoff, lastbyte);
			host_offset += lastbyte;
			dst_bytes -= lastbyte;
		}
		lastbyte = curbyte;

		offset += curbyte;
		bytes -= curbyte;
	}
	if ( bytes != 0 ) {
		fprintf( stderr, "DRAMHostDMA CopyToFPGA bytes remaining after read! %ld %s:%d\n", bytes, __FILE__, __LINE__ );
	}

	uint32_t readcnt = pcie->userReadWord(m_fpga_read_stat_off);
	while ( readcnt < m_read_done_total + reads_cnt ) {
		readcnt = pcie->userReadWord(m_fpga_read_stat_off);
	}
	m_read_done_total = readcnt;

	size_t bufoff = 0;
	if ( reads_cnt%2 == 0 ) bufoff = m_max_dma_bytes/2;
	if ( dst_bytes >= m_max_dma_bytes/2 ) {
		memcpy(((uint8_t*)buffer)+host_offset, dmabuf8+bufoff, m_max_dma_bytes/2);
	} else {
		memcpy(((uint8_t*)buffer)+host_offset, dmabuf8+bufoff, dst_bytes);
		memset(((uint8_t*)buffer)+host_offset+dst_bytes, 0xff, m_max_dma_bytes/2-dst_bytes);
	}

	m_mutex.unlock();
	return true;
}

