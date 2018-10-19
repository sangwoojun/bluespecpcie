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
	method Action addBuffer(Bit#(64) addr, Bit#(32) words, Bool last);
	method ActionValue#(Maybe#(Vector#(vcnt,valType))) get;
	method Action bufferDone;
endinterface

// qsize: max dram words in flight
module mkDRAMVectorUnpacker#(DRAMBurstControllerIfc dram, Integer qsize) (DRAMVectorUnpacker#(vcnt, valType))
	provisos(
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz),
		Mul#(vcnt, valTypeSz, vectorSz),
		Add#(valTypeSz,c__,vectorSz), Add#(vectorSz,a__, 1024)

	);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;

	Integer iVectorSz = valueOf(vectorSz);
	Integer iVectorBytes = iVectorSz/8;
	Integer iDRAMWordBytes = 512/8; //64 byte

	FIFO#(Bit#(512)) dramReadQ <- mkSizedBRAMFIFO(qsize*2, clocked_by dramclk, reset_by dramrst);
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

			// Not super accurate timing, but probably okay
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
	Reg#(Bool) dramBufferExist <- mkReg(False);

	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(8);

	rule unpackWord;
		if ( !isValid(dramReadBuffer) ) begin
			dramReadQ2.deq;
			let d = dramReadQ2.first;
			dramReadBuffer <= tagged Valid d;
			dramWordsLeft <= dramWordsLeft - 1;

			byteShifter.rotateByteBy({0,d}, 0);
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
			byteShifter.rotateByteBy({0,d}, truncate(shiftBytes));
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
		//We want to take the top (vectorSz) bits
		Bit#(vectorSz) ds = truncate(d);
		for ( Integer i = 0; i < valueOf(vcnt); i=i+1 ) begin
			Integer loweroff = valueOf(valTypeSz)*i;

			rv[i] = unpack(truncate(ds>>loweroff));
		end
		if ( v ) begin
			vectorQ.enq(tagged Valid rv);
		end else begin
			vectorQ.enq(tagged Invalid);
			dramBufferExist <= False;
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

	method Action addBuffer(Bit#(64) addr, Bit#(32) words, Bool last) if ( dramLastBuffer == False );

		if ( words == 0 || last ) begin
			if ( dramBufferExist ) begin
				dramLastBuffer <= True;
			end else begin
				outQ.enq(tagged Invalid);
			end
		end else begin
			dramBufferExist <= True;
			dramWordsLeft <= dramWordsLeft + words;
			bufferQ.enq(tuple2(addr,words));

			if ( last ) begin
				dramLastBuffer <= True;
			end
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
	method ActionValue#(Bit#(64)) bufferDone;
endinterface

// qsize: the amount of data it will try to buffer before starting DRAM burst
module mkDRAMVectorPacker#(DRAMBurstControllerIfc dram, Integer qsize) (DRAMVectorPacker#(vcnt, valType))
	provisos(
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz),
		Mul#(vcnt, valTypeSz, vectorSz),
		Add#(a__, valTypeSz, vectorSz),
		Add#(c__, vectorSz, 1024)
	);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;

	Integer iVectorSz = valueOf(vectorSz);
	Integer iVectorBytes = iVectorSz/8;
	Integer iDRAMWordSz = 512; //64 byte
	Integer iDRAMWordBytes = iDRAMWordSz/8; //64 byte


	FIFO#(Maybe#(Vector#(vcnt,valType))) inQ <- mkFIFO;
	FIFO#(Maybe#(Bit#(vectorSz))) packedQ <- mkFIFO;

	rule procIn;
		let d = inQ.first;
		inQ.deq;
		if ( isValid(d) ) begin
			Vector#(vcnt,valType) inv = fromMaybe(?,d);
			Bit#(vectorSz) p = 0;
			for ( Integer i = 0; i < valueOf(vcnt); i=i+1 ) begin
				Integer lowoff = valueOf(valTypeSz)*(valueOf(vcnt)-i-1);
				p = p | (zeroExtend(pack(inv[i]))<<lowoff);
			end
			packedQ.enq(tagged Valid p);
		end else begin
			packedQ.enq(tagged Invalid);
		end
	endrule
	SyncFIFOIfc#(Tuple2#(Bit#(64), Bit#(32))) bufferQ <- mkSyncFIFO(32, curclk, currst, dramclk);
	Reg#(Bool) dramLastBuffer <- mkReg(False);

	ByteShiftIfc#(Bit#(1024), 6) byteShifter <- mkPipelineLeftShifter;
	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(8);
	Reg#(Bit#(8)) shiftBytes <- mkReg(0);

	rule shiftPacked;
		let d_ = packedQ.first;
		packedQ.deq;
		let d = fromMaybe(?,d_);
		if ( isValid(d_) ) begin
			if ( shiftBytes + fromInteger(iVectorBytes ) >= fromInteger(iDRAMWordBytes) ) begin

				byteShifter.rotateByteBy({0,d}, truncate(shiftBytes));
				shiftBytes <= shiftBytes + fromInteger(iVectorBytes) - fromInteger(iDRAMWordBytes);
				isShiftedValidQ.enq(True);
			end else begin
				byteShifter.rotateByteBy({0,d}, truncate(shiftBytes));
				shiftBytes <= shiftBytes + fromInteger(iVectorBytes);
				isShiftedValidQ.enq(True);
			end
		end else begin
			shiftBytes <= 0;
			byteShifter.rotateByteBy(0,0);
			isShiftedValidQ.enq(False);
		end
	endrule

	FIFO#(Bit#(64)) writeBufferDoneQ <- mkSizedFIFO(32);
	
	SyncFIFOIfc#(Maybe#(Bit#(512))) dramWriteQ <- mkSyncFIFO(16, curclk, currst, dramclk);
	Reg#(Bit#(64)) curBufferOffset <- mkReg(0);
	Reg#(Bit#(32)) curBufferWordLeft <- mkReg(0);

	Reg#(Bit#(64)) curBufferBytesWritten <- mkReg(0);
	Reg#(Bool) flushing <- mkReg(False);
	


	Reg#(Bit#(8)) curShiftBytes <- mkReg(0);
	Reg#(Bit#(512)) dramWriteBuffer <- mkReg(0);
	rule getPacked (!flushing );
		let d <- byteShifter.getVal;
		let v = isShiftedValidQ.first;
		isShiftedValidQ.deq;


		if ( v ) begin
			if ( curShiftBytes + fromInteger(iVectorBytes) >= fromInteger(iDRAMWordBytes) ) begin
				curShiftBytes <= curShiftBytes + fromInteger(iVectorBytes) - fromInteger(iDRAMWordBytes);

				dramWriteBuffer <= truncateLSB(d);
				//curBufferBytesWritten <= curBufferBytesWritten + fromInteger(iDRAMWordBytes);
				
				dramWriteQ.enq(tagged Valid (dramWriteBuffer | truncate(d)) );
			end else begin
				dramWriteBuffer <= dramWriteBuffer | truncate(d);
				curShiftBytes <= curShiftBytes + fromInteger(iVectorBytes);
			end
		end else begin
			curShiftBytes <= 0;
			curBufferWordLeft <= 0;
			dramWriteQ.enq(tagged Valid dramWriteBuffer );
			//curBufferBytesWritten <= curBufferBytesWritten + fromInteger(iDRAMWordBytes);
			flushing <= True;
		end

	endrule
	rule flushout ( flushing );
		flushing <= False;
		dramWriteQ.enq(tagged Invalid);
		//writeBufferDoneQ.enq(curBufferBytesWritten);
		//curBufferBytesWritten <= 0;
	endrule


	rule getBuffer(curBufferWordLeft == 0);
		bufferQ.deq;
		let b = bufferQ.first;
		curBufferOffset <= tpl_1(b);
		curBufferWordLeft <= tpl_2(b);
		curBufferBytesWritten <= 0;
	endrule
	
	FIFO#(Bit#(512)) dramWriteStagedQ <- mkSizedBRAMFIFO(qsize*2, clocked_by dramclk, reset_by dramrst);

	Reg#(Bit#(32)) dramWriteCntUp <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(32)) dramWriteCntDn <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bool) dramWriteFlush <- mkReg(False, clocked_by dramclk, reset_by dramrst);

	rule relayDRAMWriteReq ( !dramWriteFlush ) ;
		dramWriteQ.deq;
		let d_ = dramWriteQ.first;

