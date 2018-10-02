#FIXME old stuff from KC705
create_clock -name ddr3_refclk -period 5 [get_pins sys_clk_200mhz_buf/O] 
#create_generated_clock -name ddr3_usrclk -source ddr3_refclk -multiply_by 5 -divide_by 5 [get_pins -hier -regexp { .*ddr3_ctrl/u_ddr3_0/ui_clk}]
create_generated_clock -name ddr3_usrclk -source [get_pins sys_clk_200mhz_buf/O] -multiply_by 5 -divide_by 5 [get_pins -hier -regexp { .*ddr3_ctrl/u_ddr3_0/ui_clk}]

set_clock_groups -asynchronous -group {pcie_clk_125mhz} -group {ddr3_usrclk}
set_clock_groups -asynchronous -group {pcie_clk_250mhz} -group {ddr3_usrclk}
set_clock_groups -asynchronous -group {pcie_clk_125mhz} -group {clk_pll_i}
set_clock_groups -asynchronous -group {pcie_clk_250mhz} -group {clk_pll_i}
set_clock_groups -asynchronous -group {userclk2} -group {clk_pll_i}
set_clock_groups -asynchronous -group {userclk2} -group {ddr3_usrclk}

set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME =~ *ddr3_ctrl_user_reset_n/*}] -hier -filter {NAME=~ *C}]
set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME =~ *ddr3_ctrl_user_reset_n/*}] -hier -filter {NAME=~ *C}]
set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME =~ *ddr3ref_rst_n/*}] -hier -filter {NAME=~ *CLR}]
set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME =~ *ddr_cli_200Mhz_reqs/*}] -hier -filter {NAME=~ *CLR}]

