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
	method Action outCommand(Bit#(32) stripeoff, Bit#(32) dramLimit, Bit#(32) stripewords);
	method ActionValue#(Tuple3#(Bool, Bit#(32), Bit#(16))) getBurstReq; // Write? Offset, Words
	method ActionValue#(Bit#(512)) getData;
	method Action putData(Bit#(512) data);

	method ActionValue#(Bit#(512)) getOverflow;

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
			//$display( "DRAM read to %d", i );
		endrule
		SerializerIfc#(512, 8) srSer <- mkSerializer;
		FIFO#(Bool) srLastSer <- mkStreamSerializeLast(8);
		rule connectSR;
			let d_ <- loaders[i].getData;
			srSer.put(tpl_1(d_));
			srLastSer.enq(tpl_2(d_));
		endrule
		Reg#(Maybe#(Tuple2#(Bit#(32),Bit#(32)))) staggerInBuffer <- mkReg(tagged Invalid);
		Reg#(Bool) skippingStream <- mkReg(False);
		Reg#(Bool) flushLast <- mkReg(False);
		rule skipInData (skippingStream && !flushLast);
			let d <- srSer.get;
			let l = srLastSer.first;
			srLastSer.deq;
			//$display( "input skipping %d", i );
			if ( l ) begin
				skippingStream <= False;
				//$display( "input skip done %d", i );
			end
		endrule
		rule flushLastR (flushLast);
			let ld = fromMaybe(?,staggerInBuffer);
			sortreducer.enq[i].enq(tpl_1(ld), tpl_2(ld), True);
			flushLast <= False;
			staggerInBuffer <= tagged Invalid;
		endrule
		rule feedSR (!skippingStream && !flushLast);
			let d <- srSer.get;
			let l = srLastSer.first;
			srLastSer.deq;

			let key = d[63:32];
			let val = d[31:0];
			if ( key == 32'hffffffff && val == 32'hffffffff ) begin 
				//TODO change null to \0, \0 after some data
				//ERROR if first element is null
				// skip until we get a "last"
				skippingStream <= True;
				let ld = fromMaybe(?,staggerInBuffer);
				sortreducer.enq[i].enq(tpl_1(ld), tpl_2(ld), True);
				staggerInBuffer <= tagged Invalid;
				$display ( "SR input found stripe delimiter at %d", i );
			end
			else if ( isValid(staggerInBuffer) ) begin
				//sortreducer.enq[i].enq(d[63:32], d[31:0], l);
				let ld = fromMaybe(?,staggerInBuffer);
				sortreducer.enq[i].enq(tpl_1(ld), tpl_2(ld), False);
				staggerInBuffer <= tagged Valid tuple2(key,val);
				//$display( "input replace stagger %d", i );
				if ( l ) begin
					flushLast <= True;
				end
			end else begin
				staggerInBuffer <= tagged Valid tuple2(key,val);
				//$display( "input stagger %d", i );
			end
			
		endrule
	end

	FIFO#(Bit#(512)) outBufferQ <- mkSizedBRAMFIFO((1024*8)/64);
	DeSerializerIfc#(64,8) outDes <- mkDeSerializer;
	FIFO#(Bool) doneQ <- mkFIFO; //FIXME temporary
	Reg#(Bit#(32)) mergedonecount <- mkReg(0);
	Reg#(Bit#(32)) writeIn <- mkReg(0);
	Reg#(Bit#(32)) writeOut <- mkReg(0);
	Reg#(Bool) appendNullOut <- mkReg(False);

	Reg#(Bit#(3)) desIdx <- mkReg(0);
	Reg#(Bit#(3)) desPadIdx <- mkReg(0);
	rule padOutputDes (desPadIdx > 0);
		outDes.put({32'hffffffff,32'hffffffff});
		desPadIdx <= desPadIdx + 1;
	endrule
	rule appendNullOutR (appendNullOut && desPadIdx == 0);
		outDes.put({32'hffffffff,32'hffffffff});
		appendNullOut <= False;
		desIdx <= 0;
		desPadIdx <= desIdx + 1;
	endrule
	rule bufferOutDes (!appendNullOut && desPadIdx == 0);
		let r <- sortreducer.get;
		outDes.put({tpl_1(r),tpl_2(r)});
		desIdx <= desIdx + 1;

		if ( tpl_3(r) ) begin
			doneQ.enq(True);
			$display( "Merge done %d", mergedonecount );
			mergedonecount <= mergedonecount + 1;
			appendNullOut <= True;
		end
	endrule
	Reg#(Bit#(32)) outWriteOff <- mkReg(0); 
	Reg#(Bit#(32)) curStripeBase <- mkReg(0); 
	Reg#(Bit#(32)) outStripeSz <- mkReg(0); 
	Reg#(Bit#(32)) outDramLimit <- mkReg(0);
	FIFO#(Bit#(512)) overflowQ <- mkFIFO;
	Reg#(Bool) genDramBurstReq <- mkReg(False);
	Reg#(Bool) skipToNextOutStripe <- mkReg(False);

	rule skipToNextOutStripeR (skipToNextOutStripe == True);
		skipToNextOutStripe <= False;
		writeOut <= writeIn;
		dramArbiter.eps[16].burstWrite(curStripeBase+outWriteOff,truncate(writeIn-writeOut));
		outWriteOff <= 0;
		curStripeBase <= curStripeBase + outStripeSz;
		$display( "Skipping block since we encountered a null -> %x %d", curStripeBase + outStripeSz, outWriteOff);
	endrule
	rule genDramBurstRegR (genDramBurstReq == True);
		genDramBurstReq <= False;
		writeOut <= writeOut + (1024*2/64);
		dramArbiter.eps[16].burstWrite(curStripeBase+outWriteOff,1024*2/64);
		if ( outWriteOff + (1024*2/64) >= outStripeSz ) begin
			outWriteOff <= 0;
			curStripeBase <= curStripeBase + outStripeSz;
			$display( "Done writing to stripe -> %x", curStripeBase + outStripeSz);
		end else begin
			outWriteOff <= outWriteOff + (1024*2/64);
			$display( "Done writing to block -> %x", curStripeBase);
		end
	endrule
	rule bufferOut(skipToNextOutStripe == False && genDramBurstReq == False);
		let o <- outDes.get;
		if ( curStripeBase >= outDramLimit ) begin
			overflowQ.enq(o);
			$display("Entering overflow!" );
		end else if ( writeIn+1 - writeOut >= 1024*2/64 ) begin
			outBufferQ.enq(o);
			genDramBurstReq <= True;
			writeIn <= writeIn + 1;
			$display( "Generating burst write req" );
		end else if ( o[511:512-64] == 64'hffffffffffffffff ) begin
			//if MSB is h32'hffffffff, 32'hffffffff, send partial write and then skip to next block
			if (outWriteOff > 0 ) begin // if there was no reduction, null is at beginning of stripe...
				outBufferQ.enq(o);
				writeIn <= writeIn + 1;
				skipToNextOutStripe <= True;
			end
			$display( "delimeter output at %d", outWriteOff );
		end else begin
			outBufferQ.enq(o);
			writeIn <= writeIn + 1;
			$display("outBufferQ %d", writeIn-writeOut);
		end
	endrule


	rule feedArbiterOut;
		dramArbiter.eps[16].putData(outBufferQ.first);
		outBufferQ.deq;
		//$display( "Data out!" );
	endrule

	method Action command(Bit#(8) target, Bit#(32) dramOff, Bit#(32) dramLimit, Bit#(32) stripewords);
		loadCmdQ[0].enq(tuple4(target, dramOff, stripewords, dramLimit));
	endmethod
	method Action outCommand(Bit#(32) stripeoff, Bit#(32) dramLimit, Bit#(32) stripewords) if ( curStripeBase >= outDramLimit);
		outWriteOff <= 0;
		curStripeBase <= stripeoff;
		outStripeSz <= stripewords;
		outDramLimit <= dramLimit;
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
	method ActionValue#(Bit#(512)) getOverflow;
		overflowQ.deq;
		return overflowQ.first;
	endmethod
	
	method ActionValue#(Bit#(32)) debug;
		doneQ.deq;
		return 1;
	endmethod
endmodule

endpackage: SortReduceSingle
