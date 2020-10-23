import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import Serializer::*;

import StreamKernel::*;
import LZAHCompression::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	FIFO#(DMAWord) inputQ <- mkSizedBRAMFIFO(512); // 8KBs
	FIFO#(DMAWord) outputQ <- mkSizedBRAMFIFO(512); // 8KBs
	Reg#(Bit#(16)) outputCntUp <- mkReg(0);
	Reg#(Bit#(16)) outputCntDn <- mkReg(0);


/*
	StreamKernelIfc kernel <- mkStreamKernelTest;
	DeSerializerIfc#(128, 2) des <- mkDeSerializer;
	SerializerIfc#(256, 2) ser <- mkSerializer;
	rule desIn;
		inputQ.deq;
		des.put(inputQ.first);
	endrule
	rule relayIn;
		let w <- des.get;
		kernel.enq(w);
	endrule
	rule serOut;
		kernel.deq;
		ser.put(kernel.first);
	endrule
	rule relayOut;
		let w <- ser.get;
		outputQ.enq(w);
		outputCntUp <= outputCntUp + 1;
		//$display( "outputCntUp %d %d\n", outputCntUp+1, outputCntDn);
	endrule
	*/

	SerializerIfc#(128,2) comp_ser <- mkSerializer;
	DeSerializerIfc#(64,2) comp_des <- mkDeSerializer;
	FIFO#(Bit#(64)) compr <- mkLZAHCompressor;
	rule serIn;
		inputQ.deq;
		comp_ser.put(inputQ.first);
	endrule
	rule relayIn;
		let w <- comp_ser.get;
		compr.enq(w);
	endrule
	rule serOut;
		compr.deq;
		comp_des.put(compr.first);
	endrule
	rule relayOut;
		let w <- comp_des.get;
		outputQ.enq(w);
		outputCntUp <= outputCntUp + 1;
		//$display( "outputCntUp %d %d\n", outputCntUp+1, outputCntDn);
	endrule

	BRAM2Port#(Bit#(6),DMAWord) page <- mkBRAM2Server(defaultValue); // tag, total words,words recv

	FIFO#(Bit#(8)) streamReadQ <- mkSizedBRAMFIFO(1024); // streamid, page offset
	FIFO#(Bit#(8)) streamWriteQ <- mkSizedBRAMFIFO(1024); // streamid, page offset

	Reg#(Bit#(32)) streamReadCnt <- mkReg(0);
	Reg#(Bit#(32)) streamWriteCnt <- mkReg(0);
	rule getCmd;
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let off = (a>>2);
		// off == (in|out)<<8, d == page offset
		if ( off == 0 ) begin
			streamReadQ.enq(truncate(d));
		end else begin
			streamWriteQ.enq(truncate(d));
			//$write("writeQ enqued %x\n", d);
		end
	endrule

	FIFO#(IOReadReq) reqQ <- mkFIFO;
	rule readStat;
		let r <- pcie.dataReq;
		let a = r.addr;
		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let offset = (a>>2);

		if ( offset == 0 ) begin
			pcie.dataSend(r, streamReadCnt);
		end else if ( offset == 1 ) begin
			pcie.dataSend(r, streamWriteCnt);
		end else if ( offset >= 2 ) begin
			page.portB.request.put(BRAMRequest{write:False,responseOnWrite:False,address:truncate(offset),datain:?});
			reqQ.enq(r);
		end else begin
			pcie.dataSend(r, 32'hcccccccc);
		end
	endrule
	rule relayPageRead;
		let r <- page.portB.response.get();
		let req = reqQ.first;
		reqQ.deq;
		pcie.dataSend(req,truncate(r));
	endrule

	rule dmaReadReq;
		streamReadQ.deq;
		let poff = streamReadQ.first;
		pcie.dmaReadReq( (zeroExtend(poff)<<10), 64); // offset, words
		streamReadCnt <= streamReadCnt + 1;
	endrule
	Reg#(Bit#(32)) dmaReadWords <- mkReg(0);
	rule dmaReadDatal;
		DMAWord rd <- pcie.dmaReadWord;
		page.portA.request.put(BRAMRequest{write:True,responseOnWrite:False,address:truncate(dmaReadWords),datain:rd});
		dmaReadWords <= dmaReadWords + 1;
		
		inputQ.enq(rd);
	endrule

	Reg#(Bit#(16)) curOutLeftUp <- mkReg(0);
	Reg#(Bit#(16)) curOutLeftDn <- mkReg(0);
	rule dmaWriteReq (outputCntUp - outputCntDn >= 64 && curOutLeftUp-curOutLeftDn < 128);
		streamWriteQ.deq;
		let woff = streamWriteQ.first;
		pcie.dmaWriteReq((zeroExtend(woff)<<10), 64);

		curOutLeftUp <= curOutLeftUp + 64;
		outputCntDn <= outputCntDn + 64;
		$write("Starting DMA Write\n" );
		streamWriteCnt <= streamWriteCnt + 1;
	endrule
	rule dmaWriteData(curOutLeftUp != curOutLeftDn);
		curOutLeftDn <= curOutLeftDn + 1;

		//outputCntDn <= outputCntDn + 1;

		outputQ.deq;
		pcie.dmaWriteData(outputQ.first);
		$write("DMA Write\n" );
	endrule
endmodule
