import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import Float32::*;
import Float64::*;
import Cordic::*;

import StmtFSM::*;

import QueueALU::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;


	Reg#(Bit#(32)) cycleCount <- mkReg(0);
	rule countCycle;
		cycleCount <= cycleCount + 1;
	endrule

	//QueueALUIfc#(2) qalu <- mkQueueALU;
	QueueALUIfc#(2) qalu <- mkQueueALU_2;

	

	Vector#(2,Bit#(64)) invector1;
	Vector#(2,Bit#(64)) invector2;
	invector1[0] = 64'h4020000000000000; // 8
	invector1[1] = 64'h4010000000000000; // 4
	invector2[0] = 64'h0000000000000000; // 0
	invector2[1] = 64'h3ff0000000000000; // 1

	Stmt drivealu =
	seq
		qalu.putTop(invector1);
		qalu.putNext(invector2);
		qalu.command(ALUMult, ALUInput, ALUInput, 0);
		qalu.putNext(invector2);
		qalu.command(ALUMult, ALUQueue, ALUInput, 0);
		qalu.command(ALUMult, ALUImm1, ALUImm2, 0);

		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 0);

		qalu.command(ALUOutput, ALUImm1, ALUImm2, 0);

		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUMult, ALUQueue, ALUQueue, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
		qalu.command(ALUAdd, ALUQueue, ALUImm2, 1);

		qalu.command(ALUOutput, ALUImm1, ALUImm2, 2);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 2);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 2);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		while(cycleCount < 10000) noAction;
	endseq;
	mkAutoFSM(drivealu);

	FIFO#(Vector#(2,Bit#(64))) outputQ <- mkSizedBRAMFIFO(256);
	rule getALUOut;
		let d <- qalu.get;
		$write( "%d: %x %x\n", cycleCount, d[0], d[1] );
		outputQ.enq(d);
	endrule



/*
	CompletionQueueIfc#(8,Bit#(128)) cqueue <- mkCompletionQueue;

	Reg#(Bit#(8)) enqCnt <- mkReg(0);
	rule tryEnq (enqCnt < 128);
		enqCnt <= enqCnt + 1;
		let a <- cqueue.enq;
		$write( "CQueue handle: %d\n", a );

	endrule

	rule newComplete(enqCnt >= 128 && enqCnt <= 128+64);
		enqCnt <= enqCnt + 1;
		cqueue.complete(64-(enqCnt-128), zeroExtend(enqCnt-128));
		$write( "Complete %d\n", 64-(enqCnt-128) );
	endrule

	rule tryDeq;
		cqueue.deq;
		let d = cqueue.first;
		$write( "CQueue result: %x %d\n", d, cycleCount );
	endrule
*/



/*
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
*/

	rule echoRead;
		// read request handle must be returned with pcie.dataSend
		let r <- pcie.dataReq;
		let a = r.addr;
		let d = outputQ.first;
		outputQ.deq;
		if ( a[2] == 0 ) begin 
			pcie.dataSend(r, truncate(d[0]>>((a>>3)*32)) );
		end else begin
			pcie.dataSend(r, truncate(d[1]>>((a>>3)*32)) );
		end
	endrule
	rule recvWrite;
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;
		case (d[2:0])
			0: qalu.command(ALUSqrt, ALUQueue, ALUImm1, 1);
			1: qalu.command(ALUAdd, ALUQueue, ALUQueue, 2);
			2: qalu.command(ALUMult, ALUQueue, ALUQueue, 2);
			3: qalu.command(ALUOutput, ALUImm1, ALUImm2, 1);
		endcase
	endrule
/*
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
*/
endmodule
