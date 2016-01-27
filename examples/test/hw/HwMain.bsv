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

	rule getFlashCmd;
		dma.deq;
		Bit#(128) d = dma.first;
	endrule

	rule handleFlashWriteReady;
		//dma.enq({32'h1,32'h2,zeroExtend(data)}); // 32'h1 for testing purposes
	endrule
	

endmodule
