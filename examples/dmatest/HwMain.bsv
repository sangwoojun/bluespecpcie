import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;


interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;


	Reg#(Bit#(32)) wordReadLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) wordWriteLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) wordWriteReq <- mkReg(0, clocked_by pcieclk, reset_by pcierst);

	rule getCmd ( wordWriteLeft == 0 );
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		let off = (a>>2);
		if ( off == 0 ) begin
			wordWriteLeft <= d;
			wordWriteReq <= d;
			pcie.dmaWriteReq( 0, truncate(d) ); // offset, words
		end else if ( off == 1 ) begin
			pcie.dmaReadReq( 0, truncate(d)); // offset, words
			wordReadLeft <= wordReadLeft + d;
		end
	endrule

	Reg#(DMAWord) lastRecvWord <- mkReg(0, clocked_by pcieclk, reset_by pcierst);

	rule recvDMAData;
		let rd <- pcie.dmaReadWord;
		wordReadLeft <= wordReadLeft - 1;
		lastRecvWord <= rd;
	endrule

	Reg#(Bit#(32)) writeData <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
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
			pcie.dataSend(r, wordWriteLeft);
		end else if ( offset == 1 ) begin
			pcie.dataSend(r, wordWriteReq);
		end else if ( offset == 2 ) begin
			pcie.dataSend(r, wordReadLeft);
		end else begin
			let noff = (offset-3)*32;
			//pcie.dataSend(r, pcie.debug_data);
			pcie.dataSend(r, truncate(lastRecvWord>>noff));
		end
	endrule

endmodule
