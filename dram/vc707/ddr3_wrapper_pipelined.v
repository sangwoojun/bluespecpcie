
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
  
      input [27:0]   app_addr,
      input [2:0]    app_cmd,
      input          app_en,
      input [511:0]  app_wdf_data,
      input          app_wdf_end,
      input [63:0]   app_wdf_mask,
      input          app_wdf_wren,
      output [511:0] app_rd_data,
      output         app_rd_data_end,
      output         app_rd_data_valid,
      output         app_rdy,
      output         app_wdf_rdy,
      input          app_sr_req,
      input          app_ref_req,
      input          app_zq_req,
      output         app_sr_active,
      output         app_ref_ack,
      output         app_zq_ack,
      output         ui_clk,
      output         ui_clk_sync_rst,
      output         init_calib_complete,
      input          sys_rst
    );

   assign ui_clk = ui_clk_internal;
   wire                ui_clk_internal;
   
   reg [27:0]        app_addr_reg;
   reg [2:0]         app_cmd_reg;
   reg               app_en_reg;
   reg [511:0]       app_wdf_data_reg;
   reg               app_wdf_end_reg;
   reg [63:0]        app_wdf_mask_reg;
   reg               app_wdf_wren_reg;
   reg [511:0]       app_rd_data_reg;
   reg               app_rd_data_end_reg;
   reg               app_rd_data_valid_reg;
   reg               app_rdy_reg;
   reg               app_wdf_rdy_reg;

   always @  (posedge ui_clk_internal)  begin
      app_addr_reg <= app_addr;
      app_cmd_reg <= app_cmd;
      app_en_reg <= app_en;
      app_wdf_data_reg <= app_wdf_data;
      app_wdf_end_reg <= app_wdf_end;
      app_wdf_mask_reg <= app_wdf_mask;
      app_wdf_wren_reg <= app_wdf_wren;
      
      app_rd_data_reg <= app_rd_data_wire;
      app_rd_data_end_reg <= app_rd_data_end_wire;
      app_rd_data_valid_reg <= app_rd_data_valid_wire;
      app_rdy_reg <= app_rdy_wire;
      app_wdf_rdy_reg <= app_wdf_rdy_wire;
   end

                   
//   assign app_rd_data =
   
   wire  [511:0] app_rd_data_wire;
   wire          app_rd_data_end_wire;
   wire          app_rd_data_valid_wire;
   wire          app_rdy_wire;
   wire          app_wdf_rdy_wire;

   assign app_rd_data = app_rd_data_reg;
   assign app_rd_data_end = app_rd_data_end_reg;
   assign app_rd_data_valid = app_rd_data_valid_reg;
   assign app_rdy = app_rdy_reg;
   assign app_wdf_rdy = app_wdf_rdy_reg;

   
   ddr3_v2_0 u_ddr3_v2_0
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
      .app_addr                       (app_addr_reg),
      .app_cmd                        (app_cmd_reg),
      .app_en                         (app_en_reg),
      .app_wdf_data                   (app_wdf_data_reg),
      .app_wdf_end                    (app_wdf_end_reg),
      .app_wdf_wren                   (app_wdf_wren_reg),
      .app_rd_data                    (app_rd_data_wire),
      .app_rd_data_end                (app_rd_data_end_wire),
      .app_rd_data_valid              (app_rd_data_valid_wire),
      .app_rdy                        (app_rdy_wire),
      .app_wdf_rdy                    (app_wdf_rdy_wire),
      .app_sr_req                     (1'b0),
      .app_sr_active                  (),
      .app_ref_req                    (1'b0),
      .app_ref_ack                    (),
      .app_zq_req                     (1'b0),
      .app_zq_ack                     (),
      .ui_clk                         (ui_clk_internal),
      .ui_clk_sync_rst                (ui_clk_sync_rst),
      
      .app_wdf_mask                   (app_wdf_mask_reg),
      
      // System Clock Ports
      .sys_clk_i                      (sys_clk_i),
      //.clk_ref_i                      (clk_ref_i),
      .sys_rst                        (sys_rst)
      );

endmodule // ddr3_wrapper
