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
	method Action dmaReadReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
	method ActionValue#(DMAWordTagged) dmaReadWord;
endinterface

interface DMASplitterIfc #(numeric type ways);
	method Action enq(Bit#(32) head, Bit#(128) word);
	method Action deq;
	method Bit#(128) first;
	method Bit#(32) header;

	interface Vector#(ways, DMAUserIfc) users;
endinterface

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
	rule getWriteReq;
		let d <- pcie.dataReceive;
		Bit#(8) toffset = truncate(d.addr>>2);
		if ( d.addr < 16 ) begin
			Bit#(3) offset = truncate(d.addr>>2);
			writeBuf[offset] <= d.data;
			if ( offset == 0 ) begin
				ioRecvQ.enq({writeBuf[3], writeBuf[2], writeBuf[1], d.data});
				ioRecvHQ.enq(writeBuf[4]);
			end
		end else if ( toffset == 16 ) begin
			enqReceivedIdx <= d.data;
			//$display( "enqReceivedIdx set to %d", d.data );
		end else if ( toffset == 17 ) begin
			enqIdx <= d.data;
		end
	endrule

	Vector#(ways, FIFO#(DMAWordTagged)) dmaWritecQv <- replicateM(mkFIFO);
	Vector#(ways, SyncFIFOIfc#(DMAWordTagged)) dmaWriteQv <- replicateM(mkSyncFIFOFromCC(16, pcieclk));
	Vector#(ways, Reg#(Bit#(10))) dmaWriteIn <- replicateM(mkReg(0));
	Vector#(ways, Reg#(Bit#(10))) dmaWriteOut <- replicateM(mkReg(0));

	
	// TODO Cleaner way to do this?
	MergeNIfc#(ways, Tuple2#(Bit#(8), DMAWriteReq)) wm <- mkMergeN(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm00 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	rule merge0;
		wm.deq;
		wm00.enq[0].enq(wm.first);
	endrule

/*
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm10 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm20 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm21 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	rule merge10;
		wm20.deq;
		wm10.enq[0].enq(wm20.first);
	endrule
	rule merge11;
		wm21.deq;
		wm10.enq[1].enq(wm21.first);
	endrule
	*/
	Vector#(ways, FIFO#(Tuple2#(Bit#(8), DMAWriteReq))) reqQv <- replicateM(mkFIFO);
	for ( Integer i = 0; i < valueOf(ways); i = i + 1 ) begin
		rule relayDmaWriteQ;
			dmaWritecQv[i].deq;
			dmaWriteQv[i].enq(dmaWritecQv[i].first);
		endrule

		SyncFIFOIfc#(Tuple2#(Bit#(8),DMAWriteReq)) sfifodma <- mkSyncFIFOFromCC(8,pcieclk);
		rule relaydmawrqsync(dmaWriteIn[i]-dmaWriteOut[i] > tpl_2(reqQv[i].first).words);
			reqQv[i].deq;
			dmaWriteOut[i] <= dmaWriteOut[i] + tpl_2(reqQv[i].first).words;
			sfifodma.enq(reqQv[i].first);
			
		endrule
		rule relaydmawrq ;
			sfifodma.deq;
			wm.enq[i].enq(sfifodma.first);
			/*
			case (i)
				0: wm20.enq[0].enq(sfifodma.first);
				1: wm20.enq[1].enq(sfifodma.first);
				2: wm21.enq[0].enq(sfifodma.first);
				3: wm21.enq[1].enq(sfifodma.first);
			endcase
			*/
		endrule
	end

	Reg#(Bit#(10)) dmaWriteCnt <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaWriteSrc <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule issuedmaWrite ( dmaWriteCnt == 0 );
		wm00.deq;
		let src = tpl_1(wm00.first);
		let cmd = tpl_2(wm00.first);
		
		pcie.dmaWriteReq(cmd.addr, cmd.words, cmd.tag);

		dmaWriteCnt <= cmd.words;
		dmaWriteSrc <= src;
		//$display("Issuing DMA write from src %d", src);
	endrule
	FIFO#(Bool) assertInterruptQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	rule assertInterrupt;
		assertInterruptQ.deq;
		pcie.assertInterrupt;
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
	FIFO#(Bit#(128)) enq2Q <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	
	FIFO#(Bit#(32)) enqchQ <- mkSizedFIFO(16);
	SyncFIFOIfc#(Bit#(32)) enqhQ <- mkSyncFIFOFromCC(8, pcieclk);
	FIFO#(Bit#(32)) enqh2Q <- mkFIFO(clocked_by pcieclk, reset_by pcierst);

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
	rule startEnqPacket ( enqState == 0 ); // && enqIdx - enqReceivedIdx < (1024*4)/32 ); // Just 4K
		enq2Q.deq;

		enqDataQ.enq(enq2Q.first);
		enqOffset <= ((enqOffset+32)&32'hfff); // Just 4K
		enqState <= 1;
		wm00.enq[1].enq(tuple2(255, DMAWriteReq{addr:enqOffset, words:2, tag:0}));
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
		enqDmaWriteQ.enq(DMAWordTagged{word:{zeroExtend(enqIdx), enqh2Q.first}, tag:0});
		enqState <= 0;
	endrule

	CompletionFIFOIfc#(Bit#(128), 7, 8) cbuf <- mkCompletionFIFO;
	FIFO#(Bit#(8)) availReadTagQ <- mkSizedFIFO(128);
	Reg#(Bit#(8)) readTagCounter <- mkReg(128);
	rule fillReadTagQ(readTagCounter > 0);
		readTagCounter <= readTagCounter - 1;
		availReadTagQ.enq(readTagCounter);
	endrule

	Vector#(ways, DMAUserIfc) users_;

	for ( Integer i = 0; i < valueOf(ways); i = i + 1 ) begin
		users_[i] = interface DMAUserIfc;
			method Action dmaWriteReq(Bit#(32) addr_, Bit#(10) words, Bit#(8) tag);
				//First 4K are reserved for hw->sw FIFO
				Bit#(32) addr__ = addr_ + (1024*4);
				reqQv[i].enq(tuple2(fromInteger(i), DMAWriteReq{addr:addr__, words:words, tag:tag}));
			endmethod
			method Action dmaWriteData(DMAWord data, Bit#(8) tag);
				dmaWritecQv[i].enq(DMAWordTagged{word:data, tag:tag});
				dmaWriteIn[i] <= dmaWriteIn[i] + 1;
			endmethod
			method Action dmaReadReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
			endmethod
			method ActionValue#(DMAWordTagged) dmaReadWord;
				return ?;
			endmethod
		endinterface: DMAUserIfc;
	end

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
