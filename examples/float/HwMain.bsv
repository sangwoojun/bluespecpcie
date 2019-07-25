import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import DMASplitter::*;

import Float32::*;
import Float64::*;
import Cordic::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Reg#(Bit#(32)) dataBuffer0 <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) dataBuffer1 <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) writeCounter <- mkReg(0, clocked_by pcieclk, reset_by pcierst);

	FpPairIfc#(64) mult <- mkFpMult64(clocked_by pcieclk, reset_by pcierst);
	FpFilterIfc#(64) sqrt <- mkFpSqrt64(clocked_by pcieclk, reset_by pcierst);
	CordicSinCosIfc sincos <- mkCordicSinCos(clocked_by pcieclk, reset_by pcierst);

	Reg#(Bit#(64)) doubleResultBuffer <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(64)) doubleResultBuffer2 <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(32)) cordicResultBuffer <- mkReg(0, clocked_by pcieclk, reset_by pcierst);


	Reg#(Bit#(64)) doubleBuffer1 <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(64)) doubleBuffer2 <- mkReg(0, clocked_by pcieclk, reset_by pcierst);

	rule echoRead;
		// read request handle must be returned with pcie.dataSend
		let r <- pcie.dataReq;
		let a = r.addr;

		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let offset = (a>>2);
		if ( offset == 0 ) begin 
			pcie.dataSend(r, truncate(doubleResultBuffer));
		end else if ( offset == 1 ) begin 
			pcie.dataSend(r, truncate(doubleResultBuffer>>32));
		end else if ( offset == 2 ) begin 
			pcie.dataSend(r, truncate(doubleResultBuffer2));
		end else if ( offset == 3 ) begin 
			pcie.dataSend(r, truncate(doubleResultBuffer2>>32));
		end else if ( offset == 4 ) begin
			pcie.dataSend(r, cordicResultBuffer);
		end else begin
			//pcie.dataSend(r, pcie.debug_data);
			pcie.dataSend(r, writeCounter);
		end
		$display( "Received read req at %x", r.addr );
	endrule
	rule recvWrite;
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		
		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let off = (a>>2);
		if ( off == 0 ) begin
			doubleBuffer1 <= zeroExtend(d);
		end else if ( off == 1 ) begin
			doubleBuffer1 <= doubleBuffer1 | (zeroExtend(d)<<32);
		end else if ( off == 2 ) begin
			doubleBuffer2 <= zeroExtend(d);
		end else if ( off == 3 ) begin
			Bit#(64) b2 = doubleBuffer2 | (zeroExtend(d)<<32);
			mult.enq(doubleBuffer1, b2);
			sqrt.enq(b2);
		end else if ( off == 4 ) begin
			sincos.enq(truncate(d));
		end else begin
			//pcie.assertUptrain;
			writeCounter <= writeCounter + 1;
		end
		$display( "Received write req at %x : %x", a, d );
	endrule
	rule rrrr;
		Bit#(64) d = mult.first;
		mult.deq;
		doubleResultBuffer <= d;
		$display( "mult %x ", d );
	endrule
	rule rrrr2;
		Bit#(64) d = sqrt.first;
		sqrt.deq;
		doubleResultBuffer2 <= d;
		$display( "sqrt %x ", d );
	endrule
	rule rrrr3;
		let d = sincos.first;
		sincos.deq;
		cordicResultBuffer <= {tpl_1(d),tpl_2(d)};
		$display( "sincos %x ", d );
	endrule

endmodule
