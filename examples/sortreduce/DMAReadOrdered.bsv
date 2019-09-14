package DMAReadOrdered;

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import BRAM::*;

import PcieCtrl::*;

import MergeN::*;

typedef 16 DmaTagCnt;
typedef TLog#(DmaTagCnt) DmaTagSz;

interface DMAReadOrderedIfc;
	method Action readReq(Bit#(32) data, Bit#(10) words);
	method ActionValue#(DMAWord) get;
endinterface

module mkDMAReadOrdered#(PcieUserIfc pcie) (DMAReadOrderedIfc);

	Integer dmaTagCnt = valueOf(DmaTagCnt);
	BRAM2Port#(Bit#(TAdd#(DmaTagSz,3)), Bit#(128)) dmaReorderBuffer <- mkBRAM2Server(defaultValue); //2K, 16 tags @ 128 bytes
	Vector#(DmaTagCnt, Bit#(3)) dmaReadOffset <- replicateM(mkReg(0));
	Vector#(DmaTagCnt, Bit#(3)) dmaReadLeft <- replicateM(mkReg(0));

	FIFO#(Bit#(DmaTagSz)) freeTagQ <- mkSizedFIFO(dmaTagCnt);
	FIFO#(Bit#(DmaTagSz)) tagOrderQ <- mkSizedFIFO(dmaTagCnt);

	FIFO#(Tuple2#(Bit#(32),Bit#(10))) readReqQ <- mkFIFO;

	rule sendDmaRead;
		let r = readReqQ.first;
		readReqQ.deq;
		let tag = freeTagQ.first;
		freeTagQ.deq;
		tagOrderQ.enq(tag);

		let addr = tpl_1(r);
		let words = tpl_2(r);

		pcie.dmaReadReq(addr,words,tag);
	endrule

	rule getDmaRead;
		DMAWordTagged rd <- pcie.dmaReadWord;

	endrule



	method Action readReq(Bit#(32) data, Bit#(10) words);
		readReqQ.enq(tuple2(data,words));
	endmethod
	method ActionValue#(DMAWord) get;
	endmethod
endmodule

endpackage
