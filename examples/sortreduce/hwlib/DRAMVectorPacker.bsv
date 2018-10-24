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

	method Bit#(32) debug;
endinterface

// qsize: max dram words in flight
module mkDRAMVectorUnpacker#(DRAMBurstReaderIfc dram, Integer qsize) (DRAMVectorUnpacker#(vcnt, valType))
	provisos(
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz),
		Mul#(vcnt, valTypeSz, vectorSz),
		Add#(valTypeSz,c__,vectorSz), Add#(vectorSz,a__, 1024)

	);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	Integer iVectorSz = valueOf(vectorSz);
	Integer iVectorBytes = iVectorSz/8;
	Integer iDRAMWordBytes = 512/8; //64 byte

	FIFO#(Bit#(512)) dramReadQ <- mkSizedBRAMFIFO(qsize*2);
	Reg#(Bit#(32)) dramReadCntUp <- mkReg(0);
	Reg#(Bit#(32)) dramReadCntDn <- mkReg(0);

	FIFO#(Tuple2#(Bit#(64), Bit#(32))) bufferQ <- mkSizedFIFO(32);
	FIFO#(Tuple2#(Bit#(64), Bit#(32))) bufferSplitQ <- mkFIFO;
	FIFO#(Bit#(512)) dramReadQ2 <- mkSizedFIFO(16);
	FIFO#(Bool) bufferDoneQ <- mkSizedFIFO(16);

	Reg#(Bit#(64)) dramBlockReadOff <- mkReg(0);
	Reg#(Bit#(32)) dramBlockReadLeft <- mkReg(0);

	Reg#(Bit#(32)) dramWordsLeftUp <- mkReg(0);
	Reg#(Bit#(32)) dramWordsLeftDn <- mkReg(0);

	Reg#(Bit#(32)) dramReadCurLeft <- mkReg(0);
	Reg#(Bool) dramLastBuffer <- mkReg(False);
	FIFOF#(Bool) dramBufferExistQ <- mkFIFOF;
	FIFOF#(Bool) invQ <- mkFIFOF;
	rule startSplitBufferRead ( dramBlockReadLeft == 0 && dramLastBuffer == False );
		bufferQ.deq;
		let d = bufferQ.first;
		let off = tpl_1(d);
		let words = tpl_2(d);


		if ( words == 0 ) begin
			if ( dramBufferExistQ.notEmpty ) begin
				dramLastBuffer <= True;
			end else begin
				invQ.enq(True);
			end
		end else begin
			if ( !dramBufferExistQ.notEmpty ) begin
				dramBufferExistQ.enq(True);
			end
			dramWordsLeftUp <= dramWordsLeftUp + words;
			dramBlockReadOff <= off;
			dramBlockReadLeft <= words;
		end
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

	Reg#(Bit#(32)) upperKeyCnt <- mkReg(0);
	rule relayDRAM;
		let d = dramReadQ.first;

		Bit#(32) uka = 0;
		if ( d[31:0] > 0 && d[63:32] > 0 && d[95:64] > 0 ) uka = uka + 1;
		upperKeyCnt <= upperKeyCnt + uka;


		dramReadQ.deq;
		dramReadQ2.enq(d);
		dramReadCntDn <= dramReadCntDn + 1;
	endrule



	ByteShiftIfc#(Bit#(1024), 8) byteShifter <- mkPipelineRightShifter;
	Reg#(Maybe#(Bit#(512))) dramReadBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(8)) shiftBytes <- mkReg(0);

	// indicate last buffer inputed
	Reg#(Bool) resetLast <- mkReg(False);

	// message to indicate at least one dram buffer inputed

	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(16);

	rule resetLastr ( resetLast && dramLastBuffer );
		resetLast <= False;
		dramLastBuffer <= False;
	endrule

	rule unpackWord ( !resetLast ) ;
		if ( !isValid(dramReadBuffer) ) begin
			dramReadQ2.deq;
			let d = dramReadQ2.first;
			dramReadBuffer <= tagged Valid d;

			byteShifter.rotateByteBy({0,d}, 0);
			shiftBytes <= fromInteger(iVectorBytes);
			isShiftedValidQ.enq(True);

			dramWordsLeftDn <= dramWordsLeftDn + 1;
		end else if (shiftBytes + fromInteger(iVectorBytes) >= fromInteger(iDRAMWordBytes) ) begin
			if ( dramWordsLeftUp-dramWordsLeftDn == 0 && dramLastBuffer ) begin
				dramReadBuffer <= tagged Invalid;
				shiftBytes <= 0;
				resetLast <= True;
				byteShifter.rotateByteBy(0,0);
				isShiftedValidQ.enq(False);
			end else begin
				dramReadQ2.deq;
				let d = dramReadQ2.first;
				let d0 = fromMaybe(?,dramReadBuffer);
				let dt = {d,d0};
				
				byteShifter.rotateByteBy(dt, shiftBytes);

				dramReadBuffer <= tagged Valid d;
				shiftBytes <= (shiftBytes+fromInteger(iVectorBytes)-fromInteger(iDRAMWordBytes));
				isShiftedValidQ.enq(True);
				dramWordsLeftDn <= dramWordsLeftDn + 1;
			end
		end else begin
			let d = fromMaybe(?,dramReadBuffer);
			byteShifter.rotateByteBy({0,d}, shiftBytes);
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
		//We want to take the bottom (vectorSz) bits
		Bit#(vectorSz) ds = truncate(d);
		Bit#(32) ukadd = 0;
		for ( Integer i = 0; i < valueOf(vcnt); i=i+1 ) begin
			Integer loweroff = valueOf(valTypeSz)*i;

			Bit#(valTypeSz) c = truncate(ds>>loweroff);
			if ( c[64:32]>0 ) ukadd=ukadd+1;
			rv[i] = unpack(c);
		end
		if ( v ) begin
			vectorQ.enq(tagged Valid rv);
		end else begin
			vectorQ.enq(tagged Invalid);

			// not checking if notEmpty for timing issues
			// should always have one element for each transaction
			dramBufferExistQ.deq;
		end
	endrule

	FIFO#(Maybe#(Vector#(vcnt,valType))) outQ <- mkFIFO;
	//Reg#(Bool) readyForInput <- mkReg(True);
	rule emitOutQ( !invQ.notEmpty );
			vectorQ.deq;
			let v = vectorQ.first;
			outQ.enq(v);
	endrule
	rule emitInv ( invQ.notEmpty );
		invQ.deq;
		outQ.enq(tagged Invalid);
	endrule

	Reg#(Bit#(64)) dramReadLeft <- mkReg(0);

	method Action addBuffer(Bit#(64) addr, Bit#(32) words, Bool last);
		if ( last ) begin
			bufferQ.enq(tuple2(0,0));
		end else begin
			bufferQ.enq(tuple2(addr,words));
		end
	endmethod
	method ActionValue#(Maybe#(Vector#(vcnt,valType))) get;
		outQ.deq;
		return outQ.first;
	endmethod
	method Action bufferDone;
		bufferDoneQ.deq;
	endmethod
	method Bit#(32) debug;
		return upperKeyCnt;
	endmethod
endmodule

interface DRAMVectorPacker#(numeric type vcnt, type valType);
	method Action addBuffer(Bit#(64) addr, Bit#(32) words);
	method Action put(Maybe#(Vector#(vcnt,valType)) data);
	method ActionValue#(Bit#(64)) bufferDone;
endinterface

// qsize: the amount of data it will try to buffer before starting DRAM burst
module mkDRAMVectorPacker#(DRAMBurstWriterIfc dram, Integer qsize) (DRAMVectorPacker#(vcnt, valType))
	provisos(
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz),
		Mul#(vcnt, valTypeSz, vectorSz),
		Add#(a__, valTypeSz, vectorSz),
		Add#(c__, vectorSz, 1024)
	);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

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
				Integer lowoff = valueOf(valTypeSz)*i;
				p = p | (zeroExtend(pack(inv[i]))<<lowoff);
			end
			packedQ.enq(tagged Valid p);
		end else begin
			packedQ.enq(tagged Invalid);
		end
	endrule
	FIFO#(Tuple2#(Bit#(64), Bit#(32))) bufferQ <- mkSizedFIFO(32);

	ByteShiftIfc#(Bit#(1024), 8) byteShifter <- mkPipelineLeftShifter;
	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(16);
	Reg#(Bit#(8)) shiftBytes <- mkReg(0);

	rule shiftPacked;
		let d_ = packedQ.first;
		packedQ.deq;
		let d = fromMaybe(?,d_);
		if ( isValid(d_) ) begin
			if ( shiftBytes + fromInteger(iVectorBytes ) >= fromInteger(iDRAMWordBytes) ) begin

				byteShifter.rotateByteBy({0,d}, shiftBytes);
				shiftBytes <= shiftBytes + fromInteger(iVectorBytes) - fromInteger(iDRAMWordBytes);
				isShiftedValidQ.enq(True);
			end else begin
				byteShifter.rotateByteBy({0,d}, shiftBytes);
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
	
	FIFO#(Maybe#(Bit#(512))) dramWriteQ <- mkSizedFIFO(16);
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
				
				dramWriteQ.enq(tagged Valid (dramWriteBuffer | truncate(d)) );
			end else begin
				dramWriteBuffer <= (dramWriteBuffer | truncate(d));
				curShiftBytes <= curShiftBytes + fromInteger(iVectorBytes);
			end
		end else begin
			curShiftBytes <= 0;
			dramWriteQ.enq(tagged Valid dramWriteBuffer );
			flushing <= True;
		end
	endrule
	rule flushout ( flushing );
		flushing <= False;
		dramWriteQ.enq(tagged Invalid);
	endrule


	rule getBuffer(curBufferWordLeft == 0);
		bufferQ.deq;
		let b = bufferQ.first;
		curBufferOffset <= tpl_1(b);
		curBufferWordLeft <= tpl_2(b);
		//curBufferBytesWritten <= 0;
	endrule
	
	FIFO#(Bit#(512)) dramWriteStagedQ <- mkSizedBRAMFIFO(qsize*2);

	Reg#(Bit#(32)) dramWriteCntUp <- mkReg(0);
	Reg#(Bit#(32)) dramWriteCntDn <- mkReg(0);
	Reg#(Bool) dramWriteFlush <- mkReg(False);
	Reg#(Bool) dramWriteFlushReset <- mkReg(False);

	rule relayDRAMWriteReq ( !dramWriteFlush ) ;
		dramWriteQ.deq;
		let d_ = dramWriteQ.first;

		if ( isValid(d_) ) begin
			dramWriteStagedQ.enq(fromMaybe(?,d_));
			dramWriteCntUp <= dramWriteCntUp + 1;
		end else begin
			dramWriteFlush <= True;
		end
	endrule

	Reg#(Bool) lastWriteBurst <- mkReg(False);
	Reg#(Bit#(32)) dramWriteLeft <- mkReg(0);
	rule initDRAMWrite( curBufferWordLeft > 0 && dramWriteLeft == 0 && !dramWriteFlushReset &&
		(dramWriteFlush || dramWriteCntUp-dramWriteCntDn >= fromInteger(qsize)));
		let curq = dramWriteCntUp-dramWriteCntDn;
		Bit#(32) burstWords = fromInteger(qsize);
		if ( curq < burstWords ) burstWords = curq;
		if ( curBufferWordLeft < burstWords ) burstWords = curBufferWordLeft;

		if ( burstWords > 0 ) begin
			dram.writeReq(curBufferOffset, burstWords);
			dramWriteLeft <= burstWords;
			dramWriteCntDn <= dramWriteCntDn + burstWords;

			curBufferOffset <= curBufferOffset + (zeroExtend(burstWords) * fromInteger(iDRAMWordBytes));
			curBufferBytesWritten <= curBufferBytesWritten + (fromInteger(iDRAMWordBytes)*zeroExtend(burstWords));

			if ( curBufferWordLeft == burstWords ) begin
				lastWriteBurst <= True;
				curBufferWordLeft <= 0;
				if ( dramWriteFlush ) dramWriteFlushReset <= True;
			end else begin
				lastWriteBurst <= False;
				curBufferWordLeft <= curBufferWordLeft - burstWords;
			end
		end
	endrule

	rule resetFlush(dramWriteFlush && dramWriteFlushReset);
		dramWriteFlush <= False;
		dramWriteFlushReset <= False;
	endrule

	rule writeDRAM ( dramWriteLeft > 0 );
		dramWriteStagedQ.deq;
		let r = dramWriteStagedQ.first;

		dram.write(r);
		dramWriteLeft <= dramWriteLeft - 1;
		
		if ( dramWriteLeft == 1 && lastWriteBurst ) begin
			writeBufferDoneQ.enq(curBufferBytesWritten);
			curBufferBytesWritten <= 0;
		end
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



