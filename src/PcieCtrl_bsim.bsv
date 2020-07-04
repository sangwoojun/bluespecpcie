package PcieCtrl_bsim;

import FIFO::*;

import PcieCtrl::*;

import "BDPI" function Bool bdpiIOReady();
import "BDPI" function ActionValue#(Bit#(64)) bdpiIOData();
import "BDPI" function ActionValue#(Bool) bdpiIOReadRespReady();
import "BDPI" function ActionValue#(Bool) bdpiIOReadResp(Bit#(64) data);

import "BDPI" function ActionValue#(Bool) bdpiDmaWriteData(Bit#(32) addr, Bit#(64) data1, Bit#(64) data2);
import "BDPI" function ActionValue#(Bool) bdpiDmaReadReq(Bit#(32) addr, Bit#(10) words);
import "BDPI" function ActionValue#(Bool) bdpiDmaReadReady();
import "BDPI" function ActionValue#(Bit#(32)) bdpiDmaReadData();
import "BDPI" function Bool bdpiInterruptReady();
import "BDPI" function Action bdpiAssertInterrupt();


module mkPcieCtrl_bsim (PcieCtrlIfc);
	Integer dma_buf_offset = valueOf(DMABufOffset); //must match one in driver
	Integer io_userspace_offset = valueOf(IoUserSpaceOffset);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Reg#(Bit#(10)) dmaWriteWordCount <- mkReg(0);
	Reg#(Bit#(32)) dmaWriteWordAddr <- mkReg(0);
	Reg#(Bit#(32)) dmaWriteWordOff <- mkReg(0);

	Reg#(Bit#(10)) dmaReadWordCount <- mkReg(0);
	FIFO#(DMAWord) dmaReadWordQ <- mkSizedFIFO(16);

	Reg#(DMAWord) dmaReadBuffer <- mkReg(0);
	Reg#(Bit#(8)) dmaReadBufferOff <- mkReg(0);
	rule receiveDmaRead ( dmaReadWordCount > 0 );
		let isready <- bdpiDmaReadReady();
		if ( isready ) begin
			let d <- bdpiDmaReadData();
			if ( dmaReadBufferOff >= 3 ) begin
				dmaReadWordCount <= dmaReadWordCount - 1;
				dmaReadWordQ.enq( {d, dmaReadBuffer[127:32]} );
				dmaReadBufferOff <= 0;
			end else begin
				dmaReadBuffer <= {d,dmaReadBuffer[127:32]};
				dmaReadBufferOff <= dmaReadBufferOff + 1;
			end
		end
	endrule
	

	FIFO#(IOWrite) ioWriteQ <- mkFIFO;
	FIFO#(IOReadReq) ioReadReqQ <- mkFIFO;
	rule receiveIO; 
		let d <- bdpiIOData();

		Bit#(32) data = truncate(d);
		Bit#(20) addr = truncate(d>>32);
		Bit#(1) write = truncate(d>>(32+24));
		Bit#(1) notready = truncate(d>>(32+31));

		if ( 0 == notready ) begin
			if ( write == 1 ) begin
				if ( addr >= fromInteger(io_userspace_offset) ) begin
					ioWriteQ.enq(IOWrite{addr: addr-fromInteger(io_userspace_offset), data:data});
				end else begin
					//TODO save to BRAM
				end
				//$display( "IOwrite addr:%x, data:%x", addr, data );
			end
			else begin
				IOReadReq rr = ?;
				rr.addr = addr - fromInteger(io_userspace_offset);
				if ( addr >= fromInteger(io_userspace_offset) ) begin
					ioReadReqQ.enq(rr);
				end else begin
					let dd <- bdpiIOReadResp({0,addr, 32'hc001d00d});
				end
				//$display( "IOread addr: %x", addr);
			end
		end
		$fflush(stdout);
	endrule

	FIFO#(IOReadReq) ioReadReqReturnQ <- mkFIFO;
	FIFO#(Bit#(32)) ioReadReqDataQ <- mkFIFO;
	rule relayIOReadResp;
		let isready <- bdpiIOReadRespReady;
		if ( isready ) begin
			let ioreq = ioReadReqReturnQ.first;
			let data = ioReadReqDataQ.first;
			let d <- bdpiIOReadResp({0,ioreq.addr + fromInteger(io_userspace_offset), data});
			ioReadReqReturnQ.deq;
			ioReadReqDataQ.deq;
		end
	endrule



	interface PcieUserIfc user;
		interface Clock user_clk = curClk;
		interface Reset user_rst = curRst;
		method ActionValue#(IOWrite) dataReceive;
			ioWriteQ.deq;
			return ioWriteQ.first;
		endmethod
		method ActionValue#(IOReadReq) dataReq;
			ioReadReqQ.deq;
			let d = ioReadReqQ.first;
			return d;
		endmethod
		method Action dataSend(IOReadReq ioreq, Bit#(32) data );// if (bdpiIOReadRespReady() );
			ioReadReqReturnQ.enq(ioreq);
			ioReadReqDataQ.enq(data);
			//let d <- bdpiIOReadResp({0,ioreq.addr, data});
			//$display( "IOread resp addr: %x data: %x\n", ioreq.addr, data );
		endmethod

		method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words ) if ( dmaWriteWordCount == 0);
			dmaWriteWordCount <= words;
			dmaWriteWordAddr <= addr;
			dmaWriteWordOff <= 0;
		endmethod
		method Action dmaWriteData(DMAWord data) if ( dmaWriteWordCount > 0 );
			Bool r <- bdpiDmaWriteData(dmaWriteWordAddr+dmaWriteWordOff, truncate(data), truncate(data>>64));
			dmaWriteWordOff <= dmaWriteWordOff + 16;
			dmaWriteWordCount <= dmaWriteWordCount - 1;
			//$display("dma data %x",data);
		endmethod
		method Action dmaReadReq(Bit#(32) addr, Bit#(10) words) if ( dmaReadWordCount == 0 );
			dmaReadWordCount <= words;

			let d <- bdpiDmaReadReq(addr,words);
		endmethod
		method ActionValue#(DMAWord) dmaReadWord;
			dmaReadWordQ.deq;
			return dmaReadWordQ.first;
		endmethod

		method Action assertInterrupt if ( bdpiInterruptReady() );
			bdpiAssertInterrupt();
		endmethod
		method Action assertUptrain;
		endmethod

		method Bit#(32) debug_data;
			return 0;
		endmethod

	endinterface
endmodule

endpackage: PcieCtrl_bsim
