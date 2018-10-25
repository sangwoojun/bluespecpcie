package MergeN;

import FIFO::*;
import FIFOF::*;
import Vector::*;

interface ScatterDeqIfc#(type t);
	method Action deq;
	method t first;
endinterface

interface ScatterNIfc#(numeric type n, type t);
	method Action enq(t data, Bit#(8) dst);
	interface Vector#(n,ScatterDeqIfc#(t)) get;
endinterface

interface MergeEnqIfc#(type t);
	method Action enq(t d);
endinterface

interface MergeNIfc#(numeric type n, type t);
	interface Vector#(n, MergeEnqIfc#(t)) enq;

	method Action deq;
	method t first;
endinterface

module mkScatterN (ScatterNIfc#(n,t))
	provisos(Bits#(t, a__), Log#(n,nsz)//, Add#(b__,TLog#(TDiv#(n,2)),TLog#(n))
	);
	if ( valueOf(n) > 2 ) begin
		Vector#(2,ScatterNIfc#(TDiv#(n,2), t)) sa <- replicateM(mkScatterN);
		FIFO#(Tuple2#(t,Bit#(8))) inQ <- mkFIFO;

		rule relayInput;
			let d = inQ.first;
			inQ.deq;
			let data =tpl_1(d);
			let dst = tpl_2(d);
			if ( dst[valueOf(nsz)-1] == 0 ) sa[0].enq(data, dst);
			else sa[1].enq(data, truncate(dst));
		endrule

		//Vector#(2,FIFO#(t)) vOutQ <- replicateM(mkFIFO);
		Vector#(n, ScatterDeqIfc#(t)) get_;
		for ( Integer i = 0; i < valueOf(n); i=i+1) begin
			get_[i] = interface ScatterDeqIfc;
				method Action deq;
					if ( i < valueOf(n)/2 ) begin
						sa[0].get[i].deq;
					end else begin
						sa[1].get[i-(valueOf(n)/2)].deq;
					end
				endmethod
				method t first;
					if ( i < valueOf(n)/2 ) begin
						return sa[0].get[i].first;
					end else begin
						return sa[1].get[i-(valueOf(n)/2)].first;
					end
				endmethod
			endinterface;
		end
		interface get = get_;
		method Action enq(t data, Bit#(8) dst);
			inQ.enq(tuple2(data,dst));
		endmethod

	end else if ( valueOf(n) == 2 ) begin
		Vector#(2,FIFO#(t)) vOutQ <- replicateM(mkFIFO);
		Vector#(n, ScatterDeqIfc#(t)) get_;
		for ( Integer i = 0; i < 2; i=i+1) begin
			get_[i] = interface ScatterDeqIfc;
				method Action deq;
					vOutQ[i].deq;
				endmethod
				method t first;
					return vOutQ[i].first;
				endmethod
			endinterface;
		end
		interface get = get_;
		method Action enq(t data, Bit#(8) dst);
			if ( dst[0] == 0 ) vOutQ[0].enq(data);
			else vOutQ[1].enq(data);
		endmethod

	end else begin
		FIFO#(t) inQ <- mkFIFO;
		Vector#(n, ScatterDeqIfc#(t)) get_;
		get_[0] = interface ScatterDeqIfc;
			method Action deq;
				inQ.deq;
			endmethod
			method t first;
				return inQ.first;
			endmethod
		endinterface;
		interface get = get_;
		method Action enq(t data, Bit#(8) dst);
			inQ.enq(data);
		endmethod
	end
endmodule

module mkMergeN (MergeNIfc#(n,t))
	provisos(Bits#(t, a__));

	if ( valueOf(n) > 2 ) begin
		Vector#(2,MergeNIfc#(TDiv#(n,2), t)) ma <- replicateM(mkMergeN);
		Merge2Ifc#(t) mb <- mkMerge2;
		for ( Integer i = 0; i < 2; i = i +1 ) begin
			rule ma1;
				ma[i].deq;
				mb.enq[i].enq(ma[i].first);
			endrule
		end

		Vector#(n, MergeEnqIfc#(t)) enq_;
		for ( Integer i = 0; i < valueOf(n); i = i + 1) begin
			enq_[i] = interface MergeEnqIfc;
				method Action enq(t d);
					if ( i < valueOf(n)/2 ) begin
						ma[0].enq[i%(valueOf(n)/2)].enq(d);
					end else begin
						ma[1].enq[i-(valueOf(n)/2)].enq(d);
					end
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
	end else if (valueOf(n) == 2) begin
		Merge2Ifc#(t) mb <- mkMerge2;
		Vector#(n, MergeEnqIfc#(t)) enq_;
		for ( Integer i = 0; i < valueOf(n); i = i + 1) begin
			enq_[i] = interface MergeEnqIfc;
				method Action enq(t d);
					mb.enq[i].enq(d);
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
	end else begin
		FIFO#(t) inQ <- mkFIFO;
		Vector#(n,MergeEnqIfc#(t)) enq_;
		enq_[0] = interface MergeEnqIfc;
			method Action enq(t d);
				inQ.enq(d);
			endmethod
		endinterface;
		interface enq = enq_;
		method Action deq;
			inQ.deq;
		endmethod
		method t first;
			return inQ.first;
		endmethod
	end
endmodule

interface Merge2Ifc#(type t);
	interface Vector#(2, MergeEnqIfc#(t)) enq;

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



//FIXME
// Left for backwards compatibility
// Use is discouraged


interface Merge4Ifc#(type t);
	interface Vector#(4, MergeEnqIfc#(t)) enq;

	method Action deq;
	method t first;
endinterface

interface Merge8Ifc#(type t);
	interface Vector#(8, MergeEnqIfc#(t)) enq;

	method Action deq;
	method t first;
endinterface

module mkMerge8 (Merge8Ifc#(t))
	provisos(Bits#(t, a__));
	Vector#(2,Merge4Ifc#(t)) ma <- replicateM(mkMerge4);
	Merge2Ifc#(t) mb <- mkMerge2;
	for ( Integer i = 0; i < 2; i = i +1 ) begin
		rule ma1;
			ma[i].deq;
			mb.enq[i].enq(ma[i].first);
		endrule
	end

	Vector#(8, MergeEnqIfc#(t)) enq_;
	for ( Integer i = 0; i < 8; i = i + 1) begin
		enq_[i] = interface MergeEnqIfc;
			method Action enq(t d);
				ma[i/4].enq[i%4].enq(d);
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


endpackage: MergeN


