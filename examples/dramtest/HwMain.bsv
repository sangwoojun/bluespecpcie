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

	Reg#(Bit#(32)) wordReadLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) wordWriteLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) wordWriteReq <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dramWriteLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dramReadLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dramWriteStartCycle <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dramWriteEndCycle <- mkReg(0, clocked_by pcieclk, reset_by pcierst);

	Reg#(Bit#(32)) cycles <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule incCycle;
		cycles <= cycles + 1;
	endrule


	rule getCmd ( wordWriteLeft == 0 );
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		let off = (a>>2);
		if ( off == 0 ) begin
			wordWriteLeft <= d;
			wordWriteReq <= d;
			pcie.dmaWriteReq( 0, truncate(d), 0 ); // offset, words, tag
		end else if ( off == 1 ) begin
			pcie.dmaReadReq( 0, truncate(d), 1 ); // offset, words, tag
			wordReadLeft <= wordReadLeft + d;
		end else if ( off == 2 ) begin
			dramWriteLeft <= d;
			dramWriteStartCycle <= cycles;
		end else if ( off == 3 ) begin
			dramReadLeft <= d;
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
	Reg#(Bit#(512)) dramReadVal <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule dramReadResp;
		let d <- dram.read;
		dramReadVal <= d;
	endrule

	Reg#(DMAWord) lastRecvWord <- mkReg(0, clocked_by pcieclk, reset_by pcierst);

	rule recvDMAData;
		DMAWordTagged rd <- pcie.dmaReadWord;
		wordReadLeft <= wordReadLeft - 1;
		lastRecvWord <= rd.word;
	endrule

	Reg#(Bit#(32)) writeData <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule sendDMAData ( wordWriteLeft > 0 );
		pcie.dmaWriteData({writeData+3,writeData+2,writeData+1,writeData}, 0);
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
			let noff = (offset-3)*32;
			//pcie.dataSend(r, pcie.debug_data);
			pcie.dataSend(r, truncate(dramReadVal>>noff));
		end
	endrule

endmodule
