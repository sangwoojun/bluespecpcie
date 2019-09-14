package SortReduceSingle;

import Vector::*;
import FIFO::*;
import BRAMFIFO::*;

import MergeN::*;
import Serializer::*;

import BurstIOArbiter::*;
import MergeSortReducerSingle::*;
import DramStripeLoader::*;

interface SortReduceSingleIfc;
	method Action command(Bit#(8) target, Bit#(32) dramOff, Bit#(32) dramLimit, Bit#(32) stripewords);
	method ActionValue#(Tuple3#(Bool, Bit#(32), Bit#(16))) getBurstReq; // Write? Offset, Words
	method ActionValue#(Bit#(512)) getData;
	method Action putData(Bit#(512) data);

	method ActionValue#(Bit#(32)) debug;
endinterface


typedef 16 EndpointCnt;

(* synthesize *)
module mkSortReduceSingle (SortReduceSingleIfc);
	BurstIOArbiterIfc#(TAdd#(1,EndpointCnt), Bit#(512)) dramArbiter <- mkBurstIOArbiter;
	Vector#(EndpointCnt, DramStripeLoaderIfc) loaders <- replicateM(mkDramStripeLoader((1024*3)/64,1024/64));
	MergeSortReducerSingleIfc#(EndpointCnt, Bit#(32), Bit#(32)) sortreducer <- mkMergeSortReducerSingle;

	//target, dramOff, stripewords, dramLimit
	Vector#(EndpointCnt, FIFO#(Tuple4#(Bit#(8), Bit#(32), Bit#(32), Bit#(32)))) loadCmdQ <- replicateM(mkFIFO);

	for (Integer i = 0; i < valueOf(EndpointCnt); i=i+1 ) begin
		rule connectLoadCmd;
			loadCmdQ[i].deq;
			let c = loadCmdQ[i].first;
			if ( fromInteger(i) != tpl_1(c) && i+1 < valueOf(EndpointCnt) ) loadCmdQ[i+1].enq(c);

			if ( fromInteger(i) == tpl_1(c) ) begin
				let off = tpl_2(c); let words = tpl_3(c); let limit = tpl_4(c);
				loaders[i].command(off,words,limit);
			end

		endrule
		rule connectDramLoader;
			let r <- loaders[i].getBurstReadReq;
			dramArbiter.eps[i].burstRead(tpl_1(r), tpl_2(r));
			$display( "DRAM Burst read req from %d -- %d %d", i, tpl_1(r), tpl_2(r) );
		endrule
		rule connectDramLoaded;
			let d <- dramArbiter.eps[i].getData;
			loaders[i].putData(d);
			$display( "DRAM read to %d", i );
		endrule
		SerializerIfc#(512, 8) srSer <- mkSerializer;
		FIFO#(Bool) srLastSer <- mkStreamSerializeLast(8);
		rule connectSR;
			let d_ <- loaders[i].getData;
			srSer.put(tpl_1(d_));
			srLastSer.enq(tpl_2(d_));
		endrule
		rule feedSR;
			let d <- srSer.get;
			let l = srLastSer.first;
			srLastSer.deq;
			sortreducer.enq[i].enq(d[63:32], d[31:0], l);
		endrule
	end

	FIFO#(Bit#(512)) outBufferQ <- mkSizedBRAMFIFO((1024*8)/64);
	DeSerializerIfc#(64,8) outDes <- mkDeSerializer;
	FIFO#(Bool) doneQ <- mkFIFO; //FIXME temporary
	Reg#(Bit#(32)) mergedonecount <- mkReg(0);
	Reg#(Bit#(32)) writeIn <- mkReg(0);
	Reg#(Bit#(32)) writeOut <- mkReg(0);
	rule bufferOutDes;
		let r <- sortreducer.get;
		outDes.put({tpl_1(r),tpl_2(r)});
		if ( tpl_3(r) ) begin
			doneQ.enq(True);
			$display( "Merge done %d", mergedonecount );
			mergedonecount <= mergedonecount + 1;
		end
	endrule
	rule bufferOut;
		let o <- outDes.get;
		outBufferQ.enq(o);
		writeIn <= writeIn + 1;
		
		if ( writeIn - writeOut > 1024*2/64 ) begin
			writeOut <= writeOut + (1024*2/64);
			dramArbiter.eps[16].burstWrite(0,1024*2/64);
		end
	endrule
	rule feedArbiterOut;
		dramArbiter.eps[16].putData(outBufferQ.first);
		outBufferQ.deq;
		$display( "Data out!" );
	endrule

	method Action command(Bit#(8) target, Bit#(32) dramOff, Bit#(32) dramLimit, Bit#(32) stripewords);
		loadCmdQ[0].enq(tuple4(target, dramOff, stripewords, dramLimit));
	endmethod

	method ActionValue#(Tuple3#(Bool, Bit#(32), Bit#(16))) getBurstReq; // Write? Offset, Words
		let b <- dramArbiter.getBurstReq;
		return b;
	endmethod
	method ActionValue#(Bit#(512)) getData;
		let d <- dramArbiter.getData;
		return d;
	endmethod
	method Action putData(Bit#(512) data);
		dramArbiter.putData(data);
	endmethod
	
	method ActionValue#(Bit#(32)) debug;
		doneQ.deq;
		return 1;
	endmethod
endmodule

endpackage: SortReduceSingle
