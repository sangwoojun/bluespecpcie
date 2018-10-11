/***********
Notes:
interface is word granularity (512 bits)
data types need to be byte aligned
***********/




import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import BRAM::*;
import BRAMFIFO::*;

import Shifter::*;

import DRAMBurstController::*;

interface DRAMVectorUnpacker#(numeric type vcnt, type valType);
	method Action addBuffer(Bit#(64) addr, Bit#(32) words);
	method ActionValue#(Maybe#(Vector#(vcnt,valType))) get;
	method Action bufferDone;
endinterface

// qsize: max dram words in read q
module mkDRAMVectorUnpacker#(DRAMBurstControllerIfc dram, Integer qsize) (DRAMVectorUnpacker#(vcnt, valType))
	provisos(
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz),
		Mul#(vcnt, valTypeSz, vectorSz)

	);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;

	Integer iVectorSz = valueOf(vectorSz);
	Integer iVectorBytes = iVectorSz/8;
	Integer iDRAMWordBytes = 512/8; //64 byte

	//FIFO#(Maybe#(Vector#(vcnt, valType))) dramReadQ <- mkSizedBRAMFIFO(qsize, clocked_by dramclk, reset_by dramrst);
	FIFO#(Bit#(512)) dramReadQ <- mkSizedBRAMFIFO(qsize, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) dramReadCntUp <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) dramReadCntDn <- mkReg(0, clocked_by dramclk, reset_by dramrst);

	//Reg#(Bit#(64)) vecLeft <- mkReg(0);
	//SyncFIFOIfc#(Bit#(64)) dramWordsQ <- mkSyncFIFO(16, curclk, currst, dramclk);

	SyncFIFOIfc#(Tuple2#(Bit#(64), Bit#(32))) bufferQ <- mkSyncFIFO(32, curclk, currst, dramclk);
	FIFO#(Tuple2#(Bit#(64), Bit#(32))) bufferSplitQ <- mkFIFO(clocked_by dramclk, reset_by dramrst);
	SyncFIFOIfc#(Bit#(512)) dramReadQ2 <- mkSyncFIFO(16, dramclk, dramrst, curclk);
	SyncFIFOIfc#(Bool) bufferDoneQ <- mkSyncFIFO(16, dramclk, dramrst, curclk);

	Reg#(Bit#(64)) dramBlockReadOff <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) dramBlockReadLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);

	Reg#(Bit#(32)) dramReadCurLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	rule startSplitBufferRead ( dramBlockReadLeft == 0 );
		bufferQ.deq;
		let d = bufferQ.first;
		let off = tpl_1(d);
		let words = tpl_2(d);

		dramBlockReadOff <= off;
		dramBlockReadLeft <= words;
	endrule
	rule splitBufferRead ( dramBlockReadLeft > 0 );
		if ( dramBlockReadLeft > fromInteger(qsize) ) begin
			dramBlockReadLeft <= dramBlockReadLeft - fromInteger(qsize);
			dramBlockReadOff <= dramBlockReadOff + fromInteger(qsize*iDRAMWordBytes);
			bufferSplitQ.enq(tuple2(dramBlockReadOff, fromInteger(qsize)));
		end else begin
			dramBlockReadLeft <= 0;
			bufferSplitQ.enq(tuple2(dramBlockReadOff, dramBlockReadLeft));
			bufferDoneQ.enq(True);
		end
	endrule
	rule startBufferRead ( dramReadCurLeft == 0 && dramReadCntUp-dramReadCntDn + tpl_2(bufferSplitQ.first) <= fromInteger(qsize) ); 
		bufferSplitQ.deq;
		let d = bufferSplitQ.first;
		let off = tpl_1(d);
		let words = tpl_2(d);

		dram.readReq(off, words);
		dramReadCntUp <= dramReadCntUp + tpl_2(d);
		dramReadCurLeft <= words;
	endrule

	rule readDRAM ( dramReadCurLeft > 0 );
		let d <- dram.read;
		dramReadQ.enq(d);
		dramReadCurLeft <= dramReadCurLeft - 1;
	endrule

	rule relayDRAM;
		let d = dramReadQ.first;
		dramReadQ.deq;
		dramReadQ2.enq(d);
		dramReadCntDn <= dramReadCntDn + 1;
	endrule



	ByteShiftIfc#(Bit#(1024), 6) byteShifter <- mkPipelineRightShifter;
	Reg#(Maybe#(Bit#(512))) dramReadBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(8)) shiftBytes <- mkReg(0);

	Reg#(Bit#(32)) dramWordsLeft <- mkReg(0);
	Reg#(Bool) dramLastBuffer <- mkReg(False);

	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(8);

	rule unpackWord;
		if ( !isValid(dramReadBuffer) ) begin
			dramReadQ2.deq;
			let d = dramReadQ2.first;
			dramReadBuffer <= tagged Valid d;
			dramWordsLeft <= dramWordsLeft - 1;

			byteShifter.rotateByteBy(zeroExtend(d), 0);
			shiftBytes <= fromInteger(iVectorBytes);
			isShiftedValidQ.enq(True);
		end else if (shiftBytes + fromInteger(iVectorBytes) >= fromInteger(iDRAMWordBytes) ) begin
			if ( dramWordsLeft == 0 && dramLastBuffer == True ) begin
				dramReadBuffer <= tagged Invalid;
				shiftBytes <= 0;
				dramLastBuffer <= False;
				byteShifter.rotateByteBy(0,0);
				isShiftedValidQ.enq(False);
			end else begin
				dramReadQ2.deq;
				let d = dramReadQ2.first;
				let d0 = fromMaybe(?,dramReadBuffer);
				let dt = {d,d0};
				
				byteShifter.rotateByteBy(dt, truncate(shiftBytes));

				dramReadBuffer <= tagged Valid d;
				shiftBytes <= (shiftBytes+fromInteger(iVectorBytes)-fromInteger(iDRAMWordBytes));
				isShiftedValidQ.enq(True);
				dramWordsLeft <= dramWordsLeft - 1;
			end
		end else begin
			let d = fromMaybe(?,dramReadBuffer);
			byteShifter.rotateByteBy(zeroExtend(d), truncate(shiftBytes));
			shiftBytes <= shiftBytes + fromInteger(iVectorBytes);
			isShiftedValidQ.enq(True);
		end
	endrule


	FIFO#(Maybe#(Vector#(vcnt,valType))) vectorQ <- mkFIFO;
	rule recvVector;
		let d <- byteShifter.getVal;
		let v = isShiftedValidQ.first;
		isShiftedValidQ.deq;

		Vector#(vcnt,valType) rv;
		for ( Integer i = 0; i < valueOf(vcnt); i=i+1 ) begin
			rv[i] = unpack(d[valueOf(valTypeSz)*(i+1)-1:valueOf(valTypeSz)*i]);
		end
		if ( v ) begin
			vectorQ.enq(tagged Valid rv);
		end else begin
			vectorQ.enq(tagged Invalid);
		end
	endrule

	FIFO#(Maybe#(Vector#(vcnt,valType))) outQ <- mkFIFO;
	//Reg#(Bool) readyForInput <- mkReg(True);
	rule emitOutQ;// ( readyForInput == False ) ;
		//if ( vecLeft > 0 ) begin
			vectorQ.deq;
			let v = vectorQ.first;
			//vecLeft <= vecLeft - 1;

			outQ.enq(v);
		//end else begin
			//outQ.enq(tagged Invalid);
			//readyForInput <= True;
		//end
	endrule

	Reg#(Bit#(64)) dramReadLeft <- mkReg(0);

	method Action addBuffer(Bit#(64) addr, Bit#(32) words) if ( dramLastBuffer == False );
		if ( words > 0 ) begin
			dramWordsLeft <= dramWordsLeft + words;
			bufferQ.enq(tuple2(addr,words));
		end else begin
			dramLastBuffer <= True;
		end
	endmethod
	method ActionValue#(Maybe#(Vector#(vcnt,valType))) get;
		outQ.deq;
		return outQ.first;
	endmethod
	method Action bufferDone;
		bufferDoneQ.deq;
	endmethod
endmodule

interface DRAMVectorPacker#(numeric type vcnt, type valType);
	method Action addBuffer(Bit#(64) addr, Bit#(32) words);
	method Action put(Maybe#(Vector#(vcnt,valType)) data);
	method Action bufferDone;
endinterface

// qsize: the amount of data it will try to buffer before starting DRAM burst
module mkDRAMVectorUnpacker#(DRAMBurstControllerIfc dram, Integer qsize) (DRAMVectorUnpacker#(vcnt, valType))
	provisos(
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz),
		Mul#(vcnt, valTypeSz, vectorSz)

	);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;

	Integer iVectorSz = valueOf(vectorSz);
	Integer iVectorBytes = iVectorSz/8;
	Integer iDRAMWordBytes = 512/8; //64 byte
	method Action addBuffer(Bit#(64) addr, Bit#(32) words);
	endmethod
	method Action put(Maybe#(Vector#(vcnt,valType)) data);
	endmethod
	method Action bufferDone;
	endmethod
endmodule
