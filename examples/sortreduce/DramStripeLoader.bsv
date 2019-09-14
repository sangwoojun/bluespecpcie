package DramStripeLoader;

import Vector::*;
import FIFO::*;
import BRAM::*;
import BRAMFIFO::*;

interface DramStripeLoaderIfc;
	method ActionValue#(Tuple2#(Bit#(512),Bool)) getData;
	method Action command(Bit#(32) startoff, Bit#(32) stripewords, Bit#(32) limitoff);

	// Connection to DRAM
	method ActionValue#(Tuple2#(Bit#(32), Bit#(16))) getBurstReadReq; // Offset, Words
	method Action putData(Bit#(512) data);
endinterface

module mkDramStripeLoader#(Integer buffersz, Integer fetchsz) (DramStripeLoaderIfc);
	
	FIFO#(Bit#(512)) bufferQ <- mkSizedBRAMFIFO(buffersz);
	FIFO#(Tuple2#(Bit#(32),Bit#(16))) dramReadReqQ <- mkFIFO;
	FIFO#(Bit#(512)) inDataQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(512),Bool)) outDataQ <- mkFIFO;
	Reg#(Bit#(32)) bufferInCnt <- mkReg(0);
	Reg#(Bit#(32)) bufferOutCnt <- mkReg(0);
	
	Reg#(Bit#(32)) baseOff <- mkReg(0);
	Reg#(Bit#(32)) stripeWords <- mkReg(0);
	Reg#(Bit#(32)) limitOff <- mkReg(0);

	rule genReadReq ( bufferInCnt-bufferOutCnt < fromInteger(buffersz-fetchsz) && baseOff < limitOff );
		dramReadReqQ.enq(tuple2(baseOff, fromInteger(fetchsz)));
		baseOff <= baseOff + fromInteger(fetchsz);
		bufferInCnt <= bufferInCnt + fromInteger(fetchsz);
	endrule


	rule relayBufferQ;
		let d = inDataQ.first;
		bufferQ.enq(d);
		inDataQ.deq;
	endrule

	Reg#(Bit#(32)) fetchInternalOFf <- mkReg(0);
	rule relayOutQ;
		bufferQ.deq;
		bufferOutCnt <= bufferOutCnt + 1;
		if ( fetchInternalOFf + 1 >= stripeWords ) begin
			fetchInternalOFf <= 0;
			outDataQ.enq(tuple2(bufferQ.first,True));
		end else begin
			fetchInternalOFf <= fetchInternalOFf + 1;
			outDataQ.enq(tuple2(bufferQ.first,False));
		end
	endrule
	method ActionValue#(Tuple2#(Bit#(512),Bool)) getData;
		outDataQ.deq;
		return outDataQ.first;
	endmethod
	method Action command(Bit#(32) startoff, Bit#(32) stripewords, Bit#(32) limitoff) if (baseOff >= limitOff);
		baseOff <= startoff;
		stripeWords <= stripewords;
		limitOff <= limitoff;
	endmethod

	// Connection to DRAM
	method ActionValue#(Tuple2#(Bit#(32), Bit#(16))) getBurstReadReq; // Offset, Words
		dramReadReqQ.deq;
		return dramReadReqQ.first;
	endmethod
	method Action putData(Bit#(512) data);
		inDataQ.enq(data);
	endmethod
endmodule

endpackage: DramStripeLoader
