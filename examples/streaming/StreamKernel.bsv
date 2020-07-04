package StreamKernel;

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

typedef Bit#(256) StreamWord;

interface StreamKernelIfc;
	method Action enq(StreamWord data);
	method StreamWord first;
	method Action deq;
endinterface

module mkStreamKernelTest (StreamKernelIfc);
	FIFO#(StreamWord) inQ <- mkFIFO;
	FIFO#(StreamWord) outQ <- mkFIFO;

	rule proct;
		inQ.deq;
		let d = inQ.first & 256'hffffffff_ffffffff_ffffffff_ffffffff__ffffffff_ffffffff_ffffffff_00000000;
		d = d | 256'hdeadbeef;
		outQ.enq(d);
		//outQ.enq(inQ.first & 256'hffffffff_ffffffff_ffffffff_ffffffff__ffffffff_ffffffff_ffffffff_ffffffff);
		$write("kernel proct\n");
	endrule

	method Action enq(StreamWord data);
		inQ.enq(data);
	endmethod
	method StreamWord first;
		return outQ.first;
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
endmodule

endpackage: StreamKernel
