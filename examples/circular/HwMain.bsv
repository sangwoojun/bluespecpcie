import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import DMACircularQueue::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;


	DMACircularQueueIfc#(10) dmaQ <- mkDMACircularQueue(pcie); // 8K * 8 = 64KB 
	Reg#(Bit#(256)) dataEnqCounter <- mkReg(512*16); // 16 8K pages
	rule enqData(dataEnqCounter > 0);
		dmaQ.enq(dataEnqCounter);
		dataEnqCounter <= dataEnqCounter - 1;
	endrule
endmodule
