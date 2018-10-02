import Clocks::*;
import FIFO::*;
import BRAMFIFO::*;
import FIFOF::*;

import DRAMController::*;
import DRAMControllerTypes::*;

interface DRAMBurstControllerIfc;
	method Action writeReq(Bit#(64) addr, Bit#(32) words);
	method Action readReq(Bit#(64) addr, Bit#(32) words);
	method Action write(Bit#(512) word);
	method ActionValue#(Bit#(512)) read;
	
	interface Clock user_clk;
	interface Reset user_rst;
endinterface

module mkDRAMBurstController#(DRAMUserIfc dram) (DRAMBurstControllerIfc);
	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;

	Reg#(Bit#(64)) writeCurAddr <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) writeWordLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(64)) readCurAddr <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) readWordLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	rule dramReadReq ( readWordLeft > 0 );
		dram.readReq(readCurAddr, 64);
		readWordLeft <= readWordLeft - 1;
		readCurAddr <= readCurAddr + 64;
	endrule

   interface Clock user_clk = dramclk;
   interface Reset user_rst = dramrst;
	method Action writeReq(Bit#(64) addr, Bit#(32) words) if ( writeWordLeft == 0 );
		writeCurAddr <= addr;
		writeWordLeft <= words;
	endmethod
	method Action readReq(Bit#(64) addr, Bit#(32) words) if ( readWordLeft == 0 );
		readCurAddr <= addr;
		readWordLeft <= words;
	endmethod
	method Action write(Bit#(512) word) if ( writeWordLeft > 0 );
		dram.write(writeCurAddr, word, 64);
		writeCurAddr <= writeCurAddr + 64;
		writeWordLeft <= writeWordLeft - 1;
	endmethod
	method ActionValue#(Bit#(512)) read;
		let v <- dram.read;
		return v;
	endmethod
endmodule
