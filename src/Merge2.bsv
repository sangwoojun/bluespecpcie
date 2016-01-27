package Merge2;

import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;

interface Merge2Ifc#(type t);
	method Action enq1(t d);
	method Action enq2(t d);

	method Action deq;
	method t first;
endinterface

module mkMerge2 (Merge2Ifc#(t))
	provisos(Bits#(t, a__));
	FIFOF#(t) inQ1 <- mkFIFOF;
	FIFOF#(t) inQ2 <- mkFIFOF;
	FIFO#(t) outQ <- mkFIFO;

	Reg#(Bit#(1)) prio <- mkReg(0);
	rule merge;
		if ( prio == 0 ) begin
			if ( inQ1.notEmpty ) begin
				inQ1.deq;
				outQ.enq(inQ1.first);
			end else if ( inQ2.notEmpty ) begin
				inQ2.deq;
				outQ.enq(inQ2.first);
			end
			prio <= 1;
		end else begin
			if ( inQ2.notEmpty ) begin
				inQ2.deq;
				outQ.enq(inQ2.first);
			end else if ( inQ1.notEmpty ) begin
				inQ1.deq;
				outQ.enq(inQ1.first);
			end
			prio <= 0;
		end
	endrule

	method Action enq1(t d);
		inQ1.enq(d);
	endmethod
	method Action enq2(t d);
		inQ2.enq(d);
	endmethod
	method Action deq = outQ.deq;
	method t first = outQ.first;
endmodule

endpackage: Merge2

