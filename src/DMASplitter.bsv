import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import Merge2::*;

interface DMAUserIfc;
	method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
	method Action dmaWriteData(DMAWord data, Bit#(8) tag);
	method Action dmaReadReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
	method ActionValue#(DMAWordTagged) dmaReadWord;
endinterface

interface DMASplitterIfc #(numeric type ways);
	method Action enq(Bit#(128) word);
	method Action deq;
	method Bit#(128) first;

	interface Vector#(ways, DMAUserIfc) users;
endinterface

module mkDMASplitter#(PcieUserIfc pcie) (DMASplitterIfc#(ways));
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;
	
	// Structures for the enq method
	Reg#(Bit#(32)) enqReceivedIdx <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	FIFO#(DMAWordTagged) enqDmaWriteQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	
	Vector#(4, Reg#(Bit#(32))) writeBuf <- replicateM(mkReg(0), clocked_by pcieclk, reset_by pcierst);
	SyncFIFOIfc#(Bit#(128)) ioRecvQ <- mkSyncFIFOToCC(8, pcieclk, pcierst);
	rule getWriteReq;
		let d <- pcie.dataReceive;
		if ( d.addr < 16 ) begin
			Bit#(2) offset = truncate(d.addr>>2);
			writeBuf[offset] <= d.data;
			if ( offset == 0 ) begin
				ioRecvQ.enq({writeBuf[3], writeBuf[2], writeBuf[1], d.data});
			end
		end else if ( d.addr == 16 ) begin
			enqReceivedIdx <= d.data;
		end
	endrule

	Vector#(ways, SyncFIFOIfc#(DMAWordTagged)) dmaWriteQv <- replicateM(mkSyncFIFOFromCC(16, pcieclk));
	Vector#(ways, Reg#(Bit#(10))) dmaWriteIn <- replicateM(mkReg(0));
	Vector#(ways, Reg#(Bit#(10))) dmaWriteOut <- replicateM(mkReg(0));

	
	// TODO Cleaner way to do this?
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm00 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm10 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm20 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	Merge2Ifc#(Tuple2#(Bit#(8),DMAWriteReq)) wm21 <- mkMerge2(clocked_by pcieclk, reset_by pcierst);
	rule merge10;
		wm20.deq;
		wm10.enq1(wm20.first);
	endrule
	rule merge11;
		wm21.deq;
		wm10.enq2(wm21.first);
	endrule
	rule merge0;
		wm10.deq;
		wm00.enq1(wm10.first);
	endrule
	Vector#(ways, FIFO#(Tuple2#(Bit#(8), DMAWriteReq))) reqQv <- replicateM(mkFIFO);
	for ( Integer i = 0; i < valueOf(ways); i = i + 1 ) begin
		SyncFIFOIfc#(Tuple2#(Bit#(8),DMAWriteReq)) sfifodma <- mkSyncFIFOFromCC(8,pcieclk);
		rule relaydmawrqsync(dmaWriteIn[i]-dmaWriteOut[i] > tpl_2(reqQv[i].first).words);
			reqQv[i].deq;
			dmaWriteOut[i] <= dmaWriteOut[i] + tpl_2(reqQv[i].first).words;
			sfifodma.enq(reqQv[i].first);
			
		endrule
		rule relaydmawrq ;
			sfifodma.deq;
			case (i)
				0: wm20.enq1(sfifodma.first);
				1: wm20.enq2(sfifodma.first);
				2: wm21.enq1(sfifodma.first);
				3: wm21.enq2(sfifodma.first);
			endcase
		endrule
	end
	//TODO rule to actually send data
	Reg#(Bit#(10)) dmaWriteCnt <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaWriteSrc <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule issuedmaWrite ( dmaWriteCnt == 0 );
		wm00.deq;
		let src = tpl_1(wm00.first);
		let cmd = tpl_2(wm00.first);
		
		pcie.dmaWriteReq(cmd.addr, cmd.words, cmd.tag);
		/*
		if ( src < 255 ) begin
			pcie.dmaWriteData(dmaWriteQv[src].first.word, cmd.tag);
			dmaWriteQv[src].deq;
		end else begin
			pcie.dmaWriteData(enqDmaWriteQ.first.word, cmd.tag);
			enqDmaWriteQ.deq;
		end
		*/

		dmaWriteCnt <= cmd.words;
		dmaWriteSrc <= src;
		$display("Issuing DMA write from src %d", src);
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
			if ( dmaWriteCnt == 1 ) pcie.assertInterrupt; // which is always
		end
		$display("Sending DMA write data from src %d", dmaWriteSrc );
	endrule

	SyncFIFOIfc#(Bit#(128)) enqQ <- mkSyncFIFOFromCC(8, pcieclk);
	Reg#(Bit#(32)) enqIdx <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(1)) enqState <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) enqOffset <- mkReg(0,clocked_by pcieclk, reset_by pcierst);
	FIFO#(Bit#(128)) enqDataQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);

	rule startEnqPacket ( enqIdx - enqReceivedIdx < (1024*4)/32 ); // Just 4K
		enqQ.deq;
		enqDataQ.enq(enqQ.first);
		enqOffset <= ((enqOffset+32)&32'hfff); // Just 4K
		enqIdx <= enqIdx + 1;
		enqState <= 1;
		wm00.enq2(tuple2(255, DMAWriteReq{addr:enqOffset, words:2, tag:0}));
		enqDmaWriteQ.enq(DMAWordTagged{word:{zeroExtend(enqIdx)}, tag:0});
		$display( "DMA enq data start" );

	endrule
	rule sendEnqPacket ( enqState == 1 );
		enqState <= 0;
		enqDataQ.deq;
		enqDmaWriteQ.enq(DMAWordTagged{word:enqDataQ.first, tag:0});
		$display( "DMA enq data next" );
	endrule


	Vector#(ways, DMAUserIfc) users_;

	for ( Integer i = 0; i < valueOf(ways); i = i + 1 ) begin
		users_[i] = interface DMAUserIfc;
			method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
				reqQv[i].enq(tuple2(fromInteger(i), DMAWriteReq{addr:addr, words:words, tag:tag}));
			endmethod
			method Action dmaWriteData(DMAWord data, Bit#(8) tag);
				dmaWriteQv[i].enq(DMAWordTagged{word:data, tag:tag});
				dmaWriteIn[i] <= dmaWriteIn[i] + 1;
			endmethod
			method Action dmaReadReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
			endmethod
			method ActionValue#(DMAWordTagged) dmaReadWord;
				return ?;
			endmethod
		endinterface: DMAUserIfc;
	end

	method Action enq(Bit#(128) word);
		enqQ.enq(word);
	endmethod
	method Action deq;
		ioRecvQ.deq;
	endmethod
	method Bit#(128) first;
		return ioRecvQ.first;
	endmethod
	interface users = users_;
endmodule
