import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import ScatterN::*;

import MergeSorter::*;
import SortingNetwork::*;

/**
**/


interface SingleMergerKVIfc#(type keyType, type valType, numeric type cntSz);
	method Action enq1(Tuple2#(keyType,valType) data);
	method Action enq2(Tuple2#(keyType,valType) data);
	method Action runMerge(Bit#(cntSz) count);
	method ActionValue#(Tuple2#(keyType,valType)) get;
endinterface

module mkSingleMergerKV#(Bool descending) (SingleMergerIfc#(keyType,valType, cntSz))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Ord#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz)
	);

	Reg#(Bit#(cntSz)) mCountTotal <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount1 <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount2 <- mkReg(0);

	FIFO#(Tuple2#(keyType,valType)) inQ1 <- mkFIFO;
	FIFO#(Tuple2#(keyType,valType)) inQ2 <- mkFIFO;

	FIFO#(Tuple2#(keyType,valType)) outQ <- mkFIFO;

	rule ff1 (mCount1 > 0 && mCount2 == 0);
		mCountTotal <= mCountTotal - 1;
		inQ1.deq;
		outQ.enq(inQ1.first);
		mCount1 <= mCount1 - 1;
	endrule
	rule ff2 (mCount1 == 0 && mCount2 > 0);
		mCountTotal <= mCountTotal - 1;
		inQ2.deq;
		outQ.enq(inQ2.first);
		mCount2 <= mCount2 - 1;
	endrule
	rule doMerge (mCount1 > 0 && mCount2 > 0 );
		mCountTotal <= mCountTotal - 1;
		let d1 = inQ1.first;
		let d2 = inQ2.first;
		if ( descending ) begin
			if ( tpl_1(d1) > tpl_1(d2) ) begin
				outQ.enq(d1);
				inQ1.deq;
				mCount1 <= mCount1 -1;
			end else begin
				outQ.enq(d2);
				inQ2.deq;
				mCount2 <= mCount2 -1;
			end
		end else begin
			if ( tpl_1(d1) > tpl_1(d2) ) begin
				outQ.enq(d2);
				inQ2.deq;
				mCount2 <= mCount2 -1;
			end else begin
				outQ.enq(d1);
				inQ1.deq;
				mCount1 <= mCount1 -1;
			end
		end
	endrule

	method Action enq1(Tuple2#(keyType,valType) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Tuple2#(keyType,valType) data);
		inQ2.enq(data);
	endmethod
	method Action runMerge(Bit#(cntSz) count) if (mCountTotal == 0);
		mCountTotal <= count * 2;
		mCount1 <= count;
		mCount2 <= count;
	endmethod
	method ActionValue#(Tuple2#(keyType,valType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

interface PageSorterKVIfc#(type keyType, type valType, numeric type tupleCount, numeric type pageSz);
	method Action enq(Vector#(tupleCount,Tuple2#(keyType,valType)) data);
	method ActionValue#(Vector#(tupleCount,Tuple2#(keyType,valType))) get;
endinterface
/*

module mkPageSorterSingleKV#(Bool descending) (PageSorterKVIfc#(keyType,valType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	Integer iPageSz = valueOf(pageSz)
	Integer pageSize = 2**iPageSz;
	Integer iTupleCount = valueOf(tupleCount);

	SingleMergerIfc#(keyType,valType,16) merger <- mkSingleMerger(descending);

	Vector#(2,FIFO#(Vector#(tupleCount,Tuple2#(keyType,valType)))) buffers <- replicateM(mkSizedBRAMFIFO(pageSize/2));
	//Vector#(2, Reg#(Bit#(32))) bufferCntUp <- replicateM(mkReg(0));
	//Vector#(2, Reg#(Bit#(32))) bufferCntDown <- replicateM(mkReg(0));

	Reg#(Bit#(32)) curStride <- mkReg(0);
	Reg#(Bit#(32)) strideSum <- mkReg(0);

	FIFO#(Bit#(16)) cmdQ <- mkFIFO;
	rule genCmd (curStride > 0);
		//cmdQ.enq(curStride*fromInteger(tupleCount));
		Bit#(16) mergeStride = truncate(curStride*fromInteger(iTupleCount));
		merger.runMerge(mergeStride);
		//$display( "merger inserting command for stride %d (%d)", mergeStride, strideSum );

		if ( strideSum + curStride >= fromInteger(pageSize)/2 ) begin
			if ( curStride >= fromInteger(pageSize)/2 ) begin
				curStride <= 0;
			end else begin
				curStride <= (curStride<<1);
				strideSum <= 0;
			end
		end
		else begin
			strideSum <= strideSum + curStride;
		end
	endrule







	
	//Vector#(2,FIFO#(Vector#(tupleCount, inType))) insQ <- replicateM(mkFIFO);
	Vector#(2,Reg#(Bit#(32))) totalInsCount <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 2; i = i + 1 ) begin
		
		Reg#(Vector#(tupleCount, inType)) insBuf <- mkReg(?);
		Reg#(Bit#(8)) vecIdx <- mkReg(0);
		rule startInsertData ( totalInsCount[i] > 0 && vecIdx == 0);
			buffers[i].deq;
			//bufferCntDown[i] <= bufferCntDown[i] + 1;

			let d = buffers[i].first;
			insBuf <= d;
			if ( i == 0 ) merger.enq1(d[0]);
			else if ( i == 1 ) merger.enq2(d[0]);

			vecIdx <= fromInteger(iTupleCount)-1;
			totalInsCount[i] <= totalInsCount[i] - 1;
			//$display( "inserting data from %d", i );
		endrule
		rule insertData ( vecIdx > 0 );
			vecIdx <= vecIdx - 1;
			let idx = fromInteger(iTupleCount)-vecIdx;
			if ( i == 0 ) merger.enq1(insBuf[idx]);
			else if ( i == 1 ) merger.enq2(insBuf[idx]);
		endrule
	end


	
	//Reg#(Bit#(32)) curStrideOut <- mkReg(0);
	FIFO#(Vector#(tupleCount, inType)) readQ <- mkSizedBRAMFIFO(pageSize/2);
	Vector#(tupleCount, Reg#(inType)) readBuf <- replicateM(mkReg(0));
	Reg#(Bit#(8)) readIdx <- mkReg(0);
	rule readSorted;
		let d <- merger.get;
		if ( readIdx + 1 >= fromInteger(iTupleCount) ) begin
			Vector#(tupleCount, inType) readv;
			for ( Integer i = 0; i < iTupleCount; i=i+1) begin
				readv[i] = readBuf[i];
			end
			readv[iTupleCount-1] = d;
			readQ.enq(readv);
			readIdx <= 0;
		end else begin
			readBuf[readIdx] <= d;
			readIdx <= readIdx + 1;
		end
	endrule





	Reg#(Bit#(32)) curInsCount <- mkReg(0);
	Reg#(Bit#(32)) curInsStride <- mkReg(0);
	Reg#(Bit#(32)) insStrideCount <- mkReg(0);
	Reg#(Bit#(32)) totalReadCount <- mkReg(0);
	FIFO#(Vector#(tupleCount,Tuple2#(keyType,valType))) outQ <- mkFIFO;


	rule insData ( curInsStride > 0 );
		readQ.deq;
		let d = readQ.first;
		if ( curInsStride >= fromInteger(pageSize) ) begin
			outQ.enq(d);
		end else begin
			buffers[insStrideCount[0]].enq(d);
		end


		if ( curInsCount + 1 >= curInsStride ) begin
			curInsCount <= 0;
			insStrideCount <= insStrideCount + 1;
			//$display( "stride done" );
		end else begin
			curInsCount <= curInsCount + 1;
		end
		if ( totalReadCount + 1 >= fromInteger(pageSize) ) begin
			totalReadCount <= 0;
			if ( curInsStride >= fromInteger(pageSize) ) begin
				curInsStride <= 0;
				//$display("Finished sorting page");
			end else begin
				curInsStride <= (curInsStride<<1);
			end
		end else begin
			totalReadCount <= totalReadCount + 1;
		end

	endrule




	Reg#(Bit#(32)) enqIdx <- mkReg(0);
	//NOTE: data is assumed already sorted internally!
	method Action enq(Vector#(tupleCount,Tuple2#(keyType,valType)) data) if ( curInsStride == 0);
		//$display( "Sort enq" );
		buffers[enqIdx[0]].enq(data);
		//bufferCntUp[enqIdx[0]] <= bufferCntUp[enqIdx[0]] + 1;
		if ( enqIdx+1 < fromInteger(pageSize) ) begin
			enqIdx <= enqIdx + 1;
		end
		else begin
			curStride <= 1;
			totalInsCount[0] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			totalInsCount[1] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			curInsStride <= 2;
			enqIdx <= 0;
		end
	endmethod
	method ActionValue#(Vector#(tupleCount,Tuple2#(keyType,valType))) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

*/
