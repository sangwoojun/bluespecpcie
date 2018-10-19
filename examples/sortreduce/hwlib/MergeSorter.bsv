import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import SortingNetwork::*;

interface StreamVectorMergerIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq1(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
	method Action enq2(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
endinterface

module mkStreamVectorMerger#(Bool descending) (StreamVectorMergerIfc#(vcnt, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Ord#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz)
	);
	
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) inQ1 <- mkFIFO;
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) inQ2 <- mkFIFO;
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) outQ <- mkFIFO;
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) outQ2 <- mkFIFO;


	Reg#(Vector#(vcnt,Tuple2#(keyType,valType))) abuf <- mkReg(?);
	Reg#(Maybe#(Bool)) append1 <- mkReg(tagged Invalid);
	Reg#(Tuple2#(keyType,valType)) atail <- mkReg(?);

	rule lastInvalid (!isValid(inQ1.first) && !isValid(inQ2.first));
		inQ1.deq;
		inQ2.deq;
		outQ.enq(tagged Invalid);
	endrule
	
	rule ff1 (isValid(inQ1.first) && !isValid(inQ2.first));
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(tagged Valid abuf);
		end else begin
			inQ1.deq;
			outQ.enq(inQ1.first);
		end
	endrule
	rule ff2 (!isValid(inQ1.first) && isValid(inQ2.first));
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(tagged Valid abuf);
		end else begin
			inQ2.deq;
			outQ.enq(inQ2.first);
		end
	endrule

	//Reg#(Vector#(vcnt,inType)) topReg <- mkReg(?);
	//Reg#(Vector#(vcnt,inType)) botReg <- mkReg(?);
	Reg#(Tuple2#(keyType,valType)) tailReg1 <- mkReg(?);
	Reg#(Tuple2#(keyType,valType)) tailReg2 <- mkReg(?);
	Reg#(Bit#(1)) mergestate <- mkReg(0);

	rule doMerge ( isValid(inQ1.first) && isValid(inQ2.first) );
		Integer count = valueOf(vcnt);

		let d1_ = inQ1.first;
		let d1 = fromMaybe(?,d1_);
		//Bool valid1 = isValid(d1_);
		let d2_ = inQ2.first;
		let d2 = fromMaybe(?,d2_);
		//Bool valid2 = isValid(d2_);

		
		let tail1 = d1[count-1];
		let tail2 = d2[count-1];
		if ( isValid(append1) ) begin
			let is1 = fromMaybe(?, append1);
			if ( is1 ) begin
				d1 = abuf;
				tail1 = atail;
				inQ2.deq;
			end else begin
				d2 = abuf;
				tail2 = atail;
				inQ1.deq;
			end
		end else begin
			inQ1.deq;
			inQ2.deq;
		end


		let cleaned = halfCleanKV(d1,d2,descending);
		let top = tpl_1(cleaned);
		let bot = tpl_2(cleaned);
		abuf <= sortBitonicKV(bot, descending); 

		if ( descending ) begin
			if ( tail1 >= tail2 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
			end
		end else begin
			if ( tail2 >= tail1 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
			end
		end

		//$display( "doMerge" );
		outQ.enq(tagged Valid top);
	endrule

	rule sortOut;
		outQ.deq;
		let d = outQ.first;
		if ( isValid(d) ) begin
			outQ2.enq(tagged Valid sortBitonicKV(fromMaybe(?,d), descending));
		end else begin
			outQ2.enq(d);
		end
	endrule


	//TODO input MUST be sorted!
	method Action enq1(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
		inQ2.enq(data);
	endmethod

	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
		outQ2.deq;
		return outQ2.first;
	endmethod
endmodule

interface StreamVectorMergeSorterEpIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
endinterface

interface StreamVectorMergeSorterIfc#(numeric type inCnt, numeric type vcnt, type keyType, type valType);
	interface Vector#(inCnt, StreamVectorMergeSorterEpIfc#(vcnt, keyType, valType)) enq;
	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
endinterface

module mkMergeSorter16#(Bool descending) (StreamVectorMergeSorterIfc#(16, vcnt, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Ord#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz)
	);


	Vector#(8, StreamVectorMergerIfc#(vcnt, keyType, valType)) merge0 <- replicateM(mkStreamVectorMerger(descending));
	Vector#(4, StreamVectorMergerIfc#(vcnt, keyType, valType)) merge1 <- replicateM(mkStreamVectorMerger(descending));
	Vector#(2, StreamVectorMergerIfc#(vcnt, keyType, valType)) merge2 <- replicateM(mkStreamVectorMerger(descending));
	StreamVectorMergerIfc#(vcnt, keyType, valType) merge3 <- mkStreamVectorMerger(descending);
	for (Integer i = 0; i < 8; i = i + 1) begin
		rule relay0;
			let d <- merge0[i].get;
			if ( i%2 == 0 ) begin
				merge1[i/2].enq1(d);
			end else begin
				merge1[i/2].enq2(d);
			end
		endrule
	end
	for (Integer i = 0; i < 4; i = i + 1) begin
		rule relay1;
			let d <- merge1[i].get;
			if ( i%2 == 0 ) begin
				merge2[i/2].enq1(d);
			end else begin
				merge2[i/2].enq2(d);
			end
		endrule
	end
	for (Integer i = 0; i < 2; i = i + 1) begin
		rule relay2;
			let d <- merge2[i].get;
			if ( i%2 == 0 ) begin
				merge3.enq1(d);
			end else begin
				merge3.enq2(d);
			end
		endrule
	end

	Vector#(16, StreamVectorMergeSorterEpIfc#(vcnt, keyType, valType)) enq_;
	for ( Integer i = 0; i < 16; i=i+1 ) begin
		enq_[i] = interface StreamVectorMergeSorterEpIfc;
			method Action enq(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
				if ( i%2 == 0 ) begin
					merge0[i/2].enq1(data);
				end else begin
					merge0[i/2].enq2(data);
				end
			endmethod
		endinterface: StreamVectorMergeSorterEpIfc;
	end

	interface enq = enq_;
	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
		let d <- merge3.get;
		return d;
	endmethod

endmodule


module mkMergeSorter8#(Bool descending) (StreamVectorMergeSorterIfc#(8, vcnt, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Ord#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz)
	);


	Vector#(4, StreamVectorMergerIfc#(vcnt, keyType, valType)) merge1 <- replicateM(mkStreamVectorMerger(descending));
	Vector#(2, StreamVectorMergerIfc#(vcnt, keyType, valType)) merge2 <- replicateM(mkStreamVectorMerger(descending));
	StreamVectorMergerIfc#(vcnt, keyType, valType) merge3 <- mkStreamVectorMerger(descending);
	for (Integer i = 0; i < 4; i = i + 1) begin
		rule relay1;
			let d <- merge1[i].get;
			if ( i%2 == 0 ) begin
				merge2[i/2].enq1(d);
			end else begin
				merge2[i/2].enq2(d);
			end
		endrule
	end
	for (Integer i = 0; i < 2; i = i + 1) begin
		rule relay2;
			let d <- merge2[i].get;
			if ( i%2 == 0 ) begin
				merge3.enq1(d);
			end else begin
				merge3.enq2(d);
			end
		endrule
	end

	Vector#(8, StreamVectorMergeSorterEpIfc#(vcnt, keyType, valType)) enq_;
	for ( Integer i = 0; i < 8; i=i+1 ) begin
		enq_[i] = interface StreamVectorMergeSorterEpIfc;
			method Action enq(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
				if ( i%2 == 0 ) begin
					merge1[i/2].enq1(data);
				end else begin
					merge1[i/2].enq2(data);
				end
			endmethod
		endinterface: StreamVectorMergeSorterEpIfc;
	end

	interface enq = enq_;
	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
		let d <- merge3.get;
		return d;
	endmethod

endmodule



