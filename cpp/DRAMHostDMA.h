#ifndef __DRAMHOSTDMA_H__
#define __DRAMHOSTDMA_H__

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "bdbmpcie.h"

#include <queue>
#include <mutex>


class DRAMHostDMA {
public:
	static DRAMHostDMA* GetInstance();

	// offset and bytes will be force-aligned to whatever alignment the FPGA hardware requires
	// So it's best to always use it in an aligned fashion
	// (Right now it's 4 KB for everything)
	bool CopyToFPGA(size_t offset, void* buffer, size_t bytes);
	bool CopyFromFPGA(size_t offset, void* buffer, size_t bytes);

private:
	DRAMHostDMA();
	static DRAMHostDMA* m_pInstance;
	std::mutex m_mutex;


	void ProcDoneCnt();
	uint32_t m_read_done_cnt;
	uint32_t m_write_done_cnt;
	uint32_t m_write_done_total;
	uint32_t m_read_done_total;


private: // constants
	static const uint32_t m_host_mem_arg = 256*4;
	static const uint32_t m_fpga_mem_arg = 257*4;
	static const uint32_t m_fpga_write_stat_off = 256*4;
	static const uint32_t m_fpga_read_stat_off = 257*4;
	static const uint32_t m_to_fpga_cmd = 258*4;
	static const uint32_t m_to_host_cmd = 259*4;

	// m_max_dma_bytes MUST be multiples of m_fpga_alignment
	static const uint32_t m_fpga_alignment = (4*1024);
	static const uint32_t m_max_dma_bytes = (1024*1024);
};

#endif
