package ClockImport;
import Clocks            ::*;
import "BVI" IBUFDS =
module mkClockIBUFDSImport#(Clock clk_p, Clock clk_n)(ClockGenIfc);
   default_clock no_clock;
   default_reset no_reset;
   
   parameter CAPACITANCE      = "DONT_CARE";
   parameter DIFF_TERM        = "FALSE";
   parameter DQS_BIAS         = "FALSE";
   parameter IBUF_DELAY_VALUE = "0";
   parameter IBUF_LOW_PWR     = "TRUE";
   parameter IFD_DELAY_VALUE  = "AUTO";
   parameter IOSTANDARD       = "DEFAULT";

   input_clock clk_p(I)  = clk_p;
   input_clock clk_n(IB) = clk_n;

   output_clock gen_clk(O);

   path(I,  O);
   path(IB, O);

   same_family(clk_p, gen_clk);
endmodule

import "BVI" BUFG =
module mkClockBUFGImport(ClockGenIfc);
	default_clock clk(I, (*unused*)GATE);
	default_reset no_reset;

	path(I, O);

	output_clock gen_clk(O);
	same_family(clk, gen_clk);
endmodule


endpackage: ClockImport
