/*
SW RPC
	sw->hw: IO write. IO read for flow control
	hw->sw: DMA write and interrupt. IO write for flow control

NOTE:
DMA writes doesn't really use tags...
*/


package PcieCtrl;

import Clocks :: *;

import Vector::*;
import FIFO::*;
import FIFOF::*;
import BRAM::*;
import BRAMFIFO::*;

import PcieImport::*;

import Scoreboard::*;
import MergeN::*;
import Shifter::*;

typedef struct {
	Bit#(16) requesterID;
	Bit#(8) tag;
	Bit#(20) addr;

	Bit#(3) tc;
	Bit#(1) td;
	Bit#(1) ep;
	Bit#(2) attr;
} IOReadReq deriving (Bits,Eq);

typedef struct {
	Bit#(128) tlp;
	Bit#(16) keep;
	Bit#(1) last;
} SendTLP deriving (Bits, Eq);

typedef struct {
	Bit#(20) addr;
	Bit#(32) data;
} IOWrite deriving (Bits,Eq);

typedef struct {
	Bit#(32) addr;
	Bit#(10) words;
	Bit#(8) tag;
} DMAReq deriving (Bits,Eq);

typedef 128 PcieWordSz;
typedef Bit#(PcieWordSz) PcieWord;
typedef 128 DMAWordSz;
typedef Bit#(DMAWordSz) DMAWord;

typedef struct {
	DMAWord word;
	Bit#(8) tag;
} DMAWordTagged deriving (Bits,Eq);

typedef TMul#(1024,16) IoUserSpaceOffset;
typedef 32 DMABufOffset;

typedef 8 DMAMaxWords;


interface PcieEngine;
interface PcieCtrlIfc ctrl;
interface PcieImportPins pins;
interface Clock sys_clk_o;
interface Reset sys_rst_n_o;
endinterface

(* synthesize *)
(* no_default_clock, no_default_reset *)
module mkPcieEngine#(Clock sys_clk_p, Clock sys_clk_n, Reset sys_rst_n, Clock emcclk) (PcieEngine);
	PcieImportIfc pcie <- mkPcieImport(sys_clk_p, sys_clk_n, sys_rst_n, emcclk);
	PcieCtrlIfc pcieCtrl <- mkPcieCtrl(pcie.user, clocked_by pcie.user_clk, reset_by pcie.user_reset);
	interface ctrl = pcieCtrl;
	interface pins = pcie.pins;
	interface sys_clk_o = pcie.sys_clk_o;
	interface Reset sys_rst_n_o = pcie.sys_rst_n_o;
endmodule


