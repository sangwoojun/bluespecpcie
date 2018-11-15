import Clocks::*;
import FIFO::*;
import BRAMFIFO::*;
import FIFOF::*;
import Vector::*;

import PcieCtrl::*;


interface DMAReadHelperIfc;
	method Action readReq(Bit#(32) offset, Bit#(32) words);
	method ActionValue#(Bit#(128)) read;
endinterface

module mkDMAReadHelper#(PcieUserIfc pcie) (DMAReadHelperIfc);
	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;
	
    SyncFIFOIfc#(Tuple2#(Bit#(32), Bit#(32))) readCmdQ <- mkSyncFIFO(4, curclk, currst, pcieclk);
	Reg#(Bit#(32)) dmaReadHostOff <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dmaReadLeftBytes <- mkReg(0, clocked_by pcieclk, reset_by pcierst); // host->fpga
	
	/**************************************
	** DMA Host -> FPGA Start
	**************************************/
	//TODO changing dmaReadTagCount require changing curReadTag
	Integer dmaReadTagCount  = 8;
	FIFO#(Bit#(8)) dmaReadFreeTagQ <- mkSizedFIFO(dmaReadTagCount, clocked_by pcieclk, reset_by pcierst);
	Vector#(8, Reg#(Bit#(8))) vDmaReadTagWordsLeft <- replicateM(mkReg(0, clocked_by pcieclk, reset_by pcierst));
	Vector#(8, FIFO#(Bit#(128))) vDmaReadWords <- replicateM(mkSizedFIFO(8, clocked_by pcieclk, reset_by pcierst));
	//ScatterNIfc#(16, Bit#(128)) dmaReadWordsS <- mkScatterN;//TODO use this
	FIFO#(Tuple2#(Bit#(8),Bit#(8))) dmaReadTagOrderQ <- mkSizedFIFO(dmaReadTagCount, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaReadTagInit <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bool) dmaReadTagInitDone <- mkReg(False, clocked_by pcieclk, reset_by pcierst);
	rule initDmaTagR(dmaReadTagInit < fromInteger(dmaReadTagCount));
		dmaReadTagInit <= dmaReadTagInit + 1;
		dmaReadFreeTagQ.enq(dmaReadTagInit);
		if ( dmaReadTagInit + 1 >= fromInteger(dmaReadTagCount) ) begin
			dmaReadTagInitDone <= True;
		end
	endrule
	rule sendDMARead ( dmaReadTagInitDone && dmaReadLeftBytes > 0 );
		dmaReadFreeTagQ.deq;
		Bit#(8) freeTag = dmaReadFreeTagQ.first;

		if ( dmaReadLeftBytes >= 128 ) begin
			Bit#(8) words = (128>>4);
			pcie.dmaReadReq(dmaReadHostOff, zeroExtend(words), freeTag);
			
			dmaReadLeftBytes <= dmaReadLeftBytes - 128;
			dmaReadHostOff <= dmaReadHostOff + 128;
			vDmaReadTagWordsLeft[freeTag] <= words;
			dmaReadTagOrderQ.enq(tuple2(freeTag,words));
		end else begin
			Bit#(8) words = truncate(dmaReadLeftBytes>>4);
			pcie.dmaReadReq(dmaReadHostOff, zeroExtend(words), freeTag);

			dmaReadLeftBytes <= 0;
			vDmaReadTagWordsLeft[freeTag] <= words;
			dmaReadTagOrderQ.enq(tuple2(freeTag,words));
		end
	endrule
    FIFO#(Tuple2#(Bit#(8), Bit#(128))) dmaReadWordsQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	rule getDMARead ( dmaReadTagInitDone );
		let d_ <- pcie.dmaReadWord;

		let word = d_.word;
		let tag = d_.tag;
		if ( vDmaReadTagWordsLeft[tag] == 1 ) begin
			vDmaReadTagWordsLeft[tag] <= 0;
			dmaReadFreeTagQ.enq(tag);
			dmaReadWordsQ.enq(tuple2(tag, word));
		end else if ( vDmaReadTagWordsLeft[tag] == 0 ) begin
		end else begin
			vDmaReadTagWordsLeft[tag] <= vDmaReadTagWordsLeft[tag] - 1;
			dmaReadWordsQ.enq(tuple2(tag, word));
		end
	endrule
	rule relayDmaReadWords;
		dmaReadWordsQ.deq;
		let d = dmaReadWordsQ.first;
		let tag = tpl_1(d);
		let word = tpl_2(d);
		vDmaReadWords[tag].enq(word);
	endrule
    SyncFIFOIfc#(Bit#(128)) dmaReadWordsQ2 <- mkSyncFIFO(16, pcieclk, pcierst, curclk);
	Reg#(Bit#(3)) curReadTag <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) curReadTagCnt <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule startReorderRead ( curReadTagCnt == 0 );
		dmaReadTagOrderQ.deq;
		let d = dmaReadTagOrderQ.first;
		let tag = tpl_1(d);
		let cnt = tpl_2(d);
		curReadTag <= truncate(tag);
		curReadTagCnt <= cnt-1;
		dmaReadWordsQ2.enq(vDmaReadWords[tag].first);
		vDmaReadWords[tag].deq;
	endrule
	rule reorderRead( curReadTagCnt > 0 );
		curReadTagCnt <= curReadTagCnt - 1;
		dmaReadWordsQ2.enq(vDmaReadWords[curReadTag].first);
		vDmaReadWords[curReadTag].deq;
	endrule

	rule dmaReadCmd (dmaReadLeftBytes == 0 );
		readCmdQ.deq;
		let c = readCmdQ.first;
		dmaReadLeftBytes <= tpl_2(c);
		dmaReadHostOff <= tpl_1(c);
	endrule
	/**************************************
	** DMA Host -> FPGA End
	**************************************/

	method Action readReq(Bit#(32) offset, Bit#(32) bytes);
		readCmdQ.enq(tuple2(offset,bytes));
	endmethod
	method ActionValue#(Bit#(128)) read;
		dmaReadWordsQ2.deq();
		return dmaReadWordsQ2.first;
	endmethod
endmodule
