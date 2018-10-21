import Clocks::*;
import FIFO::*;
import BRAMFIFO::*;
import FIFOF::*;
import Vector::*;

import MergeN::*;

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
	method Action writeReq(Bit#(64) addr, Bit#(32) words) if ( writeWordLeft == 0 && readWordLeft == 0 );
		writeCurAddr <= addr;
		writeWordLeft <= words;
	endmethod
	method Action readReq(Bit#(64) addr, Bit#(32) words) if ( readWordLeft == 0 && writeWordLeft == 0 );
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

interface DRAMBurstReaderIfc;
	method Action readReq(Bit#(64) addr, Bit#(32) words);
	method ActionValue#(Bit#(512)) read;
endinterface

interface DRAMBurstWriterIfc;
	method Action writeReq(Bit#(64) addr, Bit#(32) words);
	method Action write(Bit#(512) word);
endinterface

interface DRAMBurstSplitterIfc#(numeric type rcnt, numeric type wcnt);
	interface Vector#(rcnt, DRAMBurstReaderIfc) readers;
	interface Vector#(wcnt, DRAMBurstWriterIfc) writers;
endinterface

module mkDRAMBurstSplitter#(DRAMBurstControllerIfc dram) (DRAMBurstSplitterIfc#(rcnt,wcnt)) 
	provisos(Add#(rcnt,a__,256), Add#(wcnt,b__,256));

	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	MergeNIfc#(rcnt, Tuple3#(Bit#(64), Bit#(32), Bit#(8))) mReader <- mkMergeN;
	MergeNIfc#(wcnt, Tuple3#(Bit#(64), Bit#(32), Bit#(8))) mWriter <- mkMergeN;
	Vector#(wcnt, SyncFIFOIfc#(Bit#(512))) writerQs <- replicateM(mkSyncFIFO(8,curclk,currst,dramclk));
	Vector#(rcnt, SyncFIFOIfc#(Bit#(512))) readerQs <- replicateM(mkSyncFIFO(8,dramclk, dramrst, curclk));

	SyncFIFOIfc#(Tuple3#(Bit#(64), Bit#(32), Bit#(8))) readerQ <- mkSyncFIFO(2, curclk, currst, dramclk);
	SyncFIFOIfc#(Tuple3#(Bit#(64), Bit#(32), Bit#(8))) writerQ <- mkSyncFIFO(2, curclk, currst, dramclk);

	Reg#(Bit#(32)) curReadCnt  <- mkReg(0,clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) curWriteCnt <- mkReg(0,clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(8)) curClientIdx <- mkReg(0,clocked_by dramclk, reset_by dramrst);

	rule relayDramRead; 
		let r = mReader.first;
		mReader.deq;
		readerQ.enq(r);
	endrule
	rule relayDramWrite;
		let r = mWriter.first;
		mWriter.deq;
		writerQ.enq(r);
	endrule
	rule startDramWrite ( curReadCnt == 0 && curWriteCnt == 0 );
		writerQ.deq;
		let r = writerQ.first;
		dram.writeReq(tpl_1(r), tpl_2(r));
		curWriteCnt <= tpl_2(r);
		curClientIdx <= tpl_3(r);
	endrule
	rule startDramRead( curReadCnt == 0 && curWriteCnt == 0 );
		readerQ.deq;
		let r = readerQ.first;
		dram.readReq(tpl_1(r), tpl_2(r));
		curReadCnt <= tpl_2(r);
		curClientIdx <= tpl_3(r);
	endrule
	

	rule relayWrite ( curReadCnt == 0 && curWriteCnt > 0 );
		curWriteCnt <= curWriteCnt - 1;
		writerQs[curClientIdx].deq;
		let d = writerQs[curClientIdx].first;
		dram.write(d);
	endrule

	rule relayRead ( curReadCnt > 0 && curWriteCnt == 0 );
		curReadCnt <= curReadCnt - 1;
		let d <- dram.read;
		readerQs[curClientIdx].enq(d);
	endrule
	
	Vector#(rcnt, DRAMBurstReaderIfc) readers_;
	Vector#(wcnt, DRAMBurstWriterIfc) writers_;

	for ( Integer i = 0; i < valueOf(rcnt); i=i+1) begin
		readers_[i] = interface DRAMBurstReaderIfc;
			method Action readReq(Bit#(64) addr, Bit#(32) words);
				mReader.enq[i].enq(tuple3(addr,words,fromInteger(i)));
			endmethod
			method ActionValue#(Bit#(512)) read;
				readerQs[i].deq;
				return readerQs[i].first;
			endmethod

		endinterface: DRAMBurstReaderIfc;
	end
	for ( Integer i = 0; i < valueOf(wcnt); i=i+1) begin
		writers_[i] = interface DRAMBurstWriterIfc;
			method Action writeReq(Bit#(64) addr, Bit#(32) words);
				mWriter.enq[i].enq(tuple3(addr,words,fromInteger(i)));
			endmethod
			method Action write(Bit#(512) word);
				writerQs[i].enq(word);
			endmethod
		endinterface: DRAMBurstWriterIfc;
	end
	interface readers = readers_;
	interface writers = writers_;
endmodule





















