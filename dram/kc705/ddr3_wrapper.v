
// Copyright (c) 2000-2009 Bluespec, Inc.

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// $Revision$
// $Date$

// This is a wrapper around the ddr3 module generated from coregen.

module debug_ddr
  (
   input         ui_clk,
   input         ui_clk_sync_rst,//
   input         init_calib_complete,//
   input         sys_rst,//

   input [27:0]  app_addr, //
   input [2:0]   app_cmd,//
   input         app_en,//
   input [511:0] app_wdf_data,//
   input         app_wdf_end,//
   input [63:0]  app_wdf_mask,//
   input         app_wdf_wren,//
   input [511:0] app_rd_data,//
   input         app_rd_data_end,//
   input         app_rd_data_valid,//
   input         app_rdy,//
   input         app_wdf_rdy//
   );

   (* mark_debug = "true" *) reg          ui_clk_sync_rst_reg;//
   (* mark_debug = "true" *) reg          init_calib_complete_reg;//
   (* mark_debug = "true" *) reg          sys_rst_reg;

   (* mark_debug = "true" *) reg [27:0]   app_addr_reg; //
   (* mark_debug = "true" *) reg [2:0]    app_cmd_reg;//
   (* mark_debug = "true" *) reg          app_en_reg;//
   (* mark_debug = "true" *) reg [511:0]  app_wdf_data_reg;//
   (* mark_debug = "true" *) reg          app_wdf_end_reg;//
   (* mark_debug = "true" *) reg [63:0]   app_wdf_mask_reg;//
   (* mark_debug = "true" *) reg          app_wdf_wren_reg;//
   (* mark_debug = "true" *) reg [511:0] app_rd_data_reg;//
   (* mark_debug = "true" *) reg         app_rd_data_end_reg;//
   (* mark_debug = "true" *) reg         app_rd_data_valid_reg;//
   (* mark_debug = "true" *) reg         app_rdy_reg;//
   (* mark_debug = "true" *) reg         app_wdf_rdy_reg;//
   

   always @ (posedge ui_clk) begin
      ui_clk_sync_rst_reg <= ui_clk_sync_rst;//
      init_calib_complete_reg <= init_calib_complete;//
      sys_rst_reg <= sys_rst;

      app_addr_reg <= app_addr; //
      app_cmd_reg <= app_cmd;//
      app_en_reg <= app_en;//
      app_wdf_data_reg <= app_wdf_data;//
      app_wdf_end_reg <= app_wdf_end;//
      app_wdf_mask_reg <= app_wdf_mask;//
      app_wdf_wren_reg <= app_wdf_wren;//
      app_rd_data_reg <= app_rd_data;//
      app_rd_data_end_reg <= app_rd_data_end;//
      app_rd_data_valid_reg <= app_rd_data_valid;//
      app_rdy_reg <= app_rdy;//
      app_wdf_rdy_reg <= app_wdf_rdy;//
   end
   
/*
   ila_ddr u_ila_ddr
     (
      .clk	(ui_clk),
      .probe0	(app_addr_reg),
      .probe1	(app_cmd_reg),
      .probe2	(app_en_reg),
      .probe3	(app_wdf_data_reg),
      .probe4	(app_wdf_end_reg),
      .probe5	(app_wdf_mask_reg),
      .probe6	(app_wdf_wren_reg),
      .probe7	(app_rd_data_reg),
      .probe8	(app_rd_data_end_reg),
      .probe9	(app_rd_data_valid_reg),
      .probe10	(app_rdy_reg),
      .probe11	(app_wdf_rdy_reg),
      .probe12	(ui_clk_sync_rst_reg),
      .probe13	(init_calib_complete_reg),
      .probe14	(sys_rst_reg),
      .probe15 	(0)
      );
  */ 
endmodule // debug_ddr

