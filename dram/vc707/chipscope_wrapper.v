


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
   
endmodule
