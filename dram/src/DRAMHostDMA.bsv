/**
Note:
Commands operate on 4 KB pages
Host offset/cpy bytes limited to 32 bits
**/


import Clocks::*;

import FIFO::*;
import BRAMFIFO::*;
import FIFOF::*;
import Vector::*;

import DRAMController::*;
import DRAMControllerTypes::*;
import DRAMBurstController::*;

import PcieCtrl::*;

interface DRAMHostDMAIfc;
	method ActionValue#(IOWrite) dataReceive;

	interface DRAMBurstControllerIfc dram;
endinterface

module mkDRAMHostDMA#(PcieUserIfc pcie, DRAMBurstControllerIfc dram) (DRAMHostDMAIfc);
	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Clock dramclk = dram.user_clk;
	Reset dramrst = dram.user_rst;
	
	FIFOF#(IOWrite) pcieOutQ <- mkFIFOF(clocked_by pcieclk, reset_by pcierst);

	Reg#(Bit#(32)) hostMemOff<- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(64)) fpgaMemOff<- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	
	Reg#(Bit#(32)) memReadLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst); // host->fpga
	Reg#(Bit#(32)) memWriteLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst); // fpga->host

	
	/**************************************
	** DMA Host -> DRAM Start
	**************************************/
	// 32 in flight good?
    SyncFIFOIfc#(Tuple2#(Bit#(64), Bit#(32))) dmaReadWordCntQ <- mkSyncFIFO(32, pcieclk, pcierst, dramclk);
	
	Integer dmaReadTagCount  = 8;
	FIFO#(Bit#(8)) dmaReadFreeTagQ <- mkSizedFIFO(dmaReadTagCount, clocked_by pcieclk, reset_by pcierst);
	Vector#(8, Reg#(Bit#(8))) vDmaReadTagWordsLeft <- replicateM(mkReg(0, clocked_by pcieclk, reset_by pcierst));
	Reg#(Bit#(8)) dmaReadTagInit <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule initDmaTagR(dmaReadTagInit < fromInteger(dmaReadTagCount));
		dmaReadTagInit <= dmaReadTagInit + 1;
		dmaReadFreeTagQ.enq(dmaReadTagInit);
	endrule

	rule sendDMARead ( memReadLeft > 0 );
		dmaReadFreeTagQ.deq;
		Bit#(8) freeTag = dmaReadFreeTagQ.first;

		if ( memReadLeft >= 128 ) begin
			Bit#(8) words = (128>>4);
			pcie.dmaReadReq(hostMemOff, zeroExtend(words), freeTag);
			
			memReadLeft <= memReadLeft - 128;
			hostMemOff <= hostMemOff + 128;
			vDmaReadTagWordsLeft[freeTag] <= words;
		end else begin
			// +8 to take ceiling, but should not happen because 4KB units
			Bit#(8) words = truncate((memReadLeft+8)>>4);
			pcie.dmaReadReq(hostMemOff, zeroExtend(words), freeTag);

			memReadLeft <= 0;
			vDmaReadTagWordsLeft[freeTag] <= words;
		end
	endrule
    SyncFIFOIfc#(Bit#(128)) dmaReadWordsQ <- mkSyncFIFO(32, pcieclk, pcierst, dramclk);
	rule getDMARead;
		let d <- pcie.dmaReadWord;
		let word = d.word;
		let tag = d.tag;
		if ( vDmaReadTagWordsLeft[tag] == 1 ) begin
			vDmaReadTagWordsLeft[tag] <= 0;
			dmaReadFreeTagQ.enq(tag);
			dmaReadWordsQ.enq(word);
		end else if ( vDmaReadTagWordsLeft[tag] == 0 ) begin
		end else begin
			vDmaReadTagWordsLeft[tag] <= vDmaReadTagWordsLeft[tag] - 1;
			dmaReadWordsQ.enq(word);
		end
	endrule
	// units are DMA WORDS! not DRAM WORDS!
	Reg#(Bit#(32)) dramWriteBurstLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	rule dramStartBurst ( dramWriteBurstLeft == 0 );
		dmaReadWordCntQ.deq;
		let cnt = dmaReadWordCntQ.first;
		let words = tpl_2(cnt);
		let off = tpl_1(cnt);
		Bit#(32) dramwords = (words>>2);// 128bit dma words, 512bit dram words
		dram.writeReq(off, dramwords); 
		dramWriteBurstLeft <= words;
	endrule
	Reg#(Bit#(512)) dramWriteBuffer <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	Reg#(Bit#(2)) dramWriteBufferOffset <- mkReg(0, clocked_by dramclk, reset_by dramrst);
	
	SyncFIFOIfc#(Bool) dramWriteBurstDoneQ <- mkSyncFIFO(32, dramclk, dramrst, pcieclk);
	rule relayDRAMWriteBurst(dramWriteBurstLeft > 0);
		let d = dmaReadWordsQ.first;
		dmaReadWordsQ.deq;
		//let d = {32'h11223344, 32'hcccccccc, 32'h99887766, 32'hdeadbeef};
		dramWriteBurstLeft <= dramWriteBurstLeft - 1;
		if ( dramWriteBurstLeft == 1 ) begin
			dramWriteBurstDoneQ.enq(True);
		end

		if ( dramWriteBufferOffset == 3 || dramWriteBurstLeft == 1 ) begin
			dram.write({d, truncate(dramWriteBuffer>>128)});
			dramWriteBufferOffset <= 0;
		end else begin
			dramWriteBuffer <= {d,truncate(dramWriteBuffer>>128)};
			dramWriteBufferOffset <= dramWriteBufferOffset + 1;
		end
	endrule
	/**************************************
	** DMA Host -> DRAM End
	**************************************/




	/*****************************************************
	** DMA DRAM -> Host Start
	**************************************/

	Integer dmaWriteTagCount  = 16;
	FIFO#(Bit#(8)) dmaWriteFreeTagQ <- mkSizedFIFO(dmaWriteTagCount, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaWriteTagInit <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule initDmaTagW(dmaWriteTagInit < fromInteger(dmaWriteTagCount));
		dmaWriteTagInit <= dmaWriteTagInit + 1;
		dmaWriteFreeTagQ.enq(fromInteger(dmaReadTagCount)+dmaWriteTagInit);
	endrule


    SyncFIFOIfc#(Tuple2#(Bit#(64), Bit#(32))) dramReadWordCntQ <- mkSyncFIFO(32, pcieclk, pcierst, dramclk);
	SyncFIFOIfc#(Bit#(512)) dramReadWordQ <- mkSyncFIFO(32, dramclk, dramrst, pcieclk);
	Reg#(Bit#(32)) dramBurstReadLeft <- mkReg(0, clocked_by dramclk, reset_by dramrst);

	SyncFIFOIfc#(Bool) dramReadBurstDoneQ <- mkSyncFIFO(32, dramclk, dramrst, pcieclk);
	rule startDRAMRead ( dramBurstReadLeft == 0 );
		dramReadWordCntQ.deq;
		let r = dramReadWordCntQ.first;
		let off = tpl_1(r);
		let words = tpl_2(r);
		dram.readReq(off, words);
		dramBurstReadLeft <= words;
	endrule
	rule relayDRAMWord ( dramBurstReadLeft > 0 );
		let d <- dram.read;
		dramBurstReadLeft <= dramBurstReadLeft - 1;
		dramReadWordQ.enq(d);
		if ( dramBurstReadLeft == 1 ) begin
			dramReadBurstDoneQ.enq(True);
		end
	endrule
	
	
	Reg#(Bit#(8)) dmaWriteCurTag <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaCurWriteLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule sendDRAMBurstRead(memWriteLeft > 0 && dmaCurWriteLeft == 0);
		Bit#(8) writeTag = dmaWriteFreeTagQ.first;
		dmaWriteFreeTagQ.deq;
		dmaWriteCurTag <= writeTag;

		if ( memWriteLeft >= 128 ) begin
			memWriteLeft <= memWriteLeft - 128;

			Bit#(8) words = (128>>4);
			dmaCurWriteLeft <= words;
			pcie.dmaWriteReq(hostMemOff, zeroExtend(words), writeTag);
			hostMemOff <= hostMemOff + 128;
		end else begin
			memWriteLeft <= 0;
			
			// +8 to take ceiling, but should not happen because 4KB units
			Bit#(8) words = truncate((memWriteLeft+8)>>4);
			dmaCurWriteLeft <= words;
			pcie.dmaWriteReq(hostMemOff, zeroExtend(words), writeTag);
		end
	endrule
	Reg#(Bit#(512)) dmaWriteDRAMWordBuffer <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(2)) dmaWriteDRAMWordBufferOffset <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule splitDRAMWord(dmaCurWriteLeft > 0);
		dmaCurWriteLeft <= dmaCurWriteLeft - 1;
		dmaWriteDRAMWordBufferOffset <= dmaWriteDRAMWordBufferOffset + 1;

		if ( dmaCurWriteLeft == 1 ) begin
			dmaWriteFreeTagQ.enq(dmaWriteCurTag);
		end

		if (dmaWriteDRAMWordBufferOffset == 0 ) begin
			dramReadWordQ.deq;
			let d = dramReadWordQ.first;
			pcie.dmaWriteData(truncate(d), dmaWriteCurTag);
			dmaWriteDRAMWordBuffer <= (d>>128);
		end else begin
			pcie.dmaWriteData(truncate(dmaWriteDRAMWordBuffer), dmaWriteCurTag);
			dmaWriteDRAMWordBuffer <= (dmaWriteDRAMWordBuffer>>128);
		end

		//pcie.dmaWriteData({32'hdeadbeef,32'h99887766,32'h11223344,32'hdeadbeef}, dmaWriteCurTag);
	endrule
    
	
	/**************************************
	** DMA DRAM -> Host End
	****************************************************/

	Reg#(Bit#(32)) dramWriteBurstDoneCount <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dramReadBurstDoneCount <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule accDRAMBurstDone;
		dramWriteBurstDoneQ.deq;
		dramWriteBurstDoneCount <= dramWriteBurstDoneCount + 1;
	endrule
	rule accDRAMBurstRDone;
		dramReadBurstDoneQ.deq;
		dramReadBurstDoneCount <= dramReadBurstDoneCount + 1;
	endrule

	rule getCmd ( memReadLeft == 0 && memWriteLeft == 0 );
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		let off = (a>>2);

		// Commands operate on 4 KB pages!
		if ( off == 256 ) begin // hostoff
			hostMemOff <= (d<<12);
		end else if ( off == 257 ) begin // fpgaoff
			fpgaMemOff <= zeroExtend(d<<12);
		end else if ( off == 258 ) begin // host->fpga
			memReadLeft <= (d<<12);
			dmaReadWordCntQ.enq(tuple2(fpgaMemOff, (d<<8))); // Units are DMA words (16B)
		end else if ( off == 259 ) begin // fpag->host
			memWriteLeft <= (d<<12);
			dramReadWordCntQ.enq(tuple2(fpgaMemOff, (d<<6))); // Units are DRAM words (64B)
		end else begin
			if ( pcieOutQ.notFull() ) begin
				pcieOutQ.enq(w);
			end
		end
	endrule

	rule readStat;
		let r <- pcie.dataReq;
		let a = r.addr;
		let off = (a>>2);
		if ( off == 256 ) begin
			pcie.dataSend(r, dramWriteBurstDoneCount);
		end else if ( off == 257 ) begin
			pcie.dataSend(r, dramReadBurstDoneCount);
		end else begin
			pcie.dataSend(r, 32'hffffffff);
		end
	endrule
	
	/***************************************************
	** Chained DRAM interface start
	*********************************/

	/********************************
	** Chained DRAM interface end
	****************************************************/

	// TODO
	
	/***************************************************
	** Interface start
	*********************************/
	
	method ActionValue#(IOWrite) dataReceive;
		return ?;
	endmethod


	interface DRAMBurstControllerIfc dram;
	interface Clock user_clk = dram.user_clk;
	interface Reset user_rst = dram.user_rst;
	method Action writeReq(Bit#(64) addr, Bit#(32) words);
	endmethod
	method Action readReq(Bit#(64) addr, Bit#(32) words);
	endmethod
	method Action write(Bit#(512) word);
	endmethod
	method ActionValue#(Bit#(512)) read;
		return ?;
	endmethod
	endinterface
endmodule
