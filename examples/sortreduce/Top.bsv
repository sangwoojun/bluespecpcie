/*
*/

import Clocks::*;
import DefaultValue::*;
import FIFO::*;
import Connectable::*;

import Xilinx::*;
import XilinxCells::*;

// PCIe stuff
import PcieImport :: *;
import PcieCtrl :: *;
import PcieCtrl_bsim :: *;

// DRAM stuff
import DDR3Sim::*;
import DDR3Controller::*;
import DDR3Common::*;
import DRAMController::*;

import HwMain::*;

//import Platform :: *;

//import NullReset :: *;
//import IlaImport :: *;

interface TopIfc;
	(* always_ready *)
	interface PcieImportPins pcie_pins;
	(* always_ready *)
	method Bit#(4) led;
	
`ifdef kc705
	interface DDR3_Pins_KC705_1GB pins_ddr3;
`endif
`ifdef vc707
	interface DDR3_Pins_VC707_1GB pins_ddr3;
`endif
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
	Reset rst200 <- mkAsyncReset( 4, pcie_rst_n_buf, sys_clk_200mhz_buf);

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl(pcie.user, clocked_by pcie.user_clk, reset_by pcie.user_reset);
	

	ClockDividerIfc clk_div_100mhz <- mkClockDivider(2, clocked_by sys_clk_200mhz_buf, reset_by rst200 );
	Clock clk_100mhz = clk_div_100mhz.slowClock;
	Reset rst_100mhz <- mkAsyncReset(4, rst200, clk_100mhz);


	//DRAMControllerIfc dramController <- mkDRAMController(clocked_by sys_clk_200mhz_buf, reset_by rst200);
	//DRAMControllerIfc dramController <- mkDRAMController(clocked_by pcieCtrl.user.user_clk, reset_by pcieCtrl.user.user_rst);
	DRAMControllerIfc dramController <- mkDRAMController(clocked_by clk_100mhz, reset_by rst_100mhz);

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, dramController.user, clocked_by sys_clk_200mhz_buf, reset_by rst200);
	
	Clock ddr_buf = sys_clk_200mhz_buf;
	//Clock ddr_buf = clk200;
	Reset ddr3ref_rst_n <- mkAsyncResetFromCR(4, ddr_buf, reset_by pcieCtrl.user.user_rst);

	DDR3Common::DDR3_Configure ddr3_cfg = defaultValue;
	ddr3_cfg.reads_in_flight = 32;   // adjust as needed

`ifdef kc705
	DDR3_Controller_KC705_1GB ddr3_ctrl <- mkDDR3Controller_KC705_1GB(ddr3_cfg, ddr_buf, clocked_by ddr_buf, reset_by ddr3ref_rst_n);
`endif
`ifdef vc707
	DDR3_Controller_VC707_1GB ddr3_ctrl <- mkDDR3Controller_VC707_1GB(ddr3_cfg, ddr_buf, clocked_by ddr_buf, reset_by ddr3ref_rst_n);
`endif

	Clock ddr3clk = ddr3_ctrl.user.clock;
	Reset ddr3rstn = ddr3_ctrl.user.reset_n;

	let ddr_cli_200Mhz <- mkDDR3ClientSync(dramController.ddr3_cli, clockOf(dramController), resetOf(dramController), ddr3clk, ddr3rstn, clocked_by sys_clk_200mhz_buf, reset_by rst200);
	mkConnection(ddr_cli_200Mhz, ddr3_ctrl.user);

	//ReadOnly#(Bit#(4)) leddata <- mkNullCrossingWire(noClock, pcieCtrl.leds);

	// Interfaces ////
	interface PcieImportPins pcie_pins = pcie.pins;

`ifdef kc705
	interface DDR3_Pins_KC705_1GB pins_ddr3 = ddr3_ctrl.ddr3;
`endif
`ifdef vc707
	interface DDR3_Pins_VC707_1GB pins_ddr3 = ddr3_ctrl.ddr3;
`endif

	method Bit#(4) led;
		//return leddata;
		return 0;
	endmethod
endmodule

module mkProjectTop_bsim (Empty);
	Clock curclk <- exposeCurrentClock;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl_bsim;
	
	DRAMControllerIfc dramController <- mkDRAMController();
	let ddr3_ctrl_user <- mkDDR3Simulator;
	mkConnection(dramController.ddr3_cli, ddr3_ctrl_user);

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, dramController.user);
endmodule
