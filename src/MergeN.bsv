package MergeN;

import FIFO::*;
import FIFOF::*;
import Vector::*;

interface MergeEnqIfc#(type t);
	method Action enq(t d);
endinterface
interface Merge2Ifc#(type t);
	interface Vector#(2, MergeEnqIfc#(t)) enq;

	method Action deq;
	method t first;
endinterface

interface Merge4Ifc#(type t);
	interface Vector#(4, MergeEnqIfc#(t)) enq;

	method Action deq;
	method t first;
endinterface

module mkMerge4 (Merge4Ifc#(t))
	provisos(Bits#(t, a__));
	Vector#(2,Merge2Ifc#(t)) ma <- replicateM(mkMerge2);
	Merge2Ifc#(t) mb <- mkMerge2;
	for ( Integer i = 0; i < 2; i = i +1 ) begin
		rule ma1;
			ma[i].deq;
			mb.enq[i].enq(ma[i].first);
		endrule
	end

	Vector#(4, MergeEnqIfc#(t)) enq_;
	for ( Integer i = 0; i < 4; i = i + 1) begin
		enq_[i] = interface MergeEnqIfc;
			method Action enq(t d);
				ma[i/2].enq[i%2].enq(d);
			endmethod
		endinterface;
	end
	interface enq = enq_;
	method Action deq;
		mb.deq;
	endmethod
	method t first;
		return mb.first;
	endmethod
endmodule

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

	Vector#(2, MergeEnqIfc#(t)) enq_;

	enq_[0] = interface MergeEnqIfc;
		method Action enq(t d);
			inQ1.enq(d);
		endmethod
	endinterface;
	enq_[1] = interface MergeEnqIfc;
		method Action enq(t d);
			inQ2.enq(d);
		endmethod
	endinterface;

	interface enq = enq_;
	method Action deq = outQ.deq;
	method t first = outQ.first;
endmodule

interface MergeNIfc#(numeric type n, type t);
	interface Vector#(n, MergeEnqIfc#(t)) enq;

	method Action deq;
	method t first;
endinterface

/*
module mkMergeN (MergeNIfc#(n, t))
	provisos(Bits#(t, a__));

	Vector#(n, FIFOF#(t)) inQ <- replicateM(mkFIFOF);
	FIFO#(t) outQ <- mkFIFO;

	
	Vector#(n, MergeEnqIfc#(t)) enq_;
	for ( Integer i = 0; i < valueOf(n); i = i + 1 ) begin
		enq_[i] = interface MergeEnqIfc;
			method Action enq(t d);
				inQ[i].enq(d);
			endmethod
		endinterface;
	end

	interface enq = enq_;
	method Action deq = outQ.deq;
	method t first = outQ.first;
endmodule
*/

endpackage: MergeN


