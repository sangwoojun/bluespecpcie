##create_clock -name ddr3_refclk -period 5 [get_pins host_sys_clk_200mhz_buf/O]
#create_generated_clock -name ddr3_usrclk -source clk_gen_pll_CLKOUT2 -multiply_by 5 -divide_by 5 [get_pins *ddr3_ctrl/CLK]
#create_generated_clock -name app_clk -source [get_pins */clkgen_pll/CLKIN1] -divide_by 2 [get_pins */clkgen_pll/CLKOUT0]

#set_max_delay -from [get_clocks app_clk] -to [get_clocks ddr3_usrclk] 5.000 -datapath_only
#set_max_delay -from [get_clocks ddr3_usrclk] -to [get_clocks app_clk] 5.000 -datapath_only
