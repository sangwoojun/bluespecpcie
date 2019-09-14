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
			if ( dst < fromInteger(valueOf(n)/2) ) sa[0].enq(data,dst);
			else sa[1].enq(data, dst-fromInteger(valueOf(n)/2));
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

interface BurstMergeEnqIfc#(type t, numeric type bSz);
	method Action enq(t d);
	method Action burst(Bit#(bSz) b);
endinterface

interface BurstMergeNIfc#(numeric type n, type t, numeric type bSz);
	interface Vector#(n, BurstMergeEnqIfc#(t, bSz)) enq;

	method ActionValue#(Bit#(bSz)) getBurst;
	method Action deq;
	method t first;
endinterface


module mkBurstMergeN(BurstMergeNIfc#(n,t,bSz))
	provisos(Bits#(t, tSz));
	FIFO#(t) outQ <- mkFIFO;
	FIFO#(Bit#(bSz)) burstQ <- mkFIFO;
	Vector#(n,BurstMergeEnqIfc#(t,bSz)) enq_;

	if ( valueOf(n) > 2 ) begin
		Vector#(2, BurstMergeNIfc#(TDiv#(n,2),t,bSz)) ma <- replicateM(mkBurstMergeN);
		BurstMergeNIfc#(2,t,bSz) m0 <- mkBurstMergeN;

		rule relayBurst;
			let b <- m0.getBurst;
			burstQ.enq(b);
		endrule
		rule relayData;
			m0.deq;
			outQ.enq(m0.first);
		endrule

		for ( Integer i = 0; i < 2; i=i+1 ) begin
			rule relayData_s;
				ma[i].deq;
				m0.enq[i].enq(ma[i].first);
			endrule
			rule relayBurst_s;
				let b <- ma[i].getBurst;
				m0.enq[i].burst(b);
			endrule
		end
		
		for ( Integer i = 0; i < valueOf(n); i=i+1 ) begin
			enq_[i] = interface BurstMergeEnqIfc;
				method Action enq(t d);
					if ( i < valueOf(n)/2 ) begin
						ma[0].enq[i%(valueOf(n)/2)].enq(d);
					end else begin
						ma[1].enq[i-(valueOf(n)/2)].enq(d);
					end
				endmethod
				method Action burst(Bit#(bSz) b);
					if ( i < valueOf(n)/2 ) begin
						ma[0].enq[i%(valueOf(n)/2)].burst(b);
					end else begin
						ma[1].enq[i-(valueOf(n)/2)].burst(b);
					end
				endmethod
			endinterface;
		end
	end else if ( valueOf(2) == 2 ) begin
		
		Merge2Ifc#(Tuple2#(Bit#(1), Bit#(bSz))) reqM <- mkMerge2;
		Vector#(2,FIFO#(t)) inQ <- replicateM(mkFIFO);

		Reg#(Bit#(bSz)) burstLeft <- mkReg(0);
		Reg#(Bit#(1)) burstSource <- mkReg(?);
		rule relay;
			if ( burstLeft == 0 ) begin
				reqM.deq;
				let r_ = reqM.first;
				burstLeft <= tpl_2(r_)-1;
				burstSource <= tpl_1(r_);
				
				let inidx = tpl_1(r_);
				outQ.enq(inQ[inidx].first);
				inQ[inidx].deq;

				burstQ.enq(tpl_2(r_));
			end else begin
				outQ.enq(inQ[burstSource].first);
				inQ[burstSource].deq;
				burstLeft <= burstLeft - 1;
			end
		endrule
		for ( Integer i = 0; i < 2; i=i+1 ) begin
			enq_[i] = interface BurstMergeEnqIfc;
				method Action enq(t d);
					inQ[i].enq(d);
				endmethod
				method Action burst(Bit#(bSz) b);
					reqM.enq[i].enq(tuple2(fromInteger(i),b));
				endmethod
			endinterface;
		end

	end else begin // n == 1
		enq_[0] = interface BurstMergeEnqIfc;
			method Action enq(t d);
				outQ.enq(d);
			endmethod
			method Action burst(Bit#(bSz) b);
				burstQ.enq(b);
			endmethod
		endinterface;
	end 

	interface enq = enq_;
	method Action deq;
		outQ.deq;
	endmethod
	method t first;
		return outQ.first;
	endmethod
	method ActionValue#(Bit#(bSz)) getBurst;
		burstQ.deq;
		return burstQ.first;
	endmethod
endmodule

interface BurstIOMergeEnqIfc#(type t, numeric type aSz, numeric type bSz);
	method Action enq(t d);
	method Action burst(Bit#(aSz) a, Bit#(bSz) b);
endinterface

// number, type, burst size, address size
interface BurstIOMergeNIfc#(numeric type n, type t, numeric type aSz, numeric type bSz);
	interface Vector#(n, BurstIOMergeEnqIfc#(t, aSz, bSz)) enq;

	method ActionValue#(Tuple2#(Bit#(aSz), Bit#(bSz))) getBurst;
	method Action deq;
	method t first;
endinterface


module mkBurstIOMergeN(BurstIOMergeNIfc#(n,t,aSz,bSz))
	provisos(Bits#(t, tSz));
	FIFO#(t) outQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(aSz), Bit#(bSz))) burstQ <- mkFIFO;
	Vector#(n,BurstIOMergeEnqIfc#(t,aSz,bSz)) enq_;

	if ( valueOf(n) > 2 ) begin
		Vector#(2, BurstIOMergeNIfc#(TDiv#(n,2),t,aSz,bSz)) ma <- replicateM(mkBurstIOMergeN);
		BurstIOMergeNIfc#(2,t,aSz,bSz) m0 <- mkBurstIOMergeN;

		rule relayBurst;
			let b <- m0.getBurst;
			burstQ.enq(tuple2(tpl_1(b), tpl_2(b)));
		endrule
		rule relayData;
			m0.deq;
			outQ.enq(m0.first);
		endrule

		for ( Integer i = 0; i < 2; i=i+1 ) begin
			rule relayData_s;
				ma[i].deq;
				m0.enq[i].enq(ma[i].first);
			endrule
			rule relayBurst_s;
				let b <- ma[i].getBurst;
				m0.enq[i].burst(tpl_1(b),tpl_2(b));
			endrule
		end
		
		for ( Integer i = 0; i < valueOf(n); i=i+1 ) begin
			enq_[i] = interface BurstIOMergeEnqIfc;
				method Action enq(t d);
					if ( i < valueOf(n)/2 ) begin
						ma[0].enq[i%(valueOf(n)/2)].enq(d);
					end else begin
						ma[1].enq[i-(valueOf(n)/2)].enq(d);
					end
				endmethod
				method Action burst(Bit#(aSz) a, Bit#(bSz) b);
					if ( i < valueOf(n)/2 ) begin
						ma[0].enq[i%(valueOf(n)/2)].burst(a,b);
					end else begin
						ma[1].enq[i-(valueOf(n)/2)].burst(a,b);
					end
				endmethod
			endinterface;
		end
	end else if ( valueOf(2) == 2 ) begin
		
		Merge2Ifc#(Tuple2#(Bit#(1), Tuple2#(Bit#(aSz),Bit#(bSz)))) reqM <- mkMerge2;
		Vector#(2,FIFO#(t)) inQ <- replicateM(mkFIFO);

		Reg#(Bit#(bSz)) burstLeft <- mkReg(0);
		Reg#(Bit#(1)) burstSource <- mkReg(?);
		rule relay;
			if ( burstLeft == 0 ) begin
				reqM.deq;
				let r_ = reqM.first;
				Tuple2#(Bit#(aSz),Bit#(bSz)) bd = tpl_2(r_);
				burstLeft <= tpl_2(bd)-1;
				burstSource <= tpl_1(r_);
				
				let inidx = tpl_1(r_);
				outQ.enq(inQ[inidx].first);
				inQ[inidx].deq;

				burstQ.enq(tpl_2(r_));
			end else begin
				outQ.enq(inQ[burstSource].first);
				inQ[burstSource].deq;
				burstLeft <= burstLeft - 1;
			end
		endrule
		for ( Integer i = 0; i < 2; i=i+1 ) begin
			enq_[i] = interface BurstIOMergeEnqIfc;
				method Action enq(t d);
					inQ[i].enq(d);
				endmethod
				method Action burst(Bit#(aSz) a, Bit#(bSz) b);
					reqM.enq[i].enq(tuple2(fromInteger(i),tuple2(a,b)));
				endmethod
			endinterface;
		end

	end else begin // n == 1
		enq_[0] = interface BurstIOMergeEnqIfc;
			method Action enq(t d);
				outQ.enq(d);
			endmethod
			method Action burst(Bit#(aSz) a, Bit#(bSz) b);
				burstQ.enq(tuple2(a,b));
			endmethod
		endinterface;
	end 

	interface enq = enq_;
	method Action deq;
		outQ.deq;
	endmethod
	method t first;
		return outQ.first;
	endmethod
	method ActionValue#(Tuple2#(Bit#(aSz), Bit#(bSz))) getBurst;
		burstQ.deq;
		return burstQ.first;
	endmethod
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


