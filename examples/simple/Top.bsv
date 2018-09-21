/*
*/

import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;

import PcieImport :: *;
import PcieCtrl :: *;
import PcieCtrl_bsim :: *;

import Clocks       :: *;
import FIFO::*;

import HwMain::*;

//import Platform :: *;

//import NullReset :: *;
//import IlaImport :: *;

interface TopIfc;
	(* always_ready *)
	interface PcieImportPins pcie_pins;
	(* always_ready *)
	method Bit#(4) led;
endinterface

(* no_default_clock, no_default_reset *)
module mkProjectTop #(
	Clock pcie_clk_p, Clock pcie_clk_n, Clock emcclk,
	Clock sys_clk_p, Clock sys_clk_n,
	Reset pcie_rst_n
	) 
		(TopIfc);


	PcieImportIfc pcie <- mkPcieImport(pcie_clk_p, pcie_clk_n, pcie_rst_n, emcclk);
	Clock pcie_clk_buf = pcie.sys_clk_o;
	Reset pcie_rst_n_buf = pcie.sys_rst_n_o;

	Clock sys_clk_200mhz <- mkClockIBUFDS(defaultValue, sys_clk_p, sys_clk_n);
	Clock sys_clk_200mhz_buf <- mkClockBUFG(clocked_by sys_clk_200mhz);
	Reset rst200 <- mkAsyncReset( 4, pcie_rst_n, sys_clk_200mhz_buf);

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl(pcie.user, clocked_by pcie.user_clk, reset_by pcie.user_reset);
	/*
	ClockGenerator7Params clk_params = defaultValue();
	clk_params.clkin1_period     = 10.000;       // 100 MHz reference
	clk_params.clkin_buffer      = False;       // necessary buffer is instanced above
	clk_params.reset_stages      = 0;           // no sync on reset so input clock has pll as only load
	clk_params.clkfbout_mult_f   = 10.000;       // 1000 MHz VCO
	clk_params.clkout0_divide_f  = 4;          // 250MHz clock
	clk_params.clkout1_divide    = 8;           // 125MHz clock
	ClockGenerator7 clk_gen <- mkClockGenerator7(clk_params, clocked_by sys_clk_buf, reset_by sys_rst_n_buf);
	Clock clk250 = clk_gen.clkout0;
	Reset rst250 <- mkAsyncReset( 4, sys_rst_n_buf, clk250);
	
	Clock clk125 = clk_gen.clkout0;
	Reset rst125 <- mkAsyncReset( 4, sys_rst_n_buf, clk125);
	*/
	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, clocked_by sys_clk_200mhz_buf, reset_by rst200);

	//ReadOnly#(Bit#(4)) leddata <- mkNullCrossingWire(noClock, pcieCtrl.leds);

	// Interfaces ////
	interface PcieImportPins pcie_pins = pcie.pins;

	method Bit#(4) led;
		//return leddata;
		return 0;
	endmethod
endmodule

module mkProjectTop_bsim (Empty);
	Clock curclk <- exposeCurrentClock;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl_bsim;

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user);
endmodule
