import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;
import DRAMBurstController::*;
import DRAMHostDMA::*;
import MergeN::*;

import DRAMVectorPacker::*;
import MergeSorter::*;

interface HwMainIfc;
endinterface


function Tuple2#(Bit#(ksz),Bit#(vsz)) decodeTuple2(Bit#(w) in)
	provisos(Add#(ksz,vsz,w)
	);

	Bit#(ksz) keybits = truncate(in);
	Bit#(vsz) valbits = truncate(in>>valueOf(ksz));

	return tuple2(keybits, valbits);
endfunction

function Bit#(w) encodeTuple2(Tuple2#(Bit#(ksz),Bit#(vsz)) kvp)
	provisos(Add#(ksz,vsz,w)
	);
	Bit#(ksz) keybits = tpl_1(kvp);
	Bit#(vsz) valbits = tpl_2(kvp);

	return {valbits,keybits};
endfunction

module mkHwMainBoiler#(PcieUserIfc pcie, DRAMUserIfc dram) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	StreamVectorMergeSorterIfc#(8, 3, Bit#(64), Bit#(32)) sorter8 <- mkMergeSorter8(False);

	for ( Integer i = 0; i < 8; i=i+1 ) begin
		Reg#(Bit#(32)) cnt <- mkReg(0);
		rule ins ( cnt < 20000 );
			Vector#(3, Tuple2#(Bit#(64), Bit#(32))) inv;
			inv[0] = tuple2(zeroExtend(cnt)*fromInteger(i+3), 1);
			if ( cnt == 736 || cnt == 737 ) begin
				inv[1] = tuple2(zeroExtend(cnt)*fromInteger(i+3)+64'h1000000000, 99);
			end else begin
				inv[1] = tuple2(zeroExtend(cnt)*fromInteger(i+3)+1, 99);
			end
			inv[2] = tuple2(zeroExtend(cnt)*fromInteger(i+3)+2, 4);
			sorter8.enq[i].enq(tagged Valid inv);
			cnt <= cnt + 1;
		endrule
		rule insr ( cnt == 20000 );
			sorter8.enq[i].enq(tagged Invalid);
			cnt <= cnt + 1;
		endrule
	end

	Reg#(Bit#(32)) outCnt <- mkReg(0);
	rule getr;
		outCnt <= outCnt + 1;
		let r <- sorter8.get;
		if ( isValid(r) ) begin
			let rr = fromMaybe(?, r);
			if ( tpl_1(rr[0]) > 64'hffffffff ||  tpl_1(rr[1]) > 64'hffffffff || tpl_1(rr[2]) > 64'hffffffff ) begin
				$display(">> %d %x %x %x\n", outCnt, tpl_1(rr[0]), tpl_1(rr[1]), tpl_1(rr[2]));
			end
		end else begin
			$display("Done!");
		end
	endrule
endmodule



module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;


	DRAMBurstControllerIfc dramBurst <- mkDRAMBurstController(dram);
	DRAMBurstSplitterIfc#(9,2) dramSplitter <- mkDRAMBurstSplitter(dramBurst);

	DRAMHostDMAIfc dramHostDma <- mkDRAMHostDMA(pcie, dramSplitter.readers[0], dramSplitter.writers[0]);
	Vector#(8, DRAMVectorUnpacker#(3,Bit#(96))) dramReaders;
	for ( Integer i = 0; i < 8; i=i+1 ) begin
		dramReaders[i] <- mkDRAMVectorUnpacker(dramSplitter.readers[i+1], 128);
	end
	
	DRAMVectorPacker#(3,Bit#(96)) dramWriter <- mkDRAMVectorPacker(dramSplitter.writers[1], 128);
	StreamVectorMergeSorterIfc#(8, 3, Bit#(64), Bit#(32)) sorter8 <- mkMergeSorter8(False);

	//Vector#(3, FIFOF#(Bit#(32))) sampleQs <- replicateM(mkSizedFIFOF(32));
	//FIFOF#(Bit#(32)) sampleQo <- mkSizedFIFOF(32);

	//Vector#(3, FIFO#(Vector#(3,Tuple2#(Bit#(64),Bit#(32))))) allQs <- replicateM(mkFIFO);
	//Vector#(3, FIFO#(Tuple2#(Bit#(64),Bit#(32)))) allEQs <- replicateM(mkFIFO);

	Vector#(8, Reg#(Bit#(32))) dramReadCnt <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 8; i=i+1 ) begin
		rule relayInput;
			let d <- dramReaders[i].get;

			if ( !isValid(d) ) begin
				dramReadCnt[i] <= dramReadCnt[i] | (1<<31);
				sorter8.enq[i].enq(tagged Invalid);
			end else begin
				Vector#(3,Bit#(96)) v_ = fromMaybe(?,d);
				Vector#(3,Tuple2#(Bit#(64),Bit#(32))) v = map(decodeTuple2,v_);
			
				sorter8.enq[i].enq(tagged Valid v);
				dramReadCnt[i] <= dramReadCnt[i] + 1;

				//if ( i < 3 ) allQs[i].enq(v);

/*
				Bit#(32) v0t = truncateLSB(tpl_1(v[0]));
				Bit#(32) v1t = truncateLSB(tpl_1(v[1]));
				Bit#(32) v2t = truncateLSB(tpl_1(v[2]));
				if ( i < 3 &&  sampleQs[i].notFull ) begin
					if ( v0t > 0 ) begin
						sampleQs[i].enq(v0t);
					end else if ( v1t > 0 ) begin
						sampleQs[i].enq(v1t | (1<<30));
					end else if ( v2t > 0 ) begin
						sampleQs[i].enq(v2t | (2<<30));
					end
				end
*/

			end
		endrule
/*
		if ( i < 3 ) begin
			Reg#(Bit#(3)) serallIdx <- mkReg(0);
			Reg#(Vector#(3,Tuple2#(Bit#(64),Bit#(32)))) serallBuf <- mkReg(?);
			rule serializeAll;
				if ( serallIdx == 0 ) begin
					allQs[i].deq;
					let v = allQs[i].first;
					serallBuf <= v;
					allEQs[i].enq(v[0]);
					serallIdx <= 1;
				end
				else if ( serallIdx == 1 ) begin
					allEQs[i].enq(serallBuf[1]);
					serallIdx <= 2;
				end
				else if ( serallIdx == 2 ) begin
					allEQs[i].enq(serallBuf[2]);
					serallIdx <= 0;
				end
			endrule

			Reg#(Bit#(3)) serallEIdx <- mkReg(0);
			Reg#(Tuple2#(Bit#(64),Bit#(32))) serallEBuf <- mkReg(?);
			rule serialize32;
				if ( serallEIdx == 0 ) begin
					allEQs[i].deq;
					let v = allEQs[i].first;
					serallEBuf <= v;
					sampleQs[i].enq(truncateLSB(tpl_1(v)));
					serallEIdx <= 1;
				end
				else if ( serallEIdx == 1 ) begin
					serallEIdx <= 2;
					sampleQs[i].enq(truncate(tpl_1(serallEBuf)));
				end
				else if ( serallEIdx == 2 ) begin
					serallEIdx <= 0;
					sampleQs[i].enq(tpl_2(serallEBuf));
				end
				
			endrule
		end
		*/
	end
	

	FIFOF#(Bit#(64)) doneReachedQ <- mkSizedFIFOF(8);
	Reg#(Bit#(64)) sortedCnt <- mkReg(0);

	rule getMerged;
		let r <- sorter8.get;

		if ( !isValid(r) ) begin
			dramWriter.put(tagged Invalid);
			doneReachedQ.enq(sortedCnt);
			sortedCnt <= 0;
		end else begin
			sortedCnt <= sortedCnt + 1;
			dramWriter.put(tagged Valid map(encodeTuple2, fromMaybe(?,r)));

/*
			let v = fromMaybe(?,r);
			if ( sampleQo.notFull ) begin
				sampleQo.enq(truncate(tpl_1(v[0])));
			end
*/
			/*
			Bit#(32) v0t = truncateLSB(tpl_1(v[0]));
			Bit#(32) v1t = truncateLSB(tpl_1(v[1]));
			Bit#(32) v2t = truncateLSB(tpl_1(v[2]));
			if (  sampleQo.notFull ) begin
				if ( v0t > 0 ) begin
					sampleQo.enq(v0t);
				end else if ( v1t > 0 ) begin
					sampleQo.enq(v1t);
				end else if ( v2t > 0 ) begin
					sampleQo.enq(v2t);
				end
			end
			*/
		end
	endrule

	FIFO#(Bit#(64)) writeBufferDoneBytesQ <- mkSizedFIFO(8);
	MergeNIfc#(9, Bit#(8)) mBufferDone <- mkMergeN;
	for (Integer i = 0; i < 8; i=i+1 ) begin
		rule relayReadDone;
			dramReaders[i].bufferDone;
			mBufferDone.enq[i].enq(fromInteger(i));
		endrule
	end
	
	rule relayWriteDone;
		let bytes <- dramWriter.bufferDone;
		mBufferDone.enq[8].enq(8);
		writeBufferDoneBytesQ.enq(bytes);
	endrule
	
	FIFOF#(Bit#(8)) mergedQ <- mkFIFOF;
	rule relayMergedQ;
		mBufferDone.deq;
		mergedQ.enq(mBufferDone.first);
	endrule


	Vector#(4, Reg#(Bit#(32))) cmdArgs <- replicateM(mkReg(0));
	rule getCmd;
		IOWrite r <- dramHostDma.dataReceive;
		let a = r.addr;
		let d = r.data;
		let off = ( a>>2 );

		if ( off < 4 ) begin // args
			cmdArgs[off] <= d;
		end else if ( off == 8 ) begin
			dramWriter.addBuffer({cmdArgs[0], cmdArgs[1]}, cmdArgs[2]);
		end else if ( off == 9 ) begin
			dramReaders[d].addBuffer({cmdArgs[0], cmdArgs[1]}, cmdArgs[2], False);
		end
	endrule

	rule getStatus;
		IOReadReq r <- dramHostDma.dataReq;
		let a = r.addr;
		let off = (a>>2);
		if ( off == 0 ) begin
			dramHostDma.dataSend(r, truncate(sortedCnt));
		end else if ( off == 1 ) begin
			if ( doneReachedQ.notEmpty ) begin
				doneReachedQ.deq;
				dramHostDma.dataSend(r, truncate(doneReachedQ.first));
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off < 10 ) begin
			dramHostDma.dataSend(r, dramReadCnt[off-2]);
			/*
		end else if ( off == 10 ) begin
			if ( sampleQs[0].notEmpty ) begin
				sampleQs[0].deq;
				dramHostDma.dataSend(r, sampleQs[0].first);
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 11 ) begin
			if ( sampleQs[1].notEmpty ) begin
				sampleQs[1].deq;
				dramHostDma.dataSend(r, sampleQs[1].first);
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 12 ) begin
			if ( sampleQs[2].notEmpty ) begin
				sampleQs[2].deq;
				dramHostDma.dataSend(r, sampleQs[2].first);
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 13 ) begin
			if ( sampleQo.notEmpty ) begin
				sampleQo.deq;
				dramHostDma.dataSend(r, sampleQo.first);
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		*/
		end else if ( off == 16 ) begin
			if ( mergedQ.notEmpty ) begin
				mergedQ.deq;
				dramHostDma.dataSend(r, zeroExtend(mergedQ.first));
			end else begin
				dramHostDma.dataSend(r, 32'hffffffff);
			end
		end else if ( off == 17 ) begin
			let d = writeBufferDoneBytesQ.first;
			writeBufferDoneBytesQ.deq;
			dramHostDma.dataSend(r, truncate(d));
		end else begin
			dramHostDma.dataSend(r, 32'hffffffff);
		end
	endrule

endmodule
