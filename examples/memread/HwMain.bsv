import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import DMASplitter::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	DMASplitterIfc#(4) dma <- mkDMASplitter(pcie);

	Reg#(Bit#(32)) bytesReadLeft <- mkReg(0);
	Reg#(Bit#(32)) bytesRecvLeft <- mkReg(0);

	rule getFlashCmd;
		dma.deq;
		Bit#(128) d = dma.first;
		Bit#(32) h = dma.header;
		if ( h == 0 ) begin
			bytesReadLeft <= truncate(d);
			bytesRecvLeft <= truncate(d);
			$display("Starting memread for %d bytes", d );
			dma.enq(1,d);
		end
	endrule

	rule sendDMAReq ( bytesReadLeft > 0 );
		Bit#(16) off = truncate(bytesReadLeft);
		//Bit#(32) dmao = (1<<16)-zeroExtend(off);
		Bit#(32) dmao = zeroExtend(off);
		$display( "Sending DMA read request addr: %x", dmao );
		if ( bytesReadLeft >= 64 ) begin
			bytesReadLeft <= bytesReadLeft - 64;
			dma.dmaReadReq(dmao, 4);
		end else begin
			bytesReadLeft <= 0;
			dma.dmaReadReq(dmao, truncate(bytesReadLeft/16));
		end
	endrule
	rule recvDMAData;
		let d <- dma.dmaReadWord;
		$display( "read %d %x", bytesRecvLeft, d );
		if ( bytesRecvLeft > 16 ) begin
			bytesRecvLeft <= bytesRecvLeft - 16;
			dma.enq(1,d);
		end else begin
			bytesRecvLeft <= 0;
			dma.enq(0,d);
		end
	endrule

endmodule
