////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2014  Bluespec, Inc.  ALL RIGHTS RESERVED.
////////////////////////////////////////////////////////////////////////////////
//  Filename      : XilinxVC707DDR3.bsv
//  Description   : 
////////////////////////////////////////////////////////////////////////////////
package DDR3Controller;

// Notes :

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Connectable       ::*;
import Clocks            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import TriState          ::*;
import Vector            ::*;
import DefaultValue      ::*;
import Counter           ::*;
import CommitIfc         ::*;
import Memory            ::*;
import ClientServer      ::*;
import GetPut            ::*;
import BUtils            ::*;
//import I2C               ::*;
import StmtFSM           ::*;
import DDR3Common        ::*;

//import XilinxCells       ::*;

////////////////////////////////////////////////////////////////////////////////
/// Exports
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
/// Types
////////////////////////////////////////////////////////////////////////////////
//`define DDR3_VC707 29, 256, 32, 64, 8, 15, 10, 3, 1, 1, 1, 1, 1, 4
`define DDR3_1GB 28, 512, 64, 64, 8, 14, 10, 3, 1, 1, 1, 1, 1, 2

typedef DDR3_Pins#(`DDR3_1GB) DDR3_Pins_1GB;
typedef DDR3_User#(`DDR3_1GB) DDR3_User_1GB;
typedef DDR3_Controller#(`DDR3_1GB) DDR3_Controller_1GB;
typedef VDDR3_User_Xilinx#(`DDR3_1GB) VDDR3_User_Xilinx_1GB;
typedef VDDR3_Controller_Xilinx#(`DDR3_1GB) VDDR3_Controller_Xilinx_1GB;

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
///
/// Implementation
///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
import "BVI" ddr3_wrapper =
module vMkDDR3_1GB_Controller#(DDR3_Configure cfg, Clock refclk)(VDDR3_Controller_Xilinx_1GB);
   default_clock clk(sys_clk_i);
   default_reset rst(sys_rst);
   
   input_clock refclk(clk_ref_i) = refclk;
   
   parameter SIM_BYPASS_INIT_CAL = (cfg.simulation) ? "FAST" : "OFF";
   parameter SIMULATION          = (cfg.simulation) ? "TRUE" : "FALSE";
   
   interface DDR3_Pins ddr3;
      ifc_inout   dq(ddr3_dq)          clocked_by(no_clock)  reset_by(no_reset);
      ifc_inout   dqs_p(ddr3_dqs_p)    clocked_by(no_clock)  reset_by(no_reset);
      ifc_inout   dqs_n(ddr3_dqs_n)    clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_ck_p    clk_p   clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_ck_n    clk_n   clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_cke     cke     clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_cs_n    cs_n    clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_ras_n   ras_n   clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_cas_n   cas_n   clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_we_n    we_n    clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_reset_n reset_n clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_dm      dm      clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_ba      ba      clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_addr    a       clocked_by(no_clock)  reset_by(no_reset);
      method      ddr3_odt     odt     clocked_by(no_clock)  reset_by(no_reset);
   endinterface
   
   interface VDDR3_User_Xilinx user;
      output_clock    clock(ui_clk);
      output_reset    reset(ui_clk_sync_rst);
      method init_calib_complete      init_done    clocked_by(no_clock) reset_by(no_reset);
      method          		      app_addr(app_addr) enable((*inhigh*)en0) clocked_by(user_clock) reset_by(no_reset);
      method                          app_cmd(app_cmd)   enable((*inhigh*)en00) clocked_by(user_clock) reset_by(no_reset);
      method          		      app_en(app_en)     enable((*inhigh*)en1) clocked_by(user_clock) reset_by(no_reset);
      method          		      app_wdf_data(app_wdf_data) enable((*inhigh*)en2) clocked_by(user_clock) reset_by(no_reset);
      method          		      app_wdf_end(app_wdf_end)   enable((*inhigh*)en3) clocked_by(user_clock) reset_by(no_reset);
      method          		      app_wdf_mask(app_wdf_mask) enable((*inhigh*)en4) clocked_by(user_clock) reset_by(no_reset);
      method          		      app_wdf_wren(app_wdf_wren) enable((*inhigh*)en5) clocked_by(user_clock) reset_by(no_reset);
      method app_rd_data              app_rd_data clocked_by(user_clock) reset_by(no_reset);
      method app_rd_data_end          app_rd_data_end clocked_by(user_clock) reset_by(no_reset);
      method app_rd_data_valid        app_rd_data_valid clocked_by(user_clock) reset_by(no_reset);
      method app_rdy                  app_rdy clocked_by(user_clock) reset_by(no_reset);
      method app_wdf_rdy              app_wdf_rdy clocked_by(user_clock) reset_by(no_reset);
   endinterface
   
   schedule
   (
    ddr3_clk_p, ddr3_clk_n, ddr3_cke, ddr3_cs_n, ddr3_ras_n, ddr3_cas_n, ddr3_we_n, 
    ddr3_reset_n, ddr3_dm, ddr3_ba, ddr3_a, ddr3_odt, user_init_done
    )
   CF
   (
    ddr3_clk_p, ddr3_clk_n, ddr3_cke, ddr3_cs_n, ddr3_ras_n, ddr3_cas_n, ddr3_we_n, 
    ddr3_reset_n, ddr3_dm, ddr3_ba, ddr3_a, ddr3_odt, user_init_done
    );
   
   schedule 
   (
    user_app_addr, user_app_en, user_app_wdf_data, user_app_wdf_end, user_app_wdf_mask, user_app_wdf_wren, user_app_rd_data, 
    user_app_rd_data_end, user_app_rd_data_valid, user_app_rdy, user_app_wdf_rdy, user_app_cmd
    )
   CF
   (
    user_app_addr, user_app_en, user_app_wdf_data, user_app_wdf_end, user_app_wdf_mask, user_app_wdf_wren, user_app_rd_data, 
    user_app_rd_data_end, user_app_rd_data_valid, user_app_rdy, user_app_wdf_rdy, user_app_cmd
    );

endmodule
module mkDDR3Controller_1GB#(DDR3_Configure cfg, Clock refclk)(DDR3_Controller_1GB);
   (* hide_all *)
   VDDR3_Controller_Xilinx_1GB _v <- vMkDDR3_1GB_Controller(cfg, refclk);
   let _m <- mkXilinxDDR3Controller_2_1_(_v, cfg);
   return _m;
endmodule


endpackage: DDR3Controller

