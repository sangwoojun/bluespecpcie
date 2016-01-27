package Platform;

import FIFO::*;
import Clocks::*;

import AuroraImportArtix7 :: *;

interface ControllerPlatformIfc;
endinterface

module mkPlatform#(AuroraIfc aurora0, Clock clk100, Reset rst100) 
	(ControllerPlatformIfc);

	Reg#(Bit#(32)) auroraDummy <- mkReg(0);
	Reg#(Bit#(1)) auroraStat <- mkReg(0);

	FIFO#(Tuple2#(DataIfc, PacketType)) auroraRQ <- mkFIFO();
	rule mirrorAuroraR;
		let d <- aurora0.receive;
		aurora0.send(tpl_1(d), tpl_2(d));
		//auroraRQ.enq(d);
	endrule

endmodule

endpackage: Platform