/*
		if (!isValid(d_)) begin
			dramWriteFlush <= True;
		end else begin
			dramWriteStagedQ.enq(fromMaybe(?,d_));
			dramWriteCntUp <= dramWriteCntUp + 1;
		end
*/
	endrule

	Reg#(Bit#(32)) dramWriteLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	rule initDRAMWrite( curBufferWordLeft > 0 && dramWriteLeft == 0 && (dramWriteFlush || dramWriteCntUp-dramWriteCntDn >= fromInteger(qsize)));
		let curq = dramWriteCntUp-dramWriteCntDn;
		Bit#(32) burstWords = fromInteger(qsize);
		if ( curq < burstWords ) burstWords = curq;
		if ( curBufferWordLeft < burstWords ) burstWords = curBufferWordLeft;


		dram.writeReq(curBufferOffset, burstWords);
		dramWriteLeft <= burstWords;
		dramWriteCntDn <= dramWriteCntDn + burstWords;

		curBufferWordLeft <= curBufferWordLeft - burstWords;
		curBufferOffset <= curBufferOffset + zeroExtend(burstWords);

		if ( curBufferWordLeft == burstWords ) begin
			if ( dramWriteFlush ) dramWriteFlush <= False;

			writeBufferDoneQ.enq(curBufferBytesWritten+(fromInteger(iDRAMWordBytes)*zeroExtend(burstWords)));
		end 
	endrule

	rule writeDRAM ( dramWriteLeft > 0 );
		curBufferBytesWritten <= curBufferBytesWritten + fromInteger(iDRAMWordBytes);

		dramWriteStagedQ.deq;
		dram.write(dramWriteStagedQ.first);
		dramWriteLeft <= dramWriteLeft - 1;
	endrule













	method Action addBuffer(Bit#(64) addr, Bit#(32) words);
		bufferQ.enq(tuple2(addr, words));
	endmethod
	method Action put(Maybe#(Vector#(vcnt,valType)) data);
		inQ.enq(data);
	endmethod
	method ActionValue#(Bit#(64)) bufferDone;
		writeBufferDoneQ.deq;
		return writeBufferDoneQ.first;
	endmethod
endmodule



