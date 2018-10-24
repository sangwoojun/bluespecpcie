import Clocks::*;
import FIFO::*;
import BRAMFIFO::*;
import FIFOF::*;
import Vector::*;

import PcieCtrl::*;


interface DMAWriteHelperIfc;
	method Action addHostBuffer(Bit#(32) off, Bit#(32) bytes);
	method Action write(Maybe#(Bit#(128)) write);
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) bufferDone; 
endinterface

module mkDMAWriteHelper#(PcieUserIfc pcie) (DMAWriteHelperIfc);
	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;
	
	Reg#(Maybe#(Bit#(32))) dmaWriteHostStartOff <- mkReg(tagged Invalid, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dmaWriteHostOff <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dmaWriteLeftWords <- mkReg(0, clocked_by pcieclk, reset_by pcierst); // fpga->host
    SyncFIFOIfc#(Maybe#(Bit#(128))) writeSyncQ <- mkSyncFIFO(32, curclk, currst, pcieclk);
    SyncFIFOIfc#(Tuple2#(Bit#(32),Bit#(32))) writeBufferQ <- mkSyncFIFO(8, curclk, currst, pcieclk);
	FIFO#(Bit#(128)) writeBufferDataQ <- mkSizedBRAMFIFO(8192, clocked_by pcieclk, reset_by pcierst); // 4 KB * 32
	Reg#(Bool) writeBufferFlush <- mkReg(False, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) writeBufferCntUp <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) writeBufferCntDn <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
    SyncFIFOIfc#(Tuple2#(Bit#(32),Bit#(32))) writeDoneQ <- mkSyncFIFO(32, pcieclk, pcierst, curclk);

	
	/*****************************************************
	** DMA FPGA -> Host Start
	**************************************/
	Integer dmaWriteTagCount  = 32;
	FIFO#(Bit#(8)) dmaWriteFreeTagQ <- mkSizedFIFO(dmaWriteTagCount, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaWriteTagInit <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bool) dmaWriteTagInitDone <- mkReg(False, clocked_by pcieclk, reset_by pcierst);
	rule initDmaTagW(dmaWriteTagInit < fromInteger(dmaWriteTagCount) && dmaWriteTagInitDone == False);
		dmaWriteTagInit <= dmaWriteTagInit + 1;
		dmaWriteFreeTagQ.enq(32+dmaWriteTagInit);//FIXME to not overlap with read!
		if ( dmaWriteTagInit >= fromInteger(dmaWriteTagCount) - 1 ) begin
			dmaWriteTagInitDone <= True;
		end
	endrule
	rule relayWriteSync ( writeBufferFlush == False );
		writeSyncQ.deq;
		let d = writeSyncQ.first;
		if ( isValid(d) ) begin
			writeBufferDataQ.enq(fromMaybe(?,d));
			writeBufferCntUp <= writeBufferCntUp +1;
		end else begin
			writeBufferFlush <= True;
		end
	endrule



	Reg#(Bit#(32)) dmaCurWriteLeft <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaCurTag <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dmaCurBufferWriteCnt <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule genPcieWrite ( dmaCurWriteLeft == 0 && dmaWriteLeftWords > 0 && (writeBufferCntUp-writeBufferCntDn >= 8 || writeBufferFlush ) );
		Bit#(8) writeTag = dmaWriteFreeTagQ.first;
		dmaWriteFreeTagQ.deq;
		dmaCurTag <= writeTag;
		let qcount = writeBufferCntUp-writeBufferCntDn;

		if ( !writeBufferFlush ) begin
			// qcount >= 8
			pcie.dmaWriteReq(dmaWriteHostOff, 8, writeTag);
			dmaWriteHostOff <= dmaWriteHostOff + 128;

			dmaCurWriteLeft <= 8;
			dmaWriteLeftWords <= dmaWriteLeftWords - 8;
			if ( dmaWriteLeftWords == 8 ) begin
				writeDoneQ.enq(tuple2(fromMaybe(?,dmaWriteHostStartOff), dmaCurBufferWriteCnt+8));
				dmaCurBufferWriteCnt <= 0;
			end else begin
				dmaCurBufferWriteCnt <= dmaCurBufferWriteCnt + 8;
			end
		end else if ( qcount > 8 ) begin
			pcie.dmaWriteReq(dmaWriteHostOff, 8, writeTag);
			dmaWriteHostOff <= dmaWriteHostOff + 128;

			dmaCurWriteLeft <= 8;
			dmaWriteLeftWords <= dmaWriteLeftWords - 8;
			if ( dmaWriteLeftWords == 8 ) begin
				writeDoneQ.enq(tuple2(fromMaybe(?,dmaWriteHostStartOff), dmaCurBufferWriteCnt+8));
				dmaCurBufferWriteCnt <= 0;
			end else begin
				dmaCurBufferWriteCnt <= dmaCurBufferWriteCnt + 8;
			end
		end else begin
			if (qcount > 0) begin
				pcie.dmaWriteReq(dmaWriteHostOff, truncate(qcount), writeTag);
			end
			dmaCurWriteLeft <= qcount;
			dmaWriteHostOff <= dmaWriteHostOff + (qcount*16);

			//we are flushing, and no more data left in queue
			dmaWriteLeftWords <= 0;
			writeBufferFlush <= False;

			dmaWriteHostStartOff <= tagged Invalid;

			writeDoneQ.enq(tuple2(fromMaybe(?,dmaWriteHostStartOff), dmaCurBufferWriteCnt+qcount));
			dmaCurBufferWriteCnt <= 0;
		end
	endrule

	rule doPcieWrite( dmaCurWriteLeft > 0 );
		writeBufferDataQ.deq;
		let d = writeBufferDataQ.first;

		pcie.dmaWriteData(d, dmaCurTag);

		dmaCurWriteLeft <= dmaCurWriteLeft - 1;
		writeBufferCntDn <= writeBufferCntDn +1;
		if ( dmaCurWriteLeft == 1 ) begin
			dmaWriteFreeTagQ.enq(dmaCurTag);
		end
	endrule
	rule procHostBuffer ( dmaWriteLeftWords == 0 );
		writeBufferQ.deq;
		let d = writeBufferQ.first;
		let off = tpl_1(d);
		let bytes = tpl_2(d);

		dmaWriteHostStartOff <= tagged Valid off;
		dmaWriteHostOff <= off;
		dmaWriteLeftWords <= (bytes>>4); // 16 byte words
	endrule

	method Action addHostBuffer(Bit#(32) off, Bit#(32) bytes);
		writeBufferQ.enq(tuple2(off,bytes));
	endmethod
	method Action write(Maybe#(Bit#(128)) data);
		writeSyncQ.enq(data);
	endmethod
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) bufferDone; 
		writeDoneQ.deq;
		let d = writeDoneQ.first;
		return tuple2(tpl_1(d), (tpl_2(d)<<4));
	endmethod
endmodule
