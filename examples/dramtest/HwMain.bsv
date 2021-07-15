import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	//DMASplitterIfc#(4) dma <- mkDMASplitter(pcie);

	Reg#(Bit#(32)) cycles <- mkReg(0);
	rule incCycle;
		cycles <= cycles + 1;
	endrule

	FIFO#(Tuple2#(Bit#(16),Bit#(16))) dramReadReqQ <- mkSizedBRAMFIFO(1024); // offset, words
	Reg#(Bit#(16)) dramReadReqCnt <- mkReg(0);
	Reg#(Bit#(16)) dramReadReqDone <- mkReg(0);
	Reg#(Bit#(16)) dramReqWordLeft <- mkReg(0);
	Reg#(Bit#(16)) dramReqWordOff <- mkReg(0);
	Reg#(Bit#(32)) startCycle <- mkReg(0);
	Reg#(Bit#(32)) elapsedCycle <- mkReg(0);
	rule startDRAMRead(dramReadReqCnt >= 1024 && dramReqWordLeft == 0);
		let r = dramReadReqQ.first;
		dramReadReqQ.deq;
		dramReqWordLeft <= tpl_2(r);
		dramReqWordOff <= tpl_1(r);
		dramReadReqDone <= dramReadReqDone + 1;
		if ( dramReadReqDone == 0 ) startCycle <= cycles;
	endrule
	FIFO#(Bool) isLastQ <- mkSizedFIFO(64);
	rule issueDRAMRead (dramReqWordLeft > 0 );
		dramReqWordLeft <= dramReqWordLeft -1;
		dramReqWordOff <= dramReqWordOff + 1;
		dram.readReq(zeroExtend(dramReqWordOff)*64, 64);
		if ( dramReqWordLeft == 1 && dramReadReqDone == dramReadReqCnt ) isLastQ.enq(True);
		else isLastQ.enq(False);
	endrule
	rule procDRAMRead;
		let d <- dram.read;
		isLastQ.deq;
		if ( isLastQ.first ) elapsedCycle <= cycles-startCycle;
	endrule


	Reg#(Bit#(32)) wordReadLeft <- mkReg(0);
	Reg#(Bit#(32)) wordWriteLeft <- mkReg(0);
	Reg#(Bit#(32)) wordWriteReq <- mkReg(0);
	Reg#(Bit#(32)) dramWriteLeft <- mkReg(0);
	Reg#(Bit#(32)) dramReadLeft <- mkReg(0);
	Reg#(Bit#(32)) dramWriteStartCycle <- mkReg(0);
	Reg#(Bit#(32)) dramWriteEndCycle <- mkReg(0);



	rule getCmd ( wordWriteLeft == 0 );
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		let off = (a>>2);
		if ( off == 0 ) begin
			wordWriteLeft <= d;
			wordWriteReq <= d;
			pcie.dmaWriteReq( 0, truncate(d)); // offset, words
		end else if ( off == 1 ) begin
			pcie.dmaReadReq( 0, truncate(d)); // offset, words
			wordReadLeft <= wordReadLeft + d;
		end else if ( off == 2 ) begin
			dramWriteLeft <= d;
			dramWriteStartCycle <= cycles;
		end else if ( off == 3 ) begin
			dramReadReqQ.enq(tuple2(truncate(d>>16), truncate(d)));
			dramReadReqCnt <= dramReadReqCnt + 1;
		end
	endrule

	rule dramWrite( dramWriteLeft > 0 );
		dramWriteLeft <= dramWriteLeft - 1;
		Bit#(128) v0 = 128'h11112222333344445555666600000000 | zeroExtend(dramWriteLeft);
		Bit#(128) v1 = 128'hcccccccccccccccccccccccc00000000 | zeroExtend(dramWriteLeft);
		Bit#(128) v2 = 128'hdeadbeefdeadbeeddeadbeef00000000 | zeroExtend(dramWriteLeft);
		Bit#(128) v3 = 128'h88887777666655554444333300000000 | zeroExtend(dramWriteLeft);

		dram.write(zeroExtend(dramWriteLeft)*64, {v0,v1,v2,v3},64);
		if ( dramWriteLeft == 1 ) begin
			dramWriteEndCycle <= cycles;
		end
	endrule

	rule dramReadReq ( dramReadLeft > 0 );
		dramReadLeft <= dramReadLeft - 1;

		dram.readReq(zeroExtend(dramReadLeft)*64, 64);
	endrule
	Reg#(Bit#(512)) dramReadVal <- mkReg(0);
	rule dramReadResp;
		let d <- dram.read;
		dramReadVal <= d;
	endrule

	Reg#(DMAWord) lastRecvWord <- mkReg(0);

	rule recvDMAData;
		wordReadLeft <= wordReadLeft - 1;
		let d <- pcie.dmaReadWord;
		lastRecvWord  <= d;
	endrule

	Reg#(Bit#(32)) writeData <- mkReg(0);
	rule sendDMAData ( wordWriteLeft > 0 );
		pcie.dmaWriteData({writeData+3,writeData+2,writeData+1,writeData});
		writeData <= writeData + 4;
		wordWriteLeft <= wordWriteLeft - 1;
	endrule

	rule readStat;
		let r <- pcie.dataReq;
		let a = r.addr;

		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let offset = (a>>2);
		if ( offset == 0 ) begin
			//pcie.dataSend(r, wordWriteLeft);
			pcie.dataSend(r, dramWriteLeft);
		end else if ( offset == 1 ) begin
			//pcie.dataSend(r, wordWriteReq);
			pcie.dataSend(r, dramReadLeft);
		end else if ( offset == 2 ) begin
			//pcie.dataSend(r, wordReadLeft);
			pcie.dataSend(r, dramWriteEndCycle-dramWriteStartCycle);
		end else begin
			//let noff = (offset-3)*32;
			//pcie.dataSend(r, pcie.debug_data);
			//pcie.dataSend(r, truncate(dramReadVal>>noff));
			pcie.dataSend(r, elapsedCycle);

		end
	endrule

endmodule
