import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import MergeN::*;
import CompletionFIFO::*;

interface DMAUserIfc;
	method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
	method Action dmaWriteData(DMAWord data, Bit#(8) tag);
endinterface

interface DMASplitterIfc #(numeric type ways);
	method Action dmaReadReq(Bit#(32) addr, Bit#(10) words);
	method ActionValue#(DMAWord) dmaReadWord;
	method Action enq(Bit#(32) head, Bit#(128) word);
	method Action deq;
	method Bit#(128) first;
	method Bit#(32) header;

	interface Vector#(ways, DMAUserIfc) users;
endinterface

typedef 4 DMAReadTags;

module mkDMASplitter#(PcieUserIfc pcie) (DMASplitterIfc#(ways));
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

	Vector#(ways, FIFO#(DMAWordTagged)) dmaWritecQv <- replicateM(mkSizedFIFO(32));
	Vector#(ways, SyncFIFOIfc#(DMAWordTagged)) dmaWriteQv <- replicateM(mkSyncFIFOFromCC(64, pcieclk));
	Vector#(ways, Reg#(Bit#(10))) dmaWriteIn <- replicateM(mkReg(0));
	Vector#(ways, Reg#(Bit#(10))) dmaWriteOut <- replicateM(mkReg(0));

	
	// TODO Cleaner way to do this?
	MergeNIfc#(ways, Tuple2#(Bit#(8), DMAReq)) wm <- mkMergeN(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAReq)) wm00 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	rule merge0;
		wm.deq;
		wm00.enq[0].enq(wm.first);
	endrule

/*
	Merge2Ifc#(Tuple2#(Bit#(8),DMAReq)) wm10 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAReq)) wm20 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAReq)) wm21 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	rule merge10;
		wm20.deq;
		wm10.enq[0].enq(wm20.first);
	endrule
	rule merge11;
		wm21.deq;
		wm10.enq[1].enq(wm21.first);
	endrule
	*/
	Vector#(ways, FIFO#(Tuple2#(Bit#(8), DMAReq))) reqQv <- replicateM(mkSizedFIFO(8));
	for ( Integer i = 0; i < valueOf(ways); i = i + 1 ) begin
		rule relayDmaWriteQ;
			dmaWritecQv[i].deq;
			dmaWriteQv[i].enq(dmaWritecQv[i].first);
		endrule

		SyncFIFOIfc#(Tuple2#(Bit#(8),DMAReq)) sfifodma <- mkSyncFIFOFromCC(8,pcieclk);
		rule relaydmawrqsync(dmaWriteIn[i]-dmaWriteOut[i] >= tpl_2(reqQv[i].first).words);
			reqQv[i].deq;
			dmaWriteOut[i] <= dmaWriteOut[i] + tpl_2(reqQv[i].first).words;
			sfifodma.enq(reqQv[i].first);
			
		endrule
		rule relaydmawrq ;
			sfifodma.deq;
			wm.enq[i].enq(sfifodma.first);
		endrule
	end
	
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
		if ( dmaWriteSrc < 255 ) begin
			pcie.dmaWriteData(
				(dmaWriteQv[dmaWriteSrc].first.word), 
				(dmaWriteQv[dmaWriteSrc].first.tag));
			dmaWriteQv[dmaWriteSrc].deq;
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
	SyncFIFOIfc#(DMAWord) dmaReadWordQ <- mkSyncFIFOToCC(16,pcieclk, pcierst);
	rule recvDMARead;
		let w <- pcie.dmaReadWord;
		//let t = w.tag;
		//dmaReadQ[t].enq(w.word);
		dmaReadWordQ.enq({truncate(w.word>>8),w.tag});
		//$display( "pcie.dmaReadWord %x %d", w.word, w.tag );
	endrule
	Reg#(Bit#(10)) curReadWords <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule reordDMAread;
		let f = flightReadTagQ.first;
		let words = tpl_1(f);
		let tag = tpl_2(f);

		let w = dmaReadQ[tag].first;
		dmaReadQ[tag].deq;

		dmaReadWordQ.enq(w);

		if ( curReadWords + 1 >= words ) begin
			curReadWords <= 0;
			flightReadTagQ.deq;
			availReadTagQ.enq(tag);
		end else begin
			curReadWords <= curReadWords + 1;
		end
	endrule

	Vector#(ways, DMAUserIfc) users_;

	for ( Integer i = 0; i < valueOf(ways); i = i + 1 ) begin
		users_[i] = interface DMAUserIfc;
			method Action dmaWriteReq(Bit#(32) addr_, Bit#(10) words, Bit#(8) tag);
				//First 4K are reserved for hw->sw FIFO
				Bit#(32) addr__ = addr_ + (1024*4);
				reqQv[i].enq(tuple2(fromInteger(i), DMAReq{addr:addr__, words:words, tag:tag}));
			endmethod
			method Action dmaWriteData(DMAWord data, Bit#(8) tag);
				dmaWritecQv[i].enq(DMAWordTagged{word:data, tag:tag});
				dmaWriteIn[i] <= dmaWriteIn[i] + 1;
			endmethod
		endinterface: DMAUserIfc;
	end

	method Action dmaReadReq(Bit#(32) addr_, Bit#(10) words);
		Bit#(32) addr__ = addr_ + (1024*4);
		dmaReadReqQ.enq(DMAReq{addr:addr__, words:words, tag:0});
	endmethod
	method ActionValue#(DMAWord) dmaReadWord;
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
	interface users = users_;
endmodule