module ddr3_wrapper #
  (
   parameter SIM_BYPASS_INIT_CAL    = "OFF",
   parameter SIMULATION             = "FALSE"
   )
   (
    // Inouts
    inout [63:0]   ddr3_dq,
    inout [7:0]    ddr3_dqs_n,
    inout [7:0]    ddr3_dqs_p,
    output [13:0]  ddr3_addr,
    output [2:0]   ddr3_ba,
    output         ddr3_ras_n,
    output         ddr3_cas_n,
    output         ddr3_we_n,
    output         ddr3_reset_n,
    output [0:0]   ddr3_ck_p,
    output [0:0]   ddr3_ck_n,
    output [0:0]   ddr3_cke,
    output [0:0]   ddr3_cs_n,
    output [7:0]   ddr3_dm,
    output [0:0]   ddr3_odt,
    input          sys_clk_i,
    input          clk_ref_i,
   
    input [27:0]   app_addr, //
    input [2:0]    app_cmd,//
    input          app_en,//
    input [511:0]  app_wdf_data,//
    input          app_wdf_end,//
    input [63:0]   app_wdf_mask,//
    input          app_wdf_wren,//
    output [511:0] app_rd_data,//
    output         app_rd_data_end,//
    output         app_rd_data_valid,//
    output         app_rdy,//
    output         app_wdf_rdy,//
    input          app_sr_req,
    input          app_ref_req,
    input          app_zq_req,
    output         app_sr_active,
    output         app_ref_ack,
    output         app_zq_ack,
    output         ui_clk,
    output         ui_clk_sync_rst,//
    output         init_calib_complete,//
    input          sys_rst//
    );

   debug_ddr _debug_ddr
     (
      .ui_clk			(ui_clk),
      .app_addr			(app_addr),
      .app_cmd			(app_cmd),
      .app_en			(app_en),
      .app_wdf_data		(app_wdf_data),
      .app_wdf_end		(app_wdf_end),
      .app_wdf_mask		(app_wdf_mask),
      .app_wdf_wren		(app_wdf_wren),
      .app_rd_data		(app_rd_data),
      .app_rd_data_end		(app_rd_data_end),
      .app_rd_data_valid	(app_rd_data_valid),
      .app_rdy			(app_rdy),
      .app_wdf_rdy 		(app_wdf_rdy),
      .ui_clk_sync_rst		(ui_clk_sync_rst),
      .init_calib_complete	(init_calib_complete),
      .sys_rst			(sys_rst)
      );
   
   ddr3_0 u_ddr3_0
     (
      // Memory interface ports
      .ddr3_addr                      (ddr3_addr),
      .ddr3_ba                        (ddr3_ba),
      .ddr3_cas_n                     (ddr3_cas_n),
      .ddr3_ck_n                      (ddr3_ck_n),
      .ddr3_ck_p                      (ddr3_ck_p),
      .ddr3_cke                       (ddr3_cke),
      .ddr3_ras_n                     (ddr3_ras_n),
      .ddr3_reset_n                   (ddr3_reset_n),
      .ddr3_we_n                      (ddr3_we_n),
      .ddr3_dq                        (ddr3_dq),
      .ddr3_dqs_n                     (ddr3_dqs_n),
      .ddr3_dqs_p                     (ddr3_dqs_p),
      .init_calib_complete            (init_calib_complete),
      
      .ddr3_cs_n                      (ddr3_cs_n),
      .ddr3_dm                        (ddr3_dm),
      .ddr3_odt                       (ddr3_odt),
      // Application interface ports
      .app_addr                       (app_addr),
      .app_cmd                        (app_cmd),
      .app_en                         (app_en),
      .app_wdf_data                   (app_wdf_data),
      .app_wdf_end                    (app_wdf_end),
      .app_wdf_wren                   (app_wdf_wren),
      .app_rd_data                    (app_rd_data),
      .app_rd_data_end                (app_rd_data_end),
      .app_rd_data_valid              (app_rd_data_valid),
      .app_rdy                        (app_rdy),
      .app_wdf_rdy                    (app_wdf_rdy),
      .app_sr_req                     (1'b0),
      .app_sr_active                  (),
      .app_ref_req                    (1'b0),
      .app_ref_ack                    (),
      .app_zq_req                     (1'b0),
      .app_zq_ack                     (),
      .ui_clk                         (ui_clk),
      .ui_clk_sync_rst                (ui_clk_sync_rst),
      
      .app_wdf_mask                   (app_wdf_mask),
      
      // System Clock Ports
      .sys_clk_i                      (sys_clk_i),
      //.clk_ref_i                      (clk_ref_i),
      .sys_rst                        (sys_rst)
      );

endmodule // ddr3_wrapper
