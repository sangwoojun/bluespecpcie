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

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;


	DRAMBurstControllerIfc dramBurst <- mkDRAMBurstController(dram);
	DRAMHostDMAIfc dramHostDma <- mkDRAMHostDMA(pcie, dramBurst);
	Vector#(8, DRAMVectorUnpacker#(3,Tuple2#(Bit#(64),Bit#(32)))) dramReaders <- replicateM(mkDRAMVectorUnpacker(dramBurst, 128));
	
	StreamVectorMergeSorterIfc#(8, 3, Bit#(64), Bit#(32)) sorter8 <- mkMergeSorter8(False);

	Vector#(8, Reg#(Bit#(32))) dramReadCnt <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 8; i=i+1 ) begin
		rule relayInput;
			let d <- dramReaders[i].get;
			sorter8.enq[i].enq(d);
			if ( !isValid(d) ) begin
				dramReadCnt[i] <= dramReadCnt[i] | (1<<31);
			end else begin
				dramReadCnt[i] <= dramReadCnt[i] + 1;
			end
		endrule
	end
	
	DRAMVectorPacker#(3,Tuple2#(Bit#(64),Bit#(32))) dramWriter <- mkDRAMVectorPacker(dramBurst, 128);

	Reg#(Bool) doneReached <- mkReg(False);
	Reg#(Bit#(64)) sortedCnt <- mkReg(0);
	rule getMerged;
		let r <- sorter8.get;
		dramWriter.put(r);

		if ( !isValid(r) ) begin
			doneReached <= True;
		end else begin
			sortedCnt <= sortedCnt + 1;
			doneReached <= False;
		end
	endrule

	MergeNIfc#(9, Bit#(8)) mBufferDone <- mkMergeN;
	for (Integer i = 0; i < 8; i=i+1 ) begin
		rule relayReadDone;
			dramReaders[i].bufferDone;
			mBufferDone.enq[i].enq(fromInteger(i));
		endrule
	end
	rule relayWriteDone;
		mBufferDone.enq[8].enq(8);
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
		end
		else if ( off < 10 ) begin
			dramHostDma.dataSend(r, dramReadCnt[off-2]);
		end else if ( off == 16 ) begin
			mBufferDone.deq;
			dramHostDma.dataSend(r, zeroExtend(mBufferDone.first));
		end else begin
			dramHostDma.dataSend(r, 32'hffffffff);
		end
	endrule

endmodule
