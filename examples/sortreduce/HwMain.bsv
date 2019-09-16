import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;

import SortReduceSingle::*;
import Serializer::*;

interface HwMainIfc;
endinterface


module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) 
	(HwMainIfc);

	// Current clock/reset is pcieclk/rst (250MHz)
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	//DMASplitterIfc#(4) dma <- mkDMASplitter(pcie);

	SortReduceSingleIfc sr1 <- mkSortReduceSingle;

	Reg#(Bit#(32)) cycles <- mkReg(0);
	rule incCycle;
		cycles <= cycles + 1;
	endrule

	Reg#(Bit#(32)) overflowCnt <- mkReg(0);
	rule getSr1overflow;
		let o <-sr1.getOverflow;
		overflowCnt <= overflowCnt + 1;
	endrule

	/////////////////////// dram connection
	Reg#(Bit#(32)) curDRAMBurstOffset <- mkReg(0);
	Reg#(Bit#(16)) curDRAMBurstLeft <- mkReg(0);
	Reg#(Bool) curDRAMBurstWrite <- mkReg(False);
	rule relayBurstReq ( curDRAMBurstLeft == 0 );
		let r <- sr1.getBurstReq;
		curDRAMBurstWrite <= tpl_1(r);
		curDRAMBurstOffset <= tpl_2(r);
		curDRAMBurstLeft <= tpl_3(r);
		//$display( "DRAM burst read started %d %d %d", tpl_1(r), tpl_2(r), tpl_3(r) );
	endrule
	rule sendDRAMCmd(curDRAMBurstLeft > 0);
		//$display( "DRAM read req %d", curDRAMBurstLeft );

		curDRAMBurstLeft <= curDRAMBurstLeft - 1;
		curDRAMBurstOffset <= curDRAMBurstOffset + 1;
		if ( curDRAMBurstWrite ) begin
			let d <- sr1.getData;
			dram.write(zeroExtend(curDRAMBurstOffset)*64, d, 64);
		end else begin
			dram.readReq(zeroExtend(curDRAMBurstOffset)*64, 64);
		end
	endrule
	rule relayDRAMRead;
		let d <- dram.read;
		sr1.putData(d);
		//$display( "DRAM burst read data" );
	endrule


	/////////////////
	Reg#(Bit#(32)) startCycle <- mkReg(0);
	Reg#(Bit#(32)) endCycle <- mkReg(0);
	Reg#(Bit#(32)) doneCnt <- mkReg(0);
	rule getDone;
		let r <- sr1.debug;
		endCycle <= cycles-startCycle;
		doneCnt <= doneCnt + 1;
	endrule

	rule readStat;
		let r <- pcie.dataReq;
		let a = r.addr;

		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let offset = (a>>2);
		if ( offset == 0 ) pcie.dataSend(r, endCycle);
		else if ( offset == 1 ) pcie.dataSend(r, doneCnt);
		else if ( offset == 2 ) pcie.dataSend(r, overflowCnt);
	endrule


	Reg#(Bit#(32)) dramWriteOff <- mkReg(0);
	DeSerializerIfc#(32,16) dramWDes <- mkDeSerializer;
	Vector#(3,Reg#(Bit#(32))) inputArgs <- replicateM(mkReg(0));
	rule fillDRAM( curDRAMBurstLeft == 0 );
		let d <- dramWDes.get;
		dram.write(zeroExtend(dramWriteOff), d, 64);
		dramWriteOff <= dramWriteOff + 64;
	endrule
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) dramWriteCmdQ <- mkFIFO;
	rule dramWriteCmd;
		let w = dramWriteCmdQ.first;
		dramWriteCmdQ.deq;
		let d = tpl_2(w);
		let off = tpl_1(w);
		if ( off == 5 ) begin
			dramWDes.put(d);
		end
		else if ( off == 6 ) begin
			dramWriteOff <= d;
		end
	endrule
	rule getCmd;
		// dma load from host
		// dma write to host
		// start sortreduce sweep 
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		let off = (a>>2);
		if ( off < 3 ) inputArgs[off] <= d;
		else if ( off == 3 ) begin
			sr1.command(truncate(inputArgs[0]), inputArgs[1], inputArgs[2], d);
			startCycle <= cycles;
			endCycle <= 0;
			doneCnt <= 0;
		end
		else if ( off == 4 ) begin
			sr1.outCommand(inputArgs[0], inputArgs[1], d);
		end
		else begin
			dramWriteCmdQ.enq(tuple2(zeroExtend(off),d));
		end
	endrule


endmodule
