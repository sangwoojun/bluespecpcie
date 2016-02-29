package CompletionFIFO;

import Vector::*;
import FIFO::*;
import BRAM::*;

import BRAMFIFO::*;

interface CompletionFIFOIfc#(type burstWord, numeric type burstSz, numeric type tagSz);
	method Action enq(burstWord w, Bit#(tagSz) tag);
	method Tuple2#(burstWord, Bit#(tagSz)) first;
	method Action deq;
endinterface

module mkCompletionFIFO (CompletionFIFOIfc#(burstWord, burstSz, tagSz));
	method Action enq(burstWord w, Bit#(tagSz) tag);
	endmethod
	method Tuple2#(burstWord, Bit#(tagSz)) first;
		return ?;
	endmethod
	method Action deq;
	endmethod
endmodule

endpackage: CompletionFIFO
