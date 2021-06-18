import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

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


	rule echoRead;
		// read request handle must be returned with pcie.dataSend
		let r <- pcie.dataReq;
		let a = r.addr;

		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let offset = (a>>2);
		if ( offset == 0 ) begin 
			pcie.dataSend(r, dataBuffer0);
		end else if ( offset == 1 ) begin 
			pcie.dataSend(r, dataBuffer1);
		end else begin
			pcie.dataSend(r, pcie.debug_data);
		end
		$display( "Received read req at %x", r.addr );
	endrule
	


	Vector#(16, Reg#(Bit#(32))) writeBuffer <- replicateM(mkReg(0));
	Reg#(Bit#(4)) writeBufferCnt <- mkReg(0);



	rule recvWrite;
		let w <- pcie.dataReceive;
		let a = w.addr;
		let d = w.data;

		if ( a == 0 ) begin // command 
		end else if ( a == 4 ) begin // data load
			for ( Integer i = 1; i < 16; i++ ) begin
				writeBuffer[i+1] <= writeBuffer[i];
			end
			writeBuffer[0] <= d;
			if ( writeBufferCnt == 15 ) begin
				writeBufferCnt <= 0;
			end else begin
				writeBufferCnt <= writeBufferCnt + 1;
			end
		end
		
		// PCIe IO is done at 4 byte granularities
		// lower 2 bits are always zero
		let off = (a>>2);
		if ( off == 0 ) begin
			dataBuffer0 <= d;
		end else if ( off == 1 ) begin
			dataBuffer1 <= d;
		end else begin
			//pcie.assertUptrain;
			writeCounter <= writeCounter + 1;
		end
		$display( "Received write req at %x : %x", a, d );
	endrule

endmodule
