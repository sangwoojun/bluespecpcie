import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;
import DRAMBurstController::*;
import DRAMHostDMA::*;
import MergeN::*;

import DRAMVectorPacker::*;
import MergeSorter::*;

interface HwMainIfc;
endinterface

/*
function Tuple2#(Bit#(64),Bit#(32)) decodeTuple2_2_1(Bit#(96) in)
	;

	Bit#(64) keybits = truncate(in);
	Bit#(32) valbits = truncate(in>>64);

	return tuple2(keybits, valbits);
endfunction
*/
function Tuple2#(Bit#(ksz),Bit#(vsz)) decodeTuple2(Bit#(w) in)
	provisos(Add#(ksz,vsz,w)
	);

	Bit#(ksz) keybits = truncate(in>>valueOf(vsz));
	Bit#(vsz) valbits = truncate(in);

	return tuple2(keybits, valbits);
endfunction
/*
function Bit#(96) encodeTuple2_2_1(Tuple2#(Bit#(64),Bit#(32)) kvp);
	Bit#(64) keybits = tpl_1(kvp);
	Bit#(32) valbits = tpl_2(kvp);

	return {valbits,keybits};
endfunction
*/
function Bit#(w) encodeTuple2(Tuple2#(Bit#(ksz),Bit#(vsz)) kvp)
	provisos(Add#(ksz,vsz,w)
	);
	Bit#(ksz) keybits = tpl_1(kvp);
	Bit#(vsz) valbits = tpl_2(kvp);

	return {keybits,valbits};
endfunction


module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;


	DRAMBurstControllerIfc dramBurst <- mkDRAMBurstController(dram);
	DRAMHostDMAIfc dramHostDma <- mkDRAMHostDMA(pcie, dramBurst);
	Vector#(8, DRAMVectorUnpacker#(3,Bit#(96))) dramReaders <- replicateM(mkDRAMVectorUnpacker(dramHostDma.dram, 128));
	DRAMVectorPacker#(3,Bit#(96)) dramWriter <- mkDRAMVectorPacker(dramHostDma.dram, 128);
	StreamVectorMergeSorterIfc#(8, 3, Bit#(64), Bit#(32)) sorter8 <- mkMergeSorter8(False);

	FIFOF#(Bit#(32)) sampleQ <- mkSizedFIFOF(32);
	FIFOF#(Bit#(32)) sampleQ2 <- mkSizedFIFOF(32);

	//MergeNIfc#(8,Vector#(3,Tuple2#(Bit#(64),Bit#(32)))) tmerge <- mkMergeN;

	Vector#(8, Reg#(Bit#(32))) dramReadCnt <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 8; i=i+1 ) begin
		rule relayInput;
			let d <- dramReaders[i].get;

			if ( !isValid(d) ) begin
				dramReadCnt[i] <= dramReadCnt[i] | (1<<31);
				sorter8.enq[i].enq(tagged Invalid);
			end else begin
				Vector#(3,Bit#(96)) v = fromMaybe(?,d);
				Vector#(3,Tuple2#(Bit#(64),Bit#(32))) vv = map(decodeTuple2,v);
			
				sorter8.enq[i].enq(tagged Valid vv);
				dramReadCnt[i] <= dramReadCnt[i] + 1;

/*
			
				if ( i == 0 ) begin
					if ( sampleQ.notFull ) sampleQ.enq(truncate(tpl_1(vv[0])));
					if ( sampleQ2.notFull ) sampleQ2.enq(tpl_2(vv[0]));
				end
*/
			end
		endrule
	end
	

	Reg#(Bool) doneReached <- mkReg(False);
	Reg#(Bit#(64)) sortedCnt <- mkReg(0);

	rule getMerged;
		let r <- sorter8.get;

		if ( !isValid(r) ) begin
			doneReached <= True;
			dramWriter.put(tagged Invalid);
		end else begin
			sortedCnt <= sortedCnt + 1;
			doneReached <= False;
			dramWriter.put(tagged Valid map(encodeTuple2, fromMaybe(?,r)));

			let v = fromMaybe(?,r);
			let vv = v[0];

			if ( sampleQ.notFull ) sampleQ.enq(truncate(tpl_1(vv)));
			if ( sampleQ2.notFull ) sampleQ2.enq(tpl_2(vv));
			//Bit#(32) rr = {0,tpl_1(vv)[39:32],tpl_1(vv)[15:0],tpl_2(vv)[7:0]};
			//if ( sampleQ.notFull ) sampleQ.enq(rr);
		end
	endrule

	FIFO#(Bit#(64)) writeBufferDoneBytesQ <- mkSizedFIFO(16);
	MergeNIfc#(9, Bit#(8)) mBufferDone <- mkMergeN;
	for (Integer i = 0; i < 8; i=i+1 ) begin
		rule relayReadDone;
			dramReaders[i].bufferDone;
			mBufferDone.enq[i].enq(fromInteger(i));
		endrule
	end
	rule relayWriteDone;
		let bytes <- dramWriter.bufferDone;
		mBufferDone.enq[8].enq(8);
		writeBufferDoneBytesQ.enq(bytes);
	endrule
	FIFOF#(Bit#(8)) mergedQ <- mkFIFOF;
	rule relayMergedQ;
		mBufferDone.deq;
		mergedQ.enq(mBufferDone.first);
	endrule


	Vector#(4, Reg#(Bit#(32))) cmdArgs <- replicateM(mkReg(0));
	rule getCmd;
		IOWrite r <- dramHostDma.dataReceive;
		let a = r.addr;
		let d = r.data;
		let off = ( a>>2 );

		if ( off < 4 ) begin // args
			cmdArgs[off] <= d;
		end else if ( off == 8 ) begin
			dramWriter.addBuffer({cmdArgs[0], cmdArgs[1]}, cmdArgs[2]);
		end else if ( off == 9 ) begin
			dramReaders[d].addBuffer({cmdArgs[0], cmdArgs[1]}, cmdArgs[2], False);
			//doneReached <= False;
		end
	endrule

	rule getStatus;
		IOReadReq r <- dramHostDma.dataReq;
		let a = r.addr;
		let off = (a>>2);
		if ( off == 0 ) begin
			dramHostDma.dataSend(r, truncate(sortedCnt));
		end else if ( off == 1 ) begin
			dramHostDma.dataSend(r, doneReached?1:0);
		end else if ( off < 10 ) begin
			dramHostDma.dataSend(r, dramReadCnt[off-2]);
		end else if ( off == 10 ) begin
			if ( sampleQ.notEmpty ) begin
				sampleQ.deq;
				dramHostDma.dataSend(r, sampleQ.first);
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 11 ) begin
			if ( sampleQ2.notEmpty ) begin
				sampleQ2.deq;
				dramHostDma.dataSend(r, sampleQ2.first);
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 16 ) begin
			if ( mergedQ.notEmpty ) begin
				mergedQ.deq;
				dramHostDma.dataSend(r, zeroExtend(mergedQ.first));
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 17 ) begin
			let d = writeBufferDoneBytesQ.first;
			writeBufferDoneBytesQ.deq;
			dramHostDma.dataSend(r, truncate(d));
		end else begin
			dramHostDma.dataSend(r, 32'hffffffff);
		end
	endrule

endmodule