interface PcieUserIfc;
	interface Clock user_clk;
	interface Reset user_rst;
	method ActionValue#(IOWrite) dataReceive;
	method ActionValue#(IOReadReq) dataReq;
	method Action dataSend(IOReadReq ioreq, Bit#(32) data );

	method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words);
	method Action dmaWriteData(DMAWord data);
	method Action dmaReadReq(Bit#(32) addr, Bit#(10) words);
	method ActionValue#(DMAWord) dmaReadWord;

	method Action assertInterrupt;
	method Action assertUptrain;

	method Bit#(32) debug_data;
endinterface

interface PcieCtrlIfc;
	interface PcieUserIfc user;
endinterface

function Bit#(32) reverseEndian(Bit#(32) d);
	return {d[7:0], d[15:8], d[23:16], d[31:24]};
endfunction

module mkPcieCtrl#(PcieImportUser user) (PcieCtrlIfc);

	Integer dma_buf_offset = valueOf(DMABufOffset); //must match one in driver
	Integer io_userspace_offset = valueOf(IoUserSpaceOffset);
	Integer dma_max_words = valueOf(DMAMaxWords);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Bit#(7) type_rd32_io = 7'b0000010;
	Bit#(7) type_rd32_mem = 7'b0000000;
	Bit#(7) type_wr32_io = 7'b1000010;
	Bit#(7) type_wr32_mem = 7'b1000000;

	Bit#(7) type_completionn = 7'b0001010; //UNNEEDED probably
	Bit#(7) type_completionn4 = 7'b0101010; // ditto

	Bit#(7) type_completion = 7'b1001010;
	Bit#(7) type_completion4 = 7'b1101010; // ditto

	Reg#(Bit#(32)) read32data <- mkReg(32'haaaaaaaa);
	Reg#(Bit#(32)) tlpCount <- mkReg(0);

	Reg#(Bit#(10)) rxOffset <- mkReg(0);
	Vector#(4, Reg#(Bit#(1))) leddata <- replicateM(mkReg(0));

	
	FIFO#(Bit#(PcieKeepSz)) tlpKeepQ <- mkSizedFIFO(32);
	FIFO#(Bit#(PcieInterfaceSz)) tlpQ <- mkSizedFIFO(32);
	//swjun improve timing...
	//FIFO#(Bit#(PcieInterfaceSz)) tlp2Q <- mkSizedFIFO(32);
	//FIFO#(Bit#(PcieInterfaceSz)) tlp3Q <- mkSizedFIFO(32);
	FIFO#(Bit#(PcieInterfaceSz)) tlp2Q <- mkFIFO;
	FIFO#(Bit#(PcieInterfaceSz)) tlp3Q <- mkFIFO;
	Reg#(Maybe#(Bit#(PcieInterfaceSz))) partBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(PcieKeepSz)) keepBuffer <- mkReg(0);
	Reg#(Bit#(5)) partOffset <- mkReg(0);

	BRAM2Port#(Bit#(12), Bit#(32)) configBuffer <- mkBRAM2Server(defaultValue); //16K
	FIFO#(Bool) bufidxRequestedWriteQ <- mkFIFO;

	Reg#(Bit#(32)) debugCode <- mkReg(0);
	
	//FIFO#(Tuple2#(Bit#(8),Bit#(10))) readBurstQ <- mkSizedFIFO(4);
	FIFO#(Tuple2#(Bit#(8),Bit#(10))) readBurstQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(8),Bit#(10))) readBurst2Q <- mkFIFO;
	BRAM2Port#(Bit#(8),Tuple2#(Bit#(10),Bit#(10))) tagMap <- mkBRAM2Server(defaultValue); // tag, total words,words recv
	BRAM2Port#(Bit#(10), Bit#(128)) readReorder <- mkBRAM2Server(defaultValue); // 7 bit tag, 3 bit burst offset (max 8 words per burst)
	ScoreboardIfc#(4,Bit#(8)) readCompletionsb <- mkScoreboard;
	Reg#(Bit#(8)) freeTagCnt <- mkReg(0);
	FIFO#(Bit#(8)) freeReadTagQ <- mkSizedBRAMFIFO(128);
	FIFO#(Bit#(8)) freeWriteTagQ <- mkSizedBRAMFIFO(128);
	rule insertFreeTag (freeTagCnt != 128);
		freeTagCnt <= freeTagCnt + 1;
		freeReadTagQ.enq(freeTagCnt);
		freeWriteTagQ.enq(freeTagCnt+128);
	endrule

	rule relayReadBurst;
		readBurstQ.deq;
		readBurst2Q.enq(readBurstQ.first);
	endrule


	FIFO#(DMAWordTagged) dmaReadWordQ <- mkSizedBRAMFIFO(128);
	FIFO#(DMAWordTagged) dmaReadWordRQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(8),Bit#(10))) burstUpdReqQ <-mkFIFO;
	FIFO#(Tuple2#(Bit#(8),Bit#(10))) readDoneTagQ <- mkFIFO;
	Reg#(Tuple5#(Bit#(8),Bit#(10),Bit#(10),Bit#(10),Bit#(10))) tagWordsLeft <- mkReg(tuple5(0,0,0,0,0));
	rule updateReadBurst1 ( freeTagCnt == 128 );
		let burst = readBurst2Q.first;
		let tag = tpl_1(burst);
		let words = tpl_2(burst);
			
		if ( !readCompletionsb.search1(tag) ) begin
			tagMap.portB.request.put(BRAMRequest{write:False, responseOnWrite:False, address:tag, datain:?});
			readBurst2Q.deq;
			readCompletionsb.enq(tpl_1(burst));
			burstUpdReqQ.enq(burst);
		end
	endrule

	FIFO#(Tuple2#(Bit#(10),Bit#(10))) tagMapReadAQ <- mkFIFO;
	FIFO#(Bit#(8)) freeReadTagFQ <- mkFIFO;
	rule getTagMapReadA;
		let v <- tagMap.portB.response.get();
		tagMapReadAQ.enq(v);
	endrule
	rule relayFreeReadTag;
		freeReadTagFQ.deq;
		freeReadTagQ.enq(freeReadTagFQ.first);
	endrule

	rule updateReadBurst2 (tpl_3(tagWordsLeft) == 0 && freeTagCnt == 128);
		tagMapReadAQ.deq;
		let v = tagMapReadAQ.first;
		let req = tpl_1(v);
		let done = tpl_2(v);
		
		burstUpdReqQ.deq;
		let burst = burstUpdReqQ.first;
		let tag = tpl_1(burst);
		let words = tpl_2(burst);
			

		let newdone = done;
		let newwords = words;
		if ( done + words >= req ) begin // read v should never be 0!
			newdone = req;
			newwords = req - done; 
		end
		else begin
			newdone = done + words;
		end
		
		
		readCompletionsb.deq;

		tagWordsLeft <= tuple5(tag,done,newwords,0,req);

		tagMap.portB.request.put(BRAMRequest{write:True,responseOnWrite:False,address:tag,datain:tuple2(req,newdone)});
	endrule
	rule relayDmaReadrQ;
		dmaReadWordQ.deq;
		dmaReadWordRQ.enq(dmaReadWordQ.first);
	endrule
	
	FIFO#(Tuple2#(Bit#(8),Bit#(10))) orderedReadDoneTagQ <- mkSizedFIFO(4); //TODO
	FIFO#(Bit#(8)) dmaReadTagOrderQ <- mkSizedBRAMFIFO(128);
	ByteShiftIfc#(Bit#(128), 7) doneShifter <- mkPipelineLeftShifterBits;
	ByteShiftIfc#(Bit#(128), 7) orderShifter <- mkPipelineLeftShifterBits;
	FIFO#(Bit#(8)) orderTagBypassQ <- mkSizedFIFO(8);
	Reg#(Bit#(128)) doneTagMap <- mkReg(0);
	Reg#(Bit#(128)) orderTagMap <- mkReg(0);
	BRAM2Port#(Bit#(8),Tuple2#(Bit#(8),Bit#(10))) doneMap <- mkBRAM2Server(defaultValue); // tag, total words,words recv
	rule applyDoneMap;
		readDoneTagQ.deq;
		let d = readDoneTagQ.first;
		doneMap.portA.request.put(BRAMRequest{write:True,responseOnWrite:False,address:tpl_1(d),datain:d});
		doneShifter.rotateByteBy(1,truncate(tpl_1(d))); //tag
	endrule
	rule procDoneShift;
		let v <- doneShifter.getVal;
		doneTagMap <= doneTagMap ^ v;
	endrule
	rule shiftOrder;
		let tag = dmaReadTagOrderQ.first;
		dmaReadTagOrderQ.deq;
		orderShifter.rotateByteBy(1,truncate(tag));
		orderTagBypassQ.enq(tag);
	endrule
	Reg#(Maybe#(Bit#(128))) curOrderTag <- mkReg(tagged Invalid);
	FIFO#(Bit#(8)) doneReorderedTagQ <- mkFIFO;
	FIFO#(Bit#(128)) orderShiftedQ <- mkFIFO;
	rule forwardShifted;
		let v <- orderShifter.getVal;
		orderShiftedQ.enq(v);
	endrule
	rule compareOrder;
		let ot = fromMaybe(?, curOrderTag);
		if ( isValid(curOrderTag) ) begin
			if ( (ot&(orderTagMap ^ doneTagMap)) != 0 ) begin
				orderTagMap <= orderTagMap ^ ot;
				curOrderTag <= tagged Invalid;

				let tag = orderTagBypassQ.first;
				orderTagBypassQ.deq;
				doneReorderedTagQ.enq(tag);
			end
		end else begin
			orderShiftedQ.deq;
			let v = orderShiftedQ.first;

			if ( (v&(orderTagMap ^ doneTagMap)) != 0 ) begin
				orderTagMap <= orderTagMap ^ v;
				//curOrderTag <= tagged Invalid;

				let tag = orderTagBypassQ.first;
				orderTagBypassQ.deq;
				doneReorderedTagQ.enq(tag);
			end else begin
				curOrderTag <= tagged Valid v;
			end
		end

	endrule
	rule reqDoneTag;
		doneReorderedTagQ.deq;
		let tag = doneReorderedTagQ.first;
		doneMap.portB.request.put(BRAMRequest{write:False,responseOnWrite:False,address:tag,datain:?});
	endrule
	rule forwardDoneTag;
		let d <- doneMap.portB.response.get;
		orderedReadDoneTagQ.enq(d);
	endrule

	rule writeReadBuffer (tpl_3(tagWordsLeft) > 0);
		let tag = tpl_1(tagWordsLeft);
		let off = tpl_2(tagWordsLeft);
		let words = tpl_3(tagWordsLeft);
		let ioff = tpl_4(tagWordsLeft);
		let req = tpl_5(tagWordsLeft);


		if ( words <= 4 && off+ioff+4 >= req ) begin
			words = 0;
			readDoneTagQ.enq(tuple2(tag, off+ioff+4));
		end
		else words = words - 4;
		
		tagWordsLeft <= tuple5(tag,off,words,ioff+4, req);
		dmaReadWordRQ.deq;
		let word = dmaReadWordRQ.first;


		
		Bit#(10) writeoff = (zeroExtend(tag)<<3)|((zeroExtend(off)+zeroExtend(ioff))>>2);
		readReorder.portA.request.put(BRAMRequest{write:True,responseOnWrite:False,address:writeoff,datain:word.word});
	endrule
	Reg#(Tuple3#(Bit#(8),Bit#(10),Bit#(10))) readFlushTag <- mkReg(tuple3(0,0,0)); //tag, req, curword
	FIFO#(DMAWord) dmaReadOutQ <- mkSizedBRAMFIFO(dma_max_words*8);
	FIFO#(DMAWord) dmaReadOutRQ <- mkFIFO;
	Reg#(Bit#(8)) dmaReadOutCntUp <- mkReg(0);
	Reg#(Bit#(8)) dmaReadOutCntDn <- mkReg(0);
	rule flushReadTag ;
		let wleft = tpl_3(readFlushTag);
		if ( wleft == 0 ) begin
			if (dmaReadOutCntUp-dmaReadOutCntDn < fromInteger(dma_max_words*7)  ) begin
				orderedReadDoneTagQ.deq;
				let r_ = orderedReadDoneTagQ.first;
				let tag = tpl_1(r_);
				let words = tpl_2(r_);


				Bit#(10) readoff = (zeroExtend(tag)<<3);
				readReorder.portB.request.put(BRAMRequest{write:False,responseOnWrite:False,address:readoff,datain:?});
				let wordsleft = 0;
				if ( words > 4 ) wordsleft = words - 4;
				readFlushTag <= tuple3(tag,words, wordsleft);

				dmaReadOutCntUp <= dmaReadOutCntUp + 1;

				freeReadTagFQ.enq(tag);
			end
		end else begin
			let tag = tpl_1(readFlushTag);
			let words = tpl_2(readFlushTag);
			let wordsleft = 0;

			if ( wleft > 4 ) wordsleft = wleft - 4;


			readFlushTag <= tuple3(tag,words, wordsleft);
			Bit#(10) readoff = (zeroExtend(tag)<<3)|((zeroExtend(words-wleft))>>2);
			readReorder.portB.request.put(BRAMRequest{write:False,responseOnWrite:False,address:readoff,datain:?});
			dmaReadOutCntUp <= dmaReadOutCntUp + 1;
		end
	endrule
	rule flushReadOrdered;
		let v <- readReorder.portB.response.get();
		dmaReadOutQ.enq(v);
	endrule
	rule relayFlushReadOrdered;
		dmaReadOutQ.deq;
		dmaReadOutRQ.enq(dmaReadOutQ.first);
	endrule



	rule recvTLP;
		Bit#(PcieInterfaceSz) tlp <- user.receiveData;
		Bit#(PcieKeepSz) keep <- user.receiveKeep;
		//Bit#(1) last <- user.receiveLast;
		Bit#(22) ruser <- user.receiveUser;
		Bit#(1) last = ruser[21];


		Bool sof_present = ruser[14] == 1 ? True : False;
		Bool sof_mid = ruser[13:10] == 4'b1000 ? sof_present : False;
		Bool sof_right = ruser[13:10] == 4'b0000 ? sof_present : False;

		if ( sof_right ) begin
			partOffset <= 0;
			partBuffer <= tagged Invalid;

			tlpQ.enq(tlp);
			tlpKeepQ.enq(keep);
		end else if ( sof_mid ) begin
			partOffset <= 8;
			partBuffer <= tagged Valid (tlp>>64);
			keepBuffer <= (keep>>8);

			Bit#(64) curPart = truncate(tlp);
			if ( isValid(partBuffer) ) begin
				let pb = fromMaybe(?, partBuffer);
				Bit#(64) lastPart = truncate(pb);
				tlpQ.enq({curPart, lastPart});

				Bit#(8) lastKeep = truncate(keepBuffer);
				Bit#(8) curKeep = truncate(keep);
				tlpKeepQ.enq({curKeep, lastKeep});
			end
		end else begin
			if ( partOffset[3] == 0 ) begin
				tlpQ.enq(tlp);
				tlpKeepQ.enq(keep);
			end else begin
				if ( last != 1 ) begin
					partBuffer <= tagged Valid (tlp>>64);
					keepBuffer <= (keep>>8);
				end
				else partBuffer <= tagged Invalid;

				//if ( isValid(partBuffer) ) begin
					Bit#(64) lastPart = truncate(fromMaybe(?,partBuffer));
					Bit#(64) curPart = truncate(tlp);
					tlpQ.enq({curPart, lastPart});

					Bit#(8) lastKeep = truncate(keepBuffer);
					Bit#(8) curKeep = truncate(keep);
					tlpKeepQ.enq({curKeep, lastKeep});
				//end
			end
		end
	endrule

	Reg#(Bit#(10)) dmaSendWords <- mkReg(0);

	FIFO#(IOReadReq) ioReadQ <- mkSizedFIFO(8);
	FIFO#(SendTLP) sendTLPQ <- mkSizedFIFO(8);
	MergeNIfc#(8,SendTLP) sendTLPm <- mkMergeN;

	FIFOF#(IOWrite) userWriteQ <- mkSizedBRAMFIFOF(512);
	FIFO#(IOWrite) userWrite1Q <- mkFIFO;
	
	FIFO#(IOReadReq) userReadQ0 <- mkFIFO;
	FIFO#(IOReadReq) userReadQ1 <- mkSizedBRAMFIFO(512);
	FIFO#(IOReadReq) userReadQ2 <- mkFIFO;

	Reg#(Bit#(16)) userWriteBudget <- mkReg(0);
	Reg#(Bit#(32)) userWriteEmit <- mkReg(0);
	Reg#(Bit#(32)) userReadEmit <- mkReg(0);

	Reg#(Bit#(10)) completionRecvLength <- mkReg(0);
	Reg#(Bit#(8)) completionRecvTag <- mkReg(0);

	Reg#(Bit#(32)) dmaReadBuffer <- mkReg(0);

	rule procCompletionTLP( completionRecvLength > 0 );
		let tlp = tlpQ.first;
		tlpQ.deq;
		tlpKeepQ.deq;

		tlpCount <= tlpCount + 1;

		dmaReadBuffer <= reverseEndian(truncate(tlp>>(32*3)));
		Bit#(32) data0 = reverseEndian(truncate(tlp));
		Bit#(32) data1 = reverseEndian(truncate(tlp>>32));
		Bit#(32) data2 = reverseEndian(truncate(tlp>>64));

		dmaReadWordQ.enq(DMAWordTagged{word:{data2,data1,data0,dmaReadBuffer}, tag:completionRecvTag});
		

		if ( completionRecvLength >= 4 ) begin
			completionRecvLength <= completionRecvLength - 4;
		end else begin
			completionRecvLength <= 0;
		end
	endrule

	rule filterStatReadTLP( completionRecvLength == 0 );
		let tlp = tlpQ.first;
		tlpQ.deq;
		let keep = tlpKeepQ.first;
		tlpKeepQ.deq;
		
		Bit#(7) ptype = tlp[30:24];
		
		// don't know why, but rd32 generates type_rd32_mem
		if ( ptype == type_rd32_io ||
			ptype == type_rd32_mem ) begin
			let len = tlp[9:0];
			let attr = tlp[13:12];
			let td = tlp[15];
			let ep = tlp[14];
			let tc = tlp[22:20];
			let be = tlp[3+32:32];
			Bit#(8) tag = tlp[15+32:8+32];
			Bit#(16) rid = tlp[31+32:16+32];
			Bit#(32) addr = {tlp[31+64:2+64],2'b00};

			Bit#(32) cdw0 = {
				1'b0,
				2'b10,
				5'ha,
				1'b0,
				tc,4'h0,td,
				//3'b0, 4'b0,1'b0,
				ep,attr,2'b0,10'h1
				//1'b0,2'b0,2'b0,10'h1
			};
			Bit#(32) cdw1 = {
				user.cfg_completer_id,4'b0000,
				12'h4// read32 only...
			};
			Bit#(32) cdw2 = {
				rid,tag,1'b0,
				addr[6:0]
			};
			let cdw3 = reverseEndian(read32data);

			Bit#(20) internalAddr = truncate(addr);
			if ( internalAddr == 0 ) begin // magic number
				cdw3 = reverseEndian(32'hc001d00d);
				//sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
				sendTLPm.enq[0].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else if ( internalAddr == 4) begin
				cdw3 = reverseEndian(debugCode);
				sendTLPm.enq[0].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else if ( internalAddr == fromInteger(io_userspace_offset)-8) begin
				cdw3 = reverseEndian(userReadEmit);
				//sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
				sendTLPm.enq[0].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else if ( internalAddr == fromInteger(io_userspace_offset)-4) begin
				cdw3 = reverseEndian(userWriteEmit);
				//sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
				sendTLPm.enq[0].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else begin
				tlp2Q.enq(tlp);
			end
		end
		else if ( ptype == type_completion 
			|| ptype == type_completion4
			|| ptype == type_completionn
			|| ptype == type_completionn4
			) begin
			Bit#(10) length = tlp[9:0];
			Bit#(8) tag = tlp[15+64:8+64];
			Bit#(32) data = tlp[31+96:96];
		
			if ( length <= 1 ) begin // should not happen but...
				dmaReadWordQ.enq(DMAWordTagged{word:tlp, tag:tag}); //debug
			end

			completionRecvLength <= length -1; //one dw already arrived
			completionRecvTag <= tag;
			dmaReadBuffer <= reverseEndian(data);
			readBurstQ.enq(tuple2(tag, length));
		end
		else begin
			tlp2Q.enq(tlp);
		end
	endrule


	rule procTLP( completionRecvLength == 0 ); 
		let tlp = tlp2Q.first;
		tlp2Q.deq;
		tlpCount <= tlpCount + 1;

		Bit#(7) ptype = tlp[30:24];
		
		// don't know why, but rd32 generates type_rd32_mem
		if ( ptype == type_rd32_io ||
			ptype == type_rd32_mem ) begin
			let len = tlp[9:0];
			let attr = tlp[13:12];
			let td = tlp[15];
			let ep = tlp[14];
			let tc = tlp[22:20];
			let be = tlp[3+32:32];
			Bit#(8) tag = tlp[15+32:8+32];
			Bit#(16) rid = tlp[31+32:16+32];
			Bit#(32) addr = {tlp[31+64:2+64],2'b00};

			Bit#(20) internalAddr = truncate(addr);

			if ( internalAddr < fromInteger(io_userspace_offset) ) begin
				configBuffer.portA.request.put(
					BRAMRequest{
					write:False, responseOnWrite:False,
					address:truncate(internalAddr>>2),
					datain:?
					}
				);
				ioReadQ.enq(IOReadReq{requesterID:rid,tag:tag,addr:truncate(addr),
					tc:tc,td:td,ep:ep,attr:attr});
			end
			else begin
					userReadQ0.enq(IOReadReq{requesterID:rid,tag:tag,addr:truncate(addr)-fromInteger(io_userspace_offset),
						tc:tc,td:td,ep:ep,attr:attr});
					//userReadQ.enq(IOReadReq{requesterID:rid,tag:tag,addr:truncate(addr)-fromInteger(io_userspace_offset),
						//tc:tc,td:td,ep:ep,attr:attr});
			end
		end
		else if ( ptype == type_wr32_io 
		 || ptype == type_wr32_mem ) begin
		 	tlp3Q.enq(tlp);
		end 
	endrule

	rule relayUserReadQ0;
		userReadQ0.deq;
		userReadQ1.enq(userReadQ0.first);
	endrule
	rule relayUserReadQ1;
		userReadQ1.deq;
		userReadQ2.enq(userReadQ1.first);
	endrule

	rule completeIORead;
		ioReadQ.deq;
		let ioreq = ioReadQ.first;
		let v <- configBuffer.portA.response.get();

		Bit#(32) cdw0 = {
			1'b0,
			2'b10,
			5'ha,
			1'b0,
			ioreq.tc,4'h0,ioreq.td,
			ioreq.ep,ioreq.attr,2'b0,10'h1
		};
		Bit#(32) cdw1 = {
			user.cfg_completer_id,4'b0000,
			12'h4// read32 only...
		};
		Bit#(32) cdw2 = {
			ioreq.requesterID,ioreq.tag,1'b0,
			ioreq.addr[6:0]
		};
		let cdw3 = reverseEndian(v);
		//sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
		sendTLPm.enq[2].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
	endrule

	rule procIOWrite;
		let tlp = tlp3Q.first;
		tlp3Q.deq;
		Bit#(7) ptype = tlp[30:24];

		let attr = tlp[13:12];
		let td = tlp[15];
		let ep = tlp[14];
		let tc = tlp[22:20];
		let be = tlp[3+32:32];
		Bit#(8) tag = tlp[15+32:8+32];
		Bit#(16) rid = tlp[31+32:16+32];
		Bit#(32) addr = {tlp[31+64:2+64],2'b00};
		Bit#(32) data = reverseEndian(tlp[31+96:96]);
		
		read32data <= data;
		Bit#(20) internalAddr = truncate(addr);

		if ( internalAddr == 0 ) begin 
			userWriteEmit <= 0;
			userReadEmit <= 0;
		end else
		if ( internalAddr < fromInteger(io_userspace_offset) ) begin
			configBuffer.portA.request.put(
				BRAMRequest{
				write:True,
				responseOnWrite:False,
				address:truncate(internalAddr>>2),
				datain:data
				}
			);
		end
		else if (internalAddr >= fromInteger(io_userspace_offset) ) begin
			userWrite1Q.enq(IOWrite{addr:internalAddr-fromInteger(io_userspace_offset), data:data});
		end

		Bit#(32) cdw0 = {
			1'b0,
			2'b00, // 3DW header, no data
			5'ha, //For Cpl (without data)
			1'b0,
			3'b0,4'b0,1'b0, //tc,4'h0,td,
			1'b0,2'b0,2'b0,10'h1//ep,attr,2'b0,10'h1
		};
		Bit#(32) cdw1 = {
			user.cfg_completer_id,4'b0000,
			//12'h4// read32 only...
			12'h0 // completion with no data
		};
		Bit#(32) cdw2 = {
			rid,tag,1'b0,
			addr[6:0]
		};
		let cdw3 = 0;
		if ( ptype == type_wr32_io ) begin
			//sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'h0fff,last:1'b1});
			sendTLPm.enq[1].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'h0fff,last:1'b1});
		end
	endrule

	FIFO#(Bit#(32)) dmaWriteBufAddrQ <- mkFIFO;
	FIFO#(Bit#(32)) dmaReadBufAddrQ <- mkFIFO;
	rule relayBufIdxRead;
		let busAddr <- configBuffer.portB.response.get;
		bufidxRequestedWriteQ.deq;
		let write = bufidxRequestedWriteQ.first;
		if ( write ) dmaWriteBufAddrQ.enq(busAddr);
		else dmaReadBufAddrQ.enq(busAddr);
	endrule


	FIFO#(DMAReq) dmaReadReqQ <- mkFIFO;
	FIFO#(DMAReq) dmaPageReadReqQ <- mkSizedFIFO(8);
	Reg#(Bit#(32)) dmaReadStartAddr <- mkReg(0);
	Reg#(Bit#(10)) dmaReadWords <- mkReg(0);
	Reg#(Bit#(8)) dmaReadTag <- mkReg(0);
	rule splitDmaReadReq( dmaReadWords == 0 );
		let req = dmaReadReqQ.first;
		dmaReadReqQ.deq;
		dmaReadStartAddr <= {truncate(req.addr>>4), 4'b0000};
		dmaReadWords <= req.words;
		dmaReadTag <= req.tag;
	endrule
	rule splitDmaReadReq2( dmaReadWords > 0 );
		let bufidx = dmaReadStartAddr>>12; //4k pages
		let nextPage = bufidx+1;
		let internal = (nextPage<<12)-dmaReadStartAddr;
		Bit#(10) internalWords = truncate(internal>>4);

		Bit#(10) toread = dmaReadWords;
		if ( toread > fromInteger(dma_max_words) ) toread = fromInteger(dma_max_words);

		if ( internalWords > toread ) begin
			dmaReadWords <= dmaReadWords - toread;
			let tag = freeReadTagQ.first;
			freeReadTagQ.deq;
			dmaPageReadReqQ.enq(DMAReq{addr:zeroExtend(dmaReadStartAddr[11:0]), words:toread, tag:tag});
			tagMap.portA.request.put(BRAMRequest{write:True,responseOnWrite:False,address:tag,datain:tuple2(toread<<2,0)}); // DWORD words
			dmaReadStartAddr <= dmaReadStartAddr + (zeroExtend(toread)<<4);
		end else begin
			let tag = freeReadTagQ.first;
			freeReadTagQ.deq;
			dmaReadWords <= dmaReadWords - internalWords;
			dmaReadStartAddr <= nextPage<<12;
			dmaPageReadReqQ.enq(DMAReq{addr:zeroExtend(dmaReadStartAddr[11:0]), words:internalWords, tag:tag});
			tagMap.portA.request.put(BRAMRequest{write:True,responseOnWrite:False,address:tag,datain:tuple2(internalWords<<2,0)}); // DWORD words
		end

		//let bufidx = addr>>12; //4k pages
		Bit#(12) bufoffset = fromInteger(dma_buf_offset/4);
		bufoffset = bufoffset + truncate(bufidx);
		bufidxRequestedWriteQ.enq(False);
		configBuffer.portB.request.put(
			BRAMRequest{
			write:False, responseOnWrite:False,
			address: bufoffset,
			datain:?
			}
		);
	endrule

	rule generateDmaReadTLP;
		let req = dmaPageReadReqQ.first;
		dmaPageReadReqQ.deq;

		//let busAddr <- configBuffer.portB.response.get;
		let busAddr = dmaReadBufAddrQ.first;
		dmaReadBufAddrQ.deq;

		dmaReadTagOrderQ.enq(req.tag);
		//debugCode <= debugCode + zeroExtend(req.words);


		let dmaAddr = busAddr + req.addr;
		//FIXME maybe this needs to be in bytes?
		Bit#(10) dmaWords = req.words;
		
		Bit#(32) cdw0 = {
			1'b0,
			2'b00, //read
			5'h0,
			1'b0, //R
			3'h0, //Transfer Channel (virt.channel)
			4'h0, //R

			1'h0, //TD
			1'h0, //EP
			2'h0, //ATTR
			2'b0, //R
			(dmaWords<<2)//32 bit words
		};
		Bit#(32) cdw1 = {
			user.cfg_completer_id,
			req.tag, 
			4'hf, 4'hf
			};
		Bit#(32) cdw2 = {
			truncate(dmaAddr>>2),
			2'b00
		};

		Bit#(32) cdw3 = 0;

		sendTLPm.enq[3].enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'h0fff,last:1'b1});
	endrule

	// BEGIN DMA WRITE RELATED ///////////////////////////////////
	//
	
	FIFO#(DMAReq) dmaWriteReqQ <- mkFIFO;
	FIFO#(DMAWord) dmaWriteWordQ <- mkSizedFIFO(32);
	Reg#(Bit#(10)) dmaWriteWordIn <- mkReg(0);
	Reg#(Bit#(10)) dmaWriteWordOut <- mkReg(0);
	Reg#(DMAWord) dmaWriteBuf <- mkReg(0);

	Reg#(Bit#(32)) dmaStartAddr <- mkReg(0);
	rule splitDmaWriteReq (dmaSendWords == 0);
		dmaWriteReqQ.deq;
		let req = dmaWriteReqQ.first;

		dmaStartAddr <= {truncate(req.addr>>4), 4'b0000};
		//dmaStartAddr <= req.addr;
		dmaSendWords <= req.words;
	endrule

	FIFO#(Bit#(8)) busyWriteTagQ <- mkSizedBRAMFIFO(128);
	FIFO#(DMAReq) dmaPageWriteReqQ <- mkSizedFIFO(8);
	FIFO#(Bit#(8)) freeWriteTagStageQ <- mkFIFO;
	rule relayFreeWriteTag;
		freeWriteTagQ.deq;
		freeWriteTagStageQ.enq(freeWriteTagQ.first);
	endrule
	(* descending_urgency = "splitDmaWriteReq2, splitDmaReadReq2" *)
	rule splitDmaWriteReq2 (dmaSendWords > 0 );

		let bufidx = dmaStartAddr>>12; //4k pages
		let nextPage = bufidx+1;
		let internal = (nextPage<<12)-dmaStartAddr;
		Bit#(10) internalWords = truncate(internal>>4);

		Bit#(10) towrite = dmaSendWords;
		if ( towrite >= fromInteger(dma_max_words) ) towrite = fromInteger(dma_max_words);

		freeWriteTagStageQ.deq;
		let tag = freeWriteTagStageQ.first;
		busyWriteTagQ.enq(tag);

		if ( internalWords > towrite ) begin
			dmaSendWords <= dmaSendWords - towrite;
			dmaPageWriteReqQ.enq(DMAReq{addr:zeroExtend(dmaStartAddr[11:0]), words:towrite, tag:tag});
			dmaStartAddr <= dmaStartAddr + (zeroExtend(towrite)<<4);
		end else begin
			dmaSendWords <= dmaSendWords - internalWords;
			dmaStartAddr <= nextPage<<12;
			dmaPageWriteReqQ.enq(DMAReq{addr:zeroExtend(dmaStartAddr[11:0]), words:internalWords, tag:tag});
		end
		
		Bit#(12) bufoffset = fromInteger(dma_buf_offset/4);
		bufoffset = bufoffset + truncate(bufidx);
		bufidxRequestedWriteQ.enq(True);
		configBuffer.portB.request.put(
			BRAMRequest{
			write:False, responseOnWrite:False,
			address: bufoffset,
			datain:?
			}
		);
	endrule

	//Reg#(Bit#(128)) dataShiftBuffer <- mkReg(0);
	Reg#(Bit#(10)) dataWordsRemain <- mkReg(0);
	rule generateHeaderTLP ( dataWordsRemain == 0 && dmaWriteWordIn-dmaWriteWordOut >= dmaPageWriteReqQ.first().words );

		//let busAddr <- configBuffer.portB.response.get;
		let busAddr = dmaWriteBufAddrQ.first;
		dmaWriteBufAddrQ.deq;

		let req = dmaPageWriteReqQ.first;
		dmaPageWriteReqQ.deq;

		let dmaAddr = busAddr + req.addr;
		Bit#(10) dmaWords = req.words;
		//let dmaWords = 8;
		//debugCode <= debugCode + (zeroExtend(req.words)<<16);
		
		dmaWriteWordQ.deq;
		let data = dmaWriteWordQ.first;
		dmaWriteBuf <= (data>>32);
		dmaWriteWordOut <= dmaWriteWordOut + dmaWords;

		Bit#(32) cdw0 = {
			1'b0,
			2'b10, //write
			5'h0,
			1'b0, //R
			3'h0, //Transfer Channel (virt.channel)
			4'h0, //R

			1'h0, //TD
			1'h0, //EP
			2'h0, //ATTR
			2'b0, //R
			(dmaWords<<2)//32 bit words
		};
		Bit#(32) cdw1 = {
			user.cfg_completer_id,
			req.tag, //8'h00, // TAG
			4'b1111, 4'hf
			};
		Bit#(32) cdw2 = {
			truncate(dmaAddr>>2),
			2'b00
			//ioreq.requesterID,ioreq.tag,1'b0,
			//ioreq.addr
		};

		//let cdw3 = reverseEndian(32'hf00dbeef);
		Bit#(32) cdw3 = reverseEndian(truncate(data));

		sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b0});
		dataWordsRemain <= dmaWords;
	endrule

	rule generateDataTLP ( dataWordsRemain > 0 );

		dataWordsRemain <= dataWordsRemain - 1;

		if ( dataWordsRemain > 1 ) begin
			dmaWriteWordQ.deq;
			let d = dmaWriteWordQ.first;
			Bit#(32) h = truncate(d);
			dmaWriteBuf <= (d>>32);

			let data = dmaWriteBuf | (zeroExtend(h)<<(128-32));

			sendTLPQ.enq(SendTLP{tlp:{
				reverseEndian(data[127:96]),
				reverseEndian(data[95:64]),
				reverseEndian(data[63:32]),
				reverseEndian(data[31:0])
				},keep:16'hffff,last:1'b0});
		end else begin
			busyWriteTagQ.deq;
			freeWriteTagQ.enq(busyWriteTagQ.first);

			let data = dmaWriteBuf;
			sendTLPQ.enq(SendTLP{tlp:{
				reverseEndian(data[127:96]),
				reverseEndian(data[95:64]),
				reverseEndian(data[63:32]),
				reverseEndian(data[31:0])
				},keep:16'h0fff,last:1'b1});
		end
	endrule



	//
	// END DMA WRITE RELATED //////////////////////////////////////


	rule relayTLPm( dataWordsRemain == 0 );
		sendTLPm.deq;
		sendTLPQ.enq(sendTLPm.first);
	endrule
	rule relayTLP;
		sendTLPQ.deq;
		let tlp = sendTLPQ.first;
		let d = tlp.tlp;
		let last = tlp.last;
		let keep = tlp.keep;

		user.sendData(d);
		user.sendKeep(keep);
		user.sendLast(last);
	endrule

	FIFO#(SendTLP) userSendTLPQ <- mkFIFO;
	//(* descending_urgency = "filterStatReadTLP, procTLP, generateDataTLP, generateHeaderTLP, completeIORead, generateDmaReadTLP, relayUserSendTLP" *)
	(* descending_urgency = "generateDataTLP, generateHeaderTLP" *)
	rule relayUserSendTLP;
		userSendTLPQ.deq;
		//sendTLPQ.enq(userSendTLPQ.first);
		sendTLPm.enq[5].enq(userSendTLPQ.first);
	endrule

	FIFO#(IOWrite) userWrite2Q <- mkFIFO;
	rule relayUserWriteQ;
		userWrite1Q.deq;
		userWriteQ.enq(userWrite1Q.first);
	endrule
	rule relayUserWrite2Q;
		userWriteQ.deq;
		userWrite2Q.enq(userWriteQ.first);
	endrule

	interface PcieUserIfc user;
		interface Clock user_clk = curClk;
		interface Reset user_rst = curRst;

		method ActionValue#(IOWrite) dataReceive;
			userWrite2Q.deq;
			userWriteEmit <= userWriteEmit + 1;
			return userWrite2Q.first;
		endmethod
		method ActionValue#(IOReadReq) dataReq;
			userReadQ2.deq;

			//required for flow control
			userReadEmit <= userReadEmit + 1;
			return userReadQ2.first;
		endmethod
		method Action dataSend(IOReadReq ioreq, Bit#(32) data );
			Bit#(32) cdw0 = {
				1'b0,
				2'b10,
				5'ha,
				1'b0,
				ioreq.tc,4'h0,ioreq.td,
				ioreq.ep,ioreq.attr,2'b0,10'h1
			};
			Bit#(32) cdw1 = {
				user.cfg_completer_id,4'b0000,
				12'h4// read32 only...
			};
			Bit#(32) cdw2 = {
				ioreq.requesterID,ioreq.tag,1'b0,
				(ioreq.addr+fromInteger(io_userspace_offset))[6:0]
			};
			let cdw3 = reverseEndian(data);
			userSendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
		endmethod
		method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words);
			dmaWriteReqQ.enq(DMAReq{addr:addr, words:words, tag:?});
		endmethod
		method Action dmaWriteData(DMAWord data);
			dmaWriteWordQ.enq(data);
			dmaWriteWordIn <= dmaWriteWordIn + 1;
		endmethod
		method Action dmaReadReq(Bit#(32) addr, Bit#(10) words);
			dmaReadReqQ.enq(DMAReq{addr:addr, words:words, tag:?});
		endmethod
		method ActionValue#(DMAWord) dmaReadWord;
			dmaReadOutRQ.deq;
			dmaReadOutCntDn <= dmaReadOutCntDn + 1;
			return dmaReadOutRQ.first;
		endmethod
		method Action assertInterrupt if ( dataWordsRemain == 0);
			user.assertInterrupt(1);
		endmethod
		method Action assertUptrain;
			user.assertUptrain(1);
		endmethod
		method Bit#(32) debug_data;
			return user.debug_data;
		endmethod
	endinterface
endmodule


endpackage: PcieCtrl
