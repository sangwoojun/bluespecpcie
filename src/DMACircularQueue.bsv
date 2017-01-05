import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import MergeN::*;

typedef TMul#(2,PcieWordSz) DMAQueueWordSz;
typedef Bit#(DMAQueueWordSz) DMAQueueWord;

interface DMACircularQueueIfc#(numeric type bufferSz);
	method ActionValue#(Bit#(128)) getCmd;
	method Action enqStat(Bit#(8) addr, Bit#(32) data);

	method Action enq(DMAQueueWord word);

	// TODO
	method ActionValue#(DMAQueueWord) first;
	method Action deq;
endinterface

// bufferSz is log(bytes)
module mkDMACircularQueue#(PcieUserIfc pcie) (DMACircularQueueIfc#(bufferSz))
	provisos(Add#(a__, bufferSz, 32));

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Reg#(Bit#(32)) writeByteCount <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) readByteCount <- mkReg(0, clocked_by pcieclk, reset_by pcierst);


	FIFO#(IOWrite) userWriteQ <- mkFIFO(clocked_by pcieclk, reset_by pcierst);
	rule getWriteReq;
		IOWrite d <- pcie.dataReceive;
		userWriteQ.enq(d);
	endrule

	SyncFIFOIfc#(Bit#(32)) enqSyncQ <- mkSyncFIFOFromCC(32,pcieclk);
	Vector#(16,Reg#(Bit#(32))) statReg <- replicateM(mkReg(0, clocked_by pcieclk, reset_by pcierst));
	FIFO#(IOReadReq) userReadReqQ <- mkFIFO;
	rule getReadReq;
		let req = pcie.dataReq;
		userReadReqQ.enq(req);
	endrule
	rule procUserR;
		let req = userReadReqQ.first;
		userReadReqQ.deq;

		let addr = (d.addr>>2);
		if ( addr == 0 ) begin
			enqSyncQ.deq;
			pcie.dataSend(req, enqSyncQ.first);
		end else if ( addr < 16 ) begin
			pcie.dataSend(req, statReg[addr]);
		end
	endrule


	Reg#(Bool) started <- mkReg(False, clocked_by pcieclk, reset_by pcierst);
	Vector#(4,Reg#(Bit#(32))) cmdbuffer <- replicateM(mkReg(0), clocked_by pcieclk, reset_by pcierst);
	SyncFIFOIfc#(Bit#(128)) cmdQ <- mkSyncFIFOToCC(32,pcieclk,pcierst);
	rule procUserW;
		let d = userWriteQ.first;
		userWriteQ.deq;
		$display( "User write request @ %d %x", d.addr>>2, d.data );
		Bit#(8) toffset = truncate(d.addr>>2);
		
		if ( toffset == 0 ) begin
			cmdQ.enq({cmdbuffer[3],cmdbuffer[2],cmdbuffer[1],d.data});
		end else if ( toffset < 4 ) begin
			cmdbuffer[toffset] <= d.data;
		end
		if ( toffset == 16 ) begin
			started <= True;
		end
		if ( toffset == 17 ) begin
			readByteCount <= d.data;
		end
	endrule


	SyncFIFOIfc#(Bit#(256)) enqSyncQ <- mkSyncFIFOFromCC(32,pcieclk);
	FIFO#(PcieWord) enqQ <- mkSizedFIFO(32,clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) enqCountUp <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) enqCountDown <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	
	Reg#(Bit#(8)) dmaCountRemain <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) dmaCurTag <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	FIFO#(Bit#(8)) availWriteTagQ <- mkSizedFIFO(32, clocked_by pcieclk, reset_by pcierst);

	Reg#(Bit#(8)) availTagCounter <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule fillAvailWriteTag(availTagCounter <32);
		availTagCounter <= availTagCounter + 1;
		availWriteTagQ.enq(availTagCounter);
	endrule

	
	Reg#(Bit#(32)) writeOffset <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	rule initDMAWrite (dmaCountRemain == 0 && enqCountUp-enqCountDown > 8);
		let tag = availWriteTagQ.first;
		availWriteTagQ.deq;

		Bit#(bufferSz) offset = truncate(writeOffset);
		pcie.dmaWriteReq(zeroExtend(offset), 8, tag);
		writeOffset <= writeOffset+128;
		//pcie.dmaWriteData(enqQ.first,tag);
		//enqQ.deq;

		dmaCountRemain <= 8;
		//enqCountDown <= enqCountDown + 1;
		dmaCurTag <= tag;

		$display( "dma write starting @ %d (%d)", offset, tag );
	endrule
	rule dmaWriteWord (dmaCountRemain > 0);
		dmaCountRemain <= dmaCountRemain - 1;
		enqCountDown <= enqCountDown + 1;

		pcie.dmaWriteData(enqQ.first,dmaCurTag);
		enqQ.deq;

		if ( dmaCountRemain == 1 ) begin
			availWriteTagQ.enq(dmaCurTag);
		end
	endrule





	Reg#(Maybe#(PcieWord)) serializerBuffer <- mkReg(tagged Invalid, clocked_by pcieclk, reset_by pcierst);
	rule serializeEnq (started && writeByteCount-readByteCount<(1<<valueOf(bufferSz)));
		writeByteCount <= writeByteCount + 16;
		enqCountUp <= enqCountUp + 1;

		if ( isValid(serializerBuffer) ) begin
			enqQ.enq(fromMaybe(0,serializerBuffer));
			serializerBuffer <= tagged Invalid;
		end
		else begin
			enqSyncQ.deq;
			let d = enqSyncQ.first;
			DMAWord up = truncate(d>>valueOf(PcieWordSz));
			DMAWord down = truncate(d);
			enqQ.enq(down);
			serializerBuffer <= tagged Valid truncate(up);
		end
	endrule
	
	method ActionValue#(Bit#(128)) getCmd;
		cmdQ.deq;
		return cmdQ.first;
	endmethod
	method Action enqStat(Bit#(8) addr, Bit#(32) data);
		if ( addr == 0 ) begin
			enqSyncQ.enq(data);
		end else if(addr<16) begin
			statReg[addr] <= data;
		end
	endmethod

	method Action enq(DMAQueueWord word);
		enqSyncQ.enq(word);
	endmethod

	// TODO
	method ActionValue#(DMAQueueWord) first;
		return ?;
	endmethod
	method Action deq;
	endmethod
endmodule

