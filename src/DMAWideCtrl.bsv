import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import MergeN::*;

typedef struct {
	Bit#(256) word;
	Bit#(8) tag;
} WideWordTagged deriving (Bits,Eq);

interface DMAWideCtrlIfc;
	method Action dmaReadReq(Bit#(32) addr, Bit#(10) words);
	method ActionValue#(Bit#(256)) dmaReadWord;
	method Action dmaWriteReq(Bit#(32) addr, Bit#(32) words, Bit#(8) tag);
	method Action dmaWriteData(Bit#(256) data, Bit#(8) tag);

	method Action enq(Bit#(32) head, Bit#(128) word);
	method Action deq;
	method Bit#(128) first;
	method Bit#(32) header;
endinterface

typedef 4 DMAReadTags;

module mkDMAWideCtrl#(PcieUserIfc pcie) (DMAWideCtrlIfc);
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;
	
	// Structures for the enq method
	Reg#(Bit#(32)) enqReceivedIdx <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) enqIdx <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	FIFO#(DMAWordTagged) enqDmaWriteQ <- mkSizedFIFO(32,clocked_by pcieclk, reset_by pcierst);
	
	Vector#(8, Reg#(Bit#(32))) writeBuf <- replicateM(mkReg(0), clocked_by pcieclk, reset_by pcierst);
	SyncFIFOIfc#(Bit#(128)) ioRecvQ <- mkSyncFIFOToCC(8, pcieclk, pcierst);
	SyncFIFOIfc#(Bit#(32)) ioRecvHQ <- mkSyncFIFOToCC(8, pcieclk, pcierst);

	FIFO#(IOWrite) userWriteQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	FIFO#(IOWrite) userWrite1Q <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	rule getWriteReq;
		IOWrite d <- pcie.dataReceive;
		userWrite1Q.enq(d);
	endrule
	rule procFC;
		let d = userWrite1Q.first;
		userWrite1Q.deq;

		Bit#(8) toffset = truncate(d.addr>>2);
		if ( toffset < 16 ) begin
			userWriteQ.enq(d);
		end else if ( toffset == 16 ) begin
			enqReceivedIdx <= d.data;
		end else if ( toffset == 17 ) begin
			enqIdx <= d.data;
		end
	endrule
	rule userWriteReq;
		IOWrite d = userWriteQ.first;
		userWriteQ.deq;

		Bit#(3) offset = truncate(d.addr>>2);
		writeBuf[offset] <= d.data;
		if ( offset == 0 ) begin
			ioRecvQ.enq({writeBuf[3], writeBuf[2], writeBuf[1], d.data});
			ioRecvHQ.enq(writeBuf[4]);
		end
	endrule

	//Vector#(ways, FIFO#(DMAWordTagged)) dmaWritecQv <- replicateM(mkSizedFIFO(32));
	Reg#(Bit#(10)) dmaWriteOut <- mkReg(0);

	FIFO#(WideWordTagged) dmaWritecQ <- mkSizedFIFO(32);
	SyncFIFOIfc#(DMAWordTagged) dmaWriteQ <- mkSyncFIFOFromCC(64, pcieclk);
	Reg#(Bit#(10)) dmaWriteIn <- mkReg(0);
	FIFO#(Tuple2#(Bit#(8), DMAReq)) reqQ <- mkSizedFIFO(8);
	FIFO#(Tuple3#(Bit#(32),Bit#(32),Bit#(8))) writeReqQ <- mkSizedFIFO(8);
	
	Merge2Ifc#(Tuple2#(Bit#(8),DMAReq)) wm00 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);

	Reg#(Maybe#(DMAWordTagged)) dmaSerBuf <- mkReg(tagged Invalid);
	rule relayDmaWriteQ;
		if ( isValid(dmaSerBuf) ) begin
			dmaWriteQ.enq(fromMaybe(?,dmaSerBuf));
			dmaSerBuf <= tagged Invalid;
		end else begin
			let data = dmaWritecQ.first.word;
			let tag = dmaWritecQ.first.tag;
			dmaWritecQ.deq;
			dmaWriteQ.enq(DMAWordTagged{word:truncate(data),tag:tag});
			dmaSerBuf <= tagged Valid DMAWordTagged{word: truncate(data>>valueOf(DMAWordSz)), tag:tag};
		end
	endrule


	Reg#(Bit#(32)) writeWordsRemain <- mkReg(0);
	Reg#(Bit#(32)) writeCurAddr <- mkReg(0);
	Reg#(Bit#(8)) writeCurTag <- mkReg(0);
	rule startDivideWriteReq ( writeWordsRemain == 0 );
		writeReqQ.deq;
		let d = writeReqQ.first;
		let addr = tpl_1(d);
		let words = tpl_2(d);
		let tag = tpl_3(d);

		if ( words < 8 ) begin
			reqQ.enq(tuple2(0, DMAReq{addr:addr, words:truncate(words), tag:tag}));
		end else begin
			reqQ.enq(tuple2(0, DMAReq{addr:addr, words:8, tag:tag}));
			writeWordsRemain <= words - 8;
			writeCurAddr <= addr + 128;
			writeCurTag <= tag;
		end
	endrule
	rule divideWritereq ( writeWordsRemain > 0 );
		let addr = writeCurAddr;
		let tag = writeCurTag;
		let words = writeWordsRemain;
		writeCurAddr <= addr + 128;
		if ( words >= 8 ) begin
			reqQ.enq(tuple2(0, DMAReq{addr:addr, words:8, tag:tag}));
			writeWordsRemain <= words - 8;
		end else begin
			reqQ.enq(tuple2(0, DMAReq{addr:addr, words:truncate(words), tag:tag}));
			writeWordsRemain <= 0;
		end
	endrule

	SyncFIFOIfc#(Tuple2#(Bit#(8),DMAReq)) sfifodma <- mkSyncFIFOFromCC(8,pcieclk);
	rule relaydmawrqsync(dmaWriteIn-dmaWriteOut >= tpl_2(reqQ.first).words);
		reqQ.deq;
		dmaWriteOut<= dmaWriteOut + tpl_2(reqQ.first).words;
		sfifodma.enq(reqQ.first);
	endrule
	rule relaydmawrq ;
		sfifodma.deq;
		wm00.enq[0].enq(sfifodma.first);
	endrule
	
	FIFO#(Bool) assertInterruptQ <- mkSizedFIFO(16,clocked_by pcieclk, reset_by pcierst);
	rule assertInterrupt;
		assertInterruptQ.deq;
		//pcie.assertInterrupt;
	endrule

	Reg#(Bit#(10)) dmaWriteCnt <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaWriteSrc <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule issuedmaWrite ( dmaWriteCnt == 0 );
		wm00.deq;
		let src = tpl_1(wm00.first);
		let cmd = tpl_2(wm00.first);
		
		pcie.dmaWriteReq(cmd.addr, cmd.words, cmd.tag);

		dmaWriteSrc <= src;
		dmaWriteCnt <= cmd.words;
		//$display("Issuing DMA write from src %d", src);
	endrule
	rule senddmaWriteData ( dmaWriteCnt > 0 );
		dmaWriteCnt <= dmaWriteCnt - 1;
		if ( dmaWriteSrc == 0 ) begin
			pcie.dmaWriteData(
				(dmaWriteQ.first.word), 
				(dmaWriteQ.first.tag));
			dmaWriteQ.deq;
		end else begin
			pcie.dmaWriteData(
				enqDmaWriteQ.first.word, 
				enqDmaWriteQ.first.tag);
			enqDmaWriteQ.deq;
			if ( dmaWriteCnt == 1 ) assertInterruptQ.enq(True);// pcie.assertInterrupt; // which is always
		end
		//$display("Sending DMA write data from src %d", dmaWriteSrc );
	endrule

	FIFO#(Bit#(128)) enqcQ <- mkSizedFIFO(16);
	SyncFIFOIfc#(Bit#(128)) enqQ <- mkSyncFIFOFromCC(8, pcieclk);
	FIFO#(Bit#(128)) enq2Q <- mkSizedFIFO(16,clocked_by pcieclk, reset_by pcierst);
	
	FIFO#(Bit#(32)) enqchQ <- mkSizedFIFO(16);
	SyncFIFOIfc#(Bit#(32)) enqhQ <- mkSyncFIFOFromCC(8, pcieclk);
	FIFO#(Bit#(32)) enqh2Q <- mkSizedFIFO(16,clocked_by pcieclk, reset_by pcierst);

	Reg#(Bit#(2)) enqState <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) enqOffset <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	FIFO#(Bit#(128)) enqDataQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);

	rule relayEnqPacket;
		enqcQ.deq;
		enqQ.enq(enqcQ.first);
		enqchQ.deq;
		enqhQ.enq(enqchQ.first);
	endrule
	rule relayEnqPacketC;//( enqIdx - enqReceivedIdx < ( 1024*4 )/32 );// Just 4K  //FIXME so may stages!
		enqQ.deq;
		enq2Q.enq(enqQ.first);
		enqhQ.deq;
		enqh2Q.enq(enqhQ.first);
	endrule
	//FIFO#(Bit#(32)) enqIdxQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	rule startEnqPacket ( enqState == 0 && enqIdx - enqReceivedIdx < (1024*4)/32 ); // Just 4K
		enq2Q.deq;

		enqDataQ.enq(enq2Q.first);
		enqOffset <= ((enqOffset+32)&32'hfff); // Just 4K
		enqState <= 1;
		wm00.enq[1].enq(tuple2(255, DMAReq{addr:enqOffset, words:2, tag:0}));
		//enqIdx <= enqIdx + 1;
		//enqIdxQ.enq(enqIdx);
		//$display( "DMA enq data start - %x", enqOffset );
	endrule
	rule sendEnqPacket ( enqState == 1 );
		enqState <= 2;
		enqDataQ.deq;
		enqDmaWriteQ.enq(DMAWordTagged{word:enqDataQ.first, tag:0});
		//$display( "DMA enq data next" );
	endrule
	rule sendEnqIdx ( enqState == 2 ) ;
		enqh2Q.deq;

		enqIdx <= enqIdx + 1;
		//enqIdxQ.deq;
		//enqDmaWriteQ.enq(DMAWordTagged{word:{zeroExtend(enqIdxQ.first), enqh2Q.first}, tag:0});
		enqDmaWriteQ.enq(DMAWordTagged{word:{zeroExtend(enqIdx), enqh2Q.first}, tag:0});
		enqState <= 0;
	endrule

	//CompletionFIFOIfc#(Bit#(128), 7, 8) cbuf <- mkCompletionFIFO;
	Integer dmaReadTags = valueOf(DMAReadTags);
	FIFO#(Bit#(8)) availReadTagQ <- mkSizedFIFO(dmaReadTags, clocked_by pcieclk, reset_by pcierst);
	FIFO#(Tuple2#(Bit#(10),Bit#(8))) flightReadTagQ <- mkSizedFIFO(dmaReadTags , clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) readTagCounter <- mkReg(fromInteger(dmaReadTags), clocked_by pcieclk, reset_by pcierst);
	rule fillReadTagQ(readTagCounter > 0);
		readTagCounter <= readTagCounter - 1;
		availReadTagQ.enq(readTagCounter-1);
	endrule
	Vector#(DMAReadTags,FIFO#(DMAWord)) dmaReadQ <- replicateM(mkFIFO(clocked_by pcieclk, reset_by pcierst));
	SyncFIFOIfc#(DMAReq) dmaReadReqQ <- mkSyncFIFOFromCC(8, pcieclk);
	rule reqDMARead;
		dmaReadReqQ.deq;
		let r = dmaReadReqQ.first;
		//let t = availReadTagQ.first;
		//availReadTagQ.deq;
		//flightReadTagQ.enq(tuple2(r.words,t));

		pcie.dmaReadReq(r.addr, r.words, 0);
	endrule
	SyncFIFOIfc#(Bit#(256)) dmaReadWordQ <- mkSyncFIFOToCC(16,pcieclk, pcierst);
	rule recvDMARead;
		let w <- pcie.dmaReadWord;
		//let t = w.tag;
		//dmaReadQ[t].enq(w.word);
		//dmaReadWordQ.enq({truncate(w.word>>8),w.tag});
		//$display( "pcie.dmaReadWord %x %d", w.word, w.tag );
	endrule
	Reg#(Bit#(10)) curReadWords <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule reordDMAread;
		let f = flightReadTagQ.first;
		let words = tpl_1(f);
		let tag = tpl_2(f);

		let w = dmaReadQ[tag].first;
		dmaReadQ[tag].deq;

		//dmaReadWordQ.enq(w);

		if ( curReadWords + 1 >= words ) begin
			curReadWords <= 0;
			flightReadTagQ.deq;
			availReadTagQ.enq(tag);
		end else begin
			curReadWords <= curReadWords + 1;
		end
	endrule


	method Action dmaWriteReq(Bit#(32) addr_, Bit#(32) words, Bit#(8) tag);
		//First 4K are reserved for hw->sw FIFO
		Bit#(32) addr__ = addr_ + (1024*4);

		// "words" are 128bit words from here
		writeReqQ.enq(tuple3(addr__,words*2,tag));
	endmethod
	method Action dmaWriteData(Bit#(256) data, Bit#(8) tag);
		dmaWritecQ.enq(WideWordTagged{word:data, tag:tag});
		dmaWriteIn <= dmaWriteIn + 1;
	endmethod

	method Action dmaReadReq(Bit#(32) addr_, Bit#(10) words);
		Bit#(32) addr__ = addr_ + (1024*4);
		dmaReadReqQ.enq(DMAReq{addr:addr__, words:words, tag:0});
	endmethod
	method ActionValue#(Bit#(256)) dmaReadWord;
		dmaReadWordQ.deq;
		return dmaReadWordQ.first;
	endmethod
	method Action enq(Bit#(32) head, Bit#(128) word);
		enqcQ.enq(word);
		enqchQ.enq(head);
	endmethod
	method Action deq;
		ioRecvQ.deq;
		ioRecvHQ.deq;
	endmethod
	method Bit#(128) first;
		return ioRecvQ.first;
	endmethod
	method Bit#(32) header;
		return ioRecvHQ.first;
	endmethod
endmodule
