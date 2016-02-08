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
import BRAM::*;
import BRAMFIFO::*;

import PcieImport::*;

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
} DMAWriteReq deriving (Bits,Eq);

typedef 128 PcieWordSz;
typedef Bit#(PcieWordSz) PcieWord;
typedef 128 DMAWordSz;
typedef Bit#(DMAWordSz) DMAWord;

typedef struct {
	DMAWord word;
	Bit#(8) tag;
} DMAWordTagged deriving (Bits,Eq);

typedef 4096 IoUserSpaceOffset;
typedef 32 DMABufOffset;


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

	method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
	method Action dmaWriteData(DMAWord data, Bit#(8) tag);
	method Action dmaReadReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
	method ActionValue#(DMAWordTagged) dmaReadWord;

	method Action assertInterrupt;
endinterface

interface PcieCtrlIfc;
	//method Bit#(4) leds;

	interface PcieUserIfc user;
endinterface

function Bit#(32) reverseEndian(Bit#(32) d);
	return {d[7:0], d[15:8], d[23:16], d[31:24]};
endfunction

module mkPcieCtrl#(PcieImportUser user) (PcieCtrlIfc);

	Integer dma_buf_offset = valueOf(DMABufOffset); //must match one in driver
	Integer io_userspace_offset = valueOf(IoUserSpaceOffset);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Bit#(7) type_rd32_io = 7'b0000010;
	Bit#(7) type_rd32_mem = 7'b0000000;
	Bit#(7) type_wr32_io = 7'b1000010;
	Bit#(7) type_wr32_mem = 7'b1000000;
	Bit#(7) type_completion = 7'b1001010;

	Reg#(Bit#(32)) read32data <- mkReg(32'haaaaaaaa);
	Reg#(Bit#(32)) tlpCount <- mkReg(0);

	Reg#(Bit#(10)) rxOffset <- mkReg(0);
	Vector#(4, Reg#(Bit#(1))) leddata <- replicateM(mkReg(0));

	FIFO#(Bit#(PcieInterfaceSz)) tlpQ <- mkSizedFIFO(32);
	Reg#(Maybe#(Bit#(PcieInterfaceSz))) partBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(5)) partOffset <- mkReg(0);

	BRAM2Port#(Bit#(10), Bit#(32)) configBuffer <- mkBRAM2Server(defaultValue); //4K
	FIFO#(Bool) bufidxRequestedWriteQ <- mkFIFO;

	rule recvTLP;
		Bit#(PcieInterfaceSz) tlp <- user.receiveData;
		Bit#(PcieKeepSz) keep <- user.receiveKeep;
		Bit#(1) last <- user.receiveLast;
		Bit#(22) ruser <- user.receiveUser;


		Bool sof_present = ruser[14] == 1 ? True : False;
		Bool sof_mid = ruser[13:10] == 4'b1000 ? sof_present : False;
		Bool sof_right = ruser[13:10] == 4'b0000 ? sof_present : False;

		if ( sof_right ) begin
			partOffset <= 0;
			partBuffer <= tagged Invalid;

			tlpQ.enq(tlp);
		end else if ( sof_mid ) begin
			partOffset <= 8;
			partBuffer <= tagged Valid (tlp>>64);

			Bit#(64) curPart = truncate(tlp);
			if ( isValid(partBuffer) ) begin
				let pb = fromMaybe(?, partBuffer);
				Bit#(64) lastPart = truncate(pb);
				tlpQ.enq({curPart, lastPart});
			end
		end else begin
			if ( partOffset[3] == 0 ) begin
				tlpQ.enq(tlp);
			end else begin
				if ( last != 1 ) begin
					partBuffer <= tagged Valid (tlp>>64);
				end
				else partBuffer <= tagged Invalid;

				if ( isValid(partBuffer) ) begin
					Bit#(64) lastPart = truncate(fromMaybe(?,partBuffer));
					Bit#(64) curPart = truncate(tlp);
					tlpQ.enq({curPart, lastPart});
				end
			end
		end
	endrule

	Reg#(Bit#(10)) dmaSendWords <- mkReg(0);

	FIFO#(IOReadReq) ioReadQ <- mkSizedFIFO(8);
	FIFO#(SendTLP) sendTLPQ <- mkSizedFIFO(8);

	FIFO#(IOWrite) userWriteQ <- mkSizedFIFO(32);
	FIFO#(IOReadReq) userReadQ <- mkSizedFIFO(32);

	Reg#(Bit#(16)) userWriteBudget <- mkReg(0);
	Reg#(Bit#(16)) userWriteEmit <- mkReg(0);
	Reg#(Bit#(16)) userReadEmit <- mkReg(0);

	Reg#(Bit#(10)) completionRecvLength <- mkReg(0);
	Reg#(Bit#(8)) completionRecvTag <- mkReg(0);

	Reg#(Bit#(32)) dmaReadBuffer <- mkReg(0);
	FIFO#(DMAWordTagged) dmaReadWordQ <- mkSizedFIFO(16);

	rule procCompletionTLP( completionRecvLength > 0 );
		let tlp = tlpQ.first;
		tlpQ.deq;
		tlpCount <= tlpCount + 1;
		//TODO fix endianness?
		dmaReadBuffer <= truncate(tlp>>(32*3));
		dmaReadWordQ.enq(DMAWordTagged{word:{truncate(tlp), dmaReadBuffer}, tag:completionRecvTag});

		if ( completionRecvLength >= 4 ) begin
			completionRecvLength <= completionRecvLength - 4;
		end else begin
			completionRecvLength <= 0;
		end
	endrule


	rule procTLP( dmaSendWords == 0 && completionRecvLength == 0 ); //FIXME any more efficient way to do this?
		let tlp = tlpQ.first;
		tlpQ.deq;
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
				sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else if ( internalAddr == (1024*4)-8) begin
				cdw3 = reverseEndian(zeroExtend(userReadEmit));
				sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else if ( internalAddr == (1024*4)-4) begin
				//cdw3 = reverseEndian(zeroExtend(userWriteBudget-userWriteEmit));
				cdw3 = reverseEndian(zeroExtend(userWriteEmit));
				sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
			end
			else if ( internalAddr < 1024*4 ) begin
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
				userReadQ.enq(IOReadReq{requesterID:rid,tag:tag,addr:truncate(addr)-fromInteger(io_userspace_offset),
					tc:tc,td:td,ep:ep,attr:attr});
			end
		end
		else if ( ptype == type_wr32_io 
		 || ptype == type_wr32_mem ) begin

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
			/*
			if ( internalAddr == (1024*4)-4 ) begin
				userWriteBudget <= userWriteBudget + truncate(data);
			end else
			*/
			if ( internalAddr == 0 ) begin 
				userWriteEmit <= 0;
				userReadEmit <= 0;
			end else
			if ( internalAddr < 1024*4 ) begin
				configBuffer.portA.request.put(
					BRAMRequest{
					write:True,
					responseOnWrite:False,
					address:truncate(internalAddr>>2),
					datain:data
					}
				);
			end
			else if (internalAddr >= 1024*4 ) begin
				userWriteQ.enq(IOWrite{addr:internalAddr-fromInteger(io_userspace_offset), data:data});
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
				sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'h0fff,last:1'b1});
			end
		end else if ( ptype == type_completion ) begin
			Bit#(10) length = tlp[9:0];
			Bit#(8) tag = tlp[15+64:8+64];
			Bit#(32) data = reverseEndian(tlp[31+96:96]);

			completionRecvLength <= length -1; //one dw already arrived
			completionRecvTag <= tag;
			dmaReadBuffer <= data;
		end
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
		sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b1});
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


	FIFO#(DMAWriteReq) dmaReadReqQ <- mkFIFO;
	FIFO#(DMAWriteReq) dmaPageReadReqQ <- mkFIFO;
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
	rule splitDmaReadReq2(dmaReadWords > 0 );
		let bufidx = dmaReadStartAddr>>12; //4k pages
		let nextPage = bufidx+1;
		let internal = (nextPage<<12)-dmaReadStartAddr;
		Bit#(10) internalWords = truncate(internal>>4);

		if ( internalWords > dmaReadWords ) begin
			dmaReadWords <= 0;
			dmaPageReadReqQ.enq(DMAWriteReq{addr:zeroExtend(dmaReadStartAddr[11:0]), words:dmaReadWords, tag:dmaReadTag});
		end else begin
			dmaReadWords <= dmaReadWords - internalWords;
			dmaReadStartAddr <= nextPage<<12;
			dmaPageReadReqQ.enq(DMAWriteReq{addr:zeroExtend(dmaReadStartAddr[11:0]), words:internalWords, tag:dmaReadTag});
		end

		//let bufidx = addr>>12; //4k pages
		Bit#(10) bufoffset = fromInteger(dma_buf_offset)>>2;
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

		// truncating req.addr for page internal address
		let dmaAddr = busAddr + zeroExtend(req.addr[11:0]);
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
			req.tag, //8'h00, // TAG
			4'h0, 4'hf
			};
		Bit#(32) cdw2 = {
			truncate(dmaAddr>>2),
			2'b00
			//ioreq.requesterID,ioreq.tag,1'b0,
			//ioreq.addr
		};

		Bit#(32) cdw3 = 0;

		sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'h0fff,last:1'b1});
	endrule

	// BEGIN DMA WRITE RELATED ///////////////////////////////////
	//

	FIFO#(DMAWriteReq) dmaWriteReqQ <- mkFIFO;
	FIFO#(DMAWord) dmaWriteWordQ <- mkSizedFIFO(16);
	Reg#(DMAWord) dmaWriteBuf <- mkReg(0);

	Reg#(Bit#(32)) dmaStartAddr <- mkReg(0);
	Reg#(Bit#(8)) dmaWriteTag <- mkReg(0);
	rule splitDmaWriteReq (dmaSendWords == 0);
		dmaWriteReqQ.deq;
		let req = dmaWriteReqQ.first;

		dmaStartAddr <= {truncate(req.addr>>4), 4'b0000};
		//dmaStartAddr <= req.addr;
		dmaSendWords <= req.words;
		dmaWriteTag <= req.tag;
	endrule

	FIFO#(DMAWriteReq) dmaPageWriteReqQ <- mkFIFO;
	(* descending_urgency = "splitDmaWriteReq2, splitDmaReadReq2" *)
	rule splitDmaWriteReq2 (dmaSendWords > 0 );

		let bufidx = dmaStartAddr>>12; //4k pages
		let nextPage = bufidx+1;
		let internal = (nextPage<<12)-dmaStartAddr;
		Bit#(10) internalWords = truncate(internal>>4);

		if ( internalWords > dmaSendWords ) begin
			dmaSendWords <= 0;
			dmaPageWriteReqQ.enq(DMAWriteReq{addr:zeroExtend(dmaStartAddr[11:0]), words:dmaSendWords, tag:dmaWriteTag});
		end else begin
			dmaSendWords <= dmaSendWords - internalWords;
			dmaStartAddr <= nextPage<<12;
			dmaPageWriteReqQ.enq(DMAWriteReq{addr:zeroExtend(dmaStartAddr[11:0]), words:internalWords, tag:dmaWriteTag});
		end
		
		Bit#(10) bufoffset = fromInteger(dma_buf_offset)>>2;
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
	rule generateHeaderTLP ( dataWordsRemain == 0 );

		//let busAddr <- configBuffer.portB.response.get;
		let busAddr = dmaWriteBufAddrQ.first;
		dmaWriteBufAddrQ.deq;

		let req = dmaPageWriteReqQ.first;
		dmaPageWriteReqQ.deq;

		let dmaAddr = busAddr + req.addr;
		Bit#(10) dmaWords = req.words;
		//let dmaWords = 8;
		
		dmaWriteWordQ.deq;
		let data = dmaWriteWordQ.first;
		dmaWriteBuf <= (data>>32);


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

		dataWordsRemain <= dmaWords;
		//let cdw3 = reverseEndian(32'hf00dbeef);
		Bit#(32) cdw3 = reverseEndian(truncate(data));

		sendTLPQ.enq(SendTLP{tlp:{cdw3,cdw2,cdw1,cdw0},keep:16'hffff,last:1'b0});
	endrule

	rule generateDataTLP ( dataWordsRemain > 0 );


		dataWordsRemain <= dataWordsRemain - 1;

		if ( dataWordsRemain > 1 ) begin
			dmaWriteWordQ.deq;
			let d = dmaWriteWordQ.first;
			Bit#(32) h = truncate(d);
			dmaWriteBuf <= (d>>32);

			//TODO fix endian
			let data = dmaWriteBuf | (zeroExtend(h)<<(128-32));

			sendTLPQ.enq(SendTLP{tlp:{
				reverseEndian(data[127:96]),
				reverseEndian(data[95:64]),
				reverseEndian(data[63:32]),
				reverseEndian(data[31:0])
				},keep:16'hffff,last:1'b0});
			//sendTLPQ.enq(SendTLP{tlp:data,keep:16'hffff,last:1'b0});
		end else begin
			let data = dmaWriteBuf;
			sendTLPQ.enq(SendTLP{tlp:{
				reverseEndian(data[127:96]),
				reverseEndian(data[95:64]),
				reverseEndian(data[63:32]),
				reverseEndian(data[31:0])
				},keep:16'h0fff,last:1'b1});
			//sendTLPQ.enq(SendTLP{tlp:data,keep:16'h0fff,last:1'b1});
		end
	endrule



	//
	// END DMA WRITE RELATED //////////////////////////////////////


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
	(* descending_urgency = "procTLP, generateDataTLP, generateHeaderTLP, completeIORead, generateDmaReadTLP, relayUserSendTLP" *)
	rule relayUserSendTLP;
		userSendTLPQ.deq;
		sendTLPQ.enq(userSendTLPQ.first);
	endrule


	/*
	method Bit#(4) leds;
		//return {leddata[0], leddata[1], leddata[2], leddata[3]};
		//return read32data[3:0];
		return tlpCount[3:0];
	endmethod
	*/

	interface PcieUserIfc user;
		interface Clock user_clk = curClk;
		interface Reset user_rst = curRst;

		method ActionValue#(IOWrite) dataReceive;
			userWriteQ.deq;
			userWriteEmit <= userWriteEmit + 1;
			return userWriteQ.first;
		endmethod
		method ActionValue#(IOReadReq) dataReq;
			userReadQ.deq;
			userReadEmit <= userReadEmit + 1;
			return userReadQ.first;
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
		method Action dmaWriteReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
			dmaWriteReqQ.enq(DMAWriteReq{addr:addr, words:words, tag:tag});
		endmethod
		method Action dmaWriteData(DMAWord data, Bit#(8) tag);
			dmaWriteWordQ.enq(data);
		endmethod
		method Action dmaReadReq(Bit#(32) addr, Bit#(10) words, Bit#(8) tag);
			dmaReadReqQ.enq(DMAWriteReq{addr:addr, words:words, tag:tag});
		endmethod
		method ActionValue#(DMAWordTagged) dmaReadWord;
			dmaReadWordQ.deq;
			return dmaReadWordQ.first;
		endmethod
		method Action assertInterrupt;
			user.assertInterrupt(1);
		endmethod
	endinterface
endmodule


endpackage: PcieCtrl
