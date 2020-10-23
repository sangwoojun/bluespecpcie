package ScatterN;

// FIXME I think this one is incorrect

import FIFO::*;
import FIFOF::*;
import Vector::*;

interface ScatterGetIfc#(type t);
	method ActionValue#(t) get;
endinterface

interface ScatterNProtIfc#(numeric type n, numeric type bn, type t);
	interface Vector#(n, ScatterGetIfc#(t)) get;

	method Action enq(t data, Bit#(TLog#(bn)) dst);
endinterface

module mkScatterNProt (ScatterNProtIfc#(n,bn,t))
	provisos(Bits#(t,a__)
	);

	if ( valueOf(n) > 2 ) begin
		Vector#(2,ScatterNProtIfc#(TDiv#(n,2), bn,t)) sa <- replicateM(mkScatterNProt);
		Integer dsz = valueOf(TLog#(n));


		Vector#(n, ScatterGetIfc#(t)) get_;
		for ( Integer i = 0; i < valueOf(n); i=i+1 ) begin
			get_[i] = interface ScatterGetIfc;
				method ActionValue#(t) get;
				/*
					if ( i < valueOf(n)/2 ) begin
						let d <- sa[0].get[i%(valueOf(n)/2)].get;
						return d;
					end else begin
						let d <- sa[1].get[i-(valueOf(n)/2)].get;
						return d;
					end
				*/
					if ( i%2 == 0  ) begin
						let d <- sa[0].get[i/2].get;
						return d;
					end else begin
						let d <- sa[1].get[i/2].get;
						return d;
					end
				endmethod
			endinterface;
		end
		interface get = get_;


		method Action enq(t data, Bit#(TLog#(bn)) dst);
			//Bit#(TLog#(bn)) ndst = dst;
			//ndst[dsz-1] = 0;
			//if ( dst[dsz-1] == 0 ) begin
			if ( dst%2 == 0 ) begin
				sa[0].enq(data, dst/2);
			end else begin
				sa[1].enq(data, dst/2);
			end
		endmethod

	end else if ( valueOf(n) == 2 ) begin
		FIFO#(t) getQ1 <- mkFIFO;
		FIFO#(t) getQ2 <- mkFIFO;
		Vector#(n, ScatterGetIfc#(t)) get_;
		get_[0] = interface ScatterGetIfc;
			method ActionValue#(t) get;
				getQ1.deq;
				return getQ1.first;
			endmethod
		endinterface;
		get_[1] = interface ScatterGetIfc;
			method ActionValue#(t) get;
				getQ2.deq;
				return getQ2.first;
			endmethod
		endinterface;
		interface get = get_;
		method Action enq(t data, Bit#(TLog#(bn)) dst);
			if ( dst[0] == 0 ) begin
				getQ1.enq(data);
			end else begin
				getQ2.enq(data);
			end
		endmethod
	end else begin
		FIFO#(t) getQ <- mkFIFO;
		Vector#(n, ScatterGetIfc#(t)) get_;
		get_[0] = interface ScatterGetIfc;
			method ActionValue#(t) get;
				getQ.deq;
				return getQ.first;
			endmethod
		endinterface;
		interface get = get_;
		method Action enq(t data, Bit#(TLog#(bn)) dst);
			getQ.enq(data);
		endmethod
	end
endmodule

interface ScatterNIfc#(numeric type n, type t);
	interface Vector#(n, ScatterGetIfc#(t)) get;

	method Action enq(t data, Bit#(TLog#(n)) dst);
endinterface

module mkScatterN (ScatterNIfc#(n,t))
	provisos(Bits#(t,a__)
	);
	ScatterNProtIfc#(n,n,t) sa <- mkScatterNProt;

	FIFO#(Tuple2#(t,Bit#(TLog#(n)))) inQ <- mkFIFO;
	rule relenq;
		let data = tpl_1(inQ.first);
		let dst = tpl_2(inQ.first);
		sa.enq(data,dst);
		inQ.deq;
	endrule

	Vector#(n, ScatterGetIfc#(t)) get_;
	for ( Integer i = 0; i < valueOf(n); i=i+1 ) begin
		get_[i] = interface ScatterGetIfc;
			method ActionValue#(t) get;
				let d <- sa.get[i].get;
				return d;
			endmethod
		endinterface;
	end
	interface get = get_;
	method Action enq(t data, Bit#(TLog#(n)) dst);
		inQ.enq(tuple2(data,dst));
	endmethod
endmodule

endpackage: ScatterN
