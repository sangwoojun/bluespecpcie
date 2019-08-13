set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Type2 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-2 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
set_property CONFIG_MODE BPI16 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 2.5 [current_design]

set_property IOSTANDARD LVCMOS15 [get_ports led[0]]
set_property IOSTANDARD LVCMOS15 [get_ports led[1]]
set_property IOSTANDARD LVCMOS15 [get_ports led[2]]
set_property IOSTANDARD LVCMOS15 [get_ports led[3]]
set_property LOC AB8 [get_ports led[0]]
set_property LOC AA8 [get_ports led[1]]
set_property LOC AC9 [get_ports led[2]]
set_property LOC AB9 [get_ports led[3]]

set_property IOSTANDARD DIFF_SSTL15 [get_ports { CLK_sys_clk_* }]
set_property LOC AD12 [get_ports { CLK_sys_clk_p }]
set_property LOC AD11 [get_ports { CLK_sys_clk_n }]


set_property IOSTANDARD LVCMOS25 [get_ports CLK_emcclk]
set_property PACKAGE_PIN AP37 [get_ports FPGA_EMCCLK]
set_property IOSTANDARD LVCMOS18 [get_ports FPGA_EMCCLK]

###################################################### Base board stuff done


set_property LOC IBUFDS_GTE2_X0Y1 [get_cells {pcie/refclk_ibuf}]

#set_property IOSTANDARD DIFF_SSTL15 [get_ports { CLK_pcie_clk_* }] # why?
#actually PCIE_CLK_QO_N
set_property LOC U7 [get_ports CLK_pcie_clk_n] 
set_property LOC U8 [get_ports CLK_pcie_clk_p]
create_clock -name pcie_clk -period 10 [get_pins -hier refclk_ibuf/O]

set_property IOSTANDARD LVCMOS25 [get_ports RST_N_pcie_rst_n]
set_property PULLUP true [get_ports RST_N_pcie_rst_n]
set_property LOC G25 [get_ports RST_N_pcie_rst_n]
set_false_path -from [get_ports RST_N_pcie_rst_n]

#create_clock -name sys_clk -period 5 [get_ports CLK_sys_clk_p]

#############################################################

create_clock -name sys_clk_200 -period 5 [get_pins sys_clk_200mhz_buf/O] 


#set_case_analysis 1 [get_pins -hier {pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S0}]
#set_case_analysis 0 [get_pins -hier {pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S1}]
set_property DONT_TOUCH true [get_cells -of [get_nets -of [get_pins -hier -regexp { .*pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S0}]]]



create_generated_clock -name pcie_clk_125mhz [get_pins -hierarchical -regexp {.*pcie_7x_0_support_i/pipe_clock_i/mmcm_i/CLKOUT0}]
create_generated_clock -name pcie_clk_250mhz [get_pins -hier -regexp {.*pcie_7x_0_support_i/pipe_clock_i/mmcm_i/CLKOUT1}]
create_generated_clock -name pcie_clk_125mhz_mux \ 
-source [get_pins -hier -regexp {.*pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/I0}] \
		-divide_by 1 \
		[get_pins -hier -regexp {.*pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/O}]
#
create_generated_clock -name pcie_clk_250mhz_mux \ 
-source [get_pins -hier -regexp { .*pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/I1}] \
	-divide_by 1 -add -master_clock [get_clocks -of [get_pins -hier -regexp { .*pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/I1}]] \
	[get_pins -hier -regexp { .*pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/O}]
#
set_clock_groups -name pcieclkmux -physically_exclusive -group pcie_clk_125mhz_mux -group pcie_clk_250mhz_mux



#set_property LOC PCIE_X0Y3 [get_cells -hierarchical -regexp {.*pcie_top_i/pcie_7x_i/pcie_block_i}]
#Why is it X0Y3?
#set_property LOC PCIE_X0Y0 [get_cells -hierarchical -regexp {.*pcie_top_i/pcie_7x_i/pcie_block_i}]

#set_property LOC RAMB36_X4Y34 [get_cells -hier {pcie_7x_0pcie_7x_0_core_top/pcie_top_i/pcie_7x_i/pcie_bram_top/pcie_brams_rx/brams[0].ram/use_sdp.ramb36sdp/genblk*.bram36_dp_bl.bram36_tdp_bl}]
#set_property LOC RAMB36_X4Y33 [get_cells -hier {pcie_7x_0pcie_7x_0_core_top/pcie_top_i/pcie_7x_i/pcie_bram_top/pcie_brams_rx/brams[1].ram/use_sdp.ramb36sdp/genblk*.bram36_dp_bl.bram36_tdp_bl}]
#set_property LOC RAMB36_X4Y31 [get_cells -hier {pcie_7x_0pcie_7x_0_core_top/pcie_top_i/pcie_7x_i/pcie_bram_top/pcie_brams_tx/brams[0].ram/use_sdp.ramb36sdp/genblk*.bram36_dp_bl.bram36_tdp_bl}]
#set_property LOC RAMB36_X4Y30 [get_cells -hier {pcie_7x_0pcie_7x_0_core_top/pcie_top_i/pcie_7x_i/pcie_bram_top/pcie_brams_tx/brams[1].ram/use_sdp.ramb36sdp/genblk*.bram36_dp_bl.bram36_tdp_bl}]

set_max_delay -from [get_clocks {userclk2}] -to   [get_clocks {sys_clk}] 4.0 -datapath_only
set_max_delay -to   [get_clocks {userclk2}] -from [get_clocks {sys_clk}] 4.0 -datapath_only

set_clock_groups -asynchronous -group {sys_clk} -group {userclk2}
set_clock_groups -asynchronous -group {pcie_clk_125mhz} -group {userclk2}
set_clock_groups -asynchronous -group {pcie_clk_250mhz} -group {userclk2}

#set_false_path -to [get_pins {pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S0}]
#set_false_path -to [get_pins {pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S1}]
set_false_path -to [get_pins -hier {pclk_i1_bufgctrl.pclk_i1/S0}]
set_false_path -to [get_pins -hier {pclk_i1_bufgctrl.pclk_i1/S1}]

###############################################################################
# End
###############################################################################



# PCIe Lane 0
set_property LOC GTXE2_CHANNEL_X0Y7 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[0\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 1
set_property LOC GTXE2_CHANNEL_X0Y6 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[1\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 2
set_property LOC GTXE2_CHANNEL_X0Y5 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[2\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 3
set_property LOC GTXE2_CHANNEL_X0Y4 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[3\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 4
set_property LOC GTXE2_CHANNEL_X0Y3 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[4\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 5
set_property LOC GTXE2_CHANNEL_X0Y2 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[5\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 6
set_property LOC GTXE2_CHANNEL_X0Y1 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[6\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 7
set_property LOC GTXE2_CHANNEL_X0Y0 [get_cells -hierarchical -regexp {.*gt_top_i/pipe_wrapper_i/pipe_lane\[7\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]

set_property PACKAGE_PIN M5 [get_ports {pcie_pins_rxn_i[0]}]
set_property PACKAGE_PIN M6 [get_ports {pcie_pins_rxp_i[0]}]
set_property PACKAGE_PIN P5 [get_ports {pcie_pins_rxn_i[1]}]
set_property PACKAGE_PIN P6 [get_ports {pcie_pins_rxp_i[1]}]
set_property PACKAGE_PIN R3 [get_ports {pcie_pins_rxn_i[2]}]
set_property PACKAGE_PIN R4 [get_ports {pcie_pins_rxp_i[2]}]
set_property PACKAGE_PIN T5 [get_ports {pcie_pins_rxn_i[3]}]
set_property PACKAGE_PIN T6 [get_ports {pcie_pins_rxp_i[3]}]
set_property PACKAGE_PIN V5 [get_ports {pcie_pins_rxn_i[4]}]
set_property PACKAGE_PIN V6 [get_ports {pcie_pins_rxp_i[4]}]
set_property PACKAGE_PIN W3 [get_ports {pcie_pins_rxn_i[5]}]
set_property PACKAGE_PIN W4 [get_ports {pcie_pins_rxp_i[5]}]
set_property PACKAGE_PIN Y5 [get_ports {pcie_pins_rxn_i[6]}]
set_property PACKAGE_PIN Y6 [get_ports {pcie_pins_rxp_i[6]}]
set_property PACKAGE_PIN AA3 [get_ports {pcie_pins_rxn_i[7]}]
set_property PACKAGE_PIN AA4 [get_ports {pcie_pins_rxp_i[7]}]
set_property PACKAGE_PIN L3 [get_ports {pcie_pins_TXN[0]}]
set_property PACKAGE_PIN L4 [get_ports {pcie_pins_TXP[0]}]
set_property PACKAGE_PIN M1 [get_ports {pcie_pins_TXN[1]}]
set_property PACKAGE_PIN M2 [get_ports {pcie_pins_TXP[1]}]
set_property PACKAGE_PIN N3 [get_ports {pcie_pins_TXN[2]}]
set_property PACKAGE_PIN N4 [get_ports {pcie_pins_TXP[2]}]
set_property PACKAGE_PIN P1 [get_ports {pcie_pins_TXN[3]}]
set_property PACKAGE_PIN P2 [get_ports {pcie_pins_TXP[3]}]
set_property PACKAGE_PIN T1 [get_ports {pcie_pins_TXN[4]}]
set_property PACKAGE_PIN T2 [get_ports {pcie_pins_TXP[4]}]
set_property PACKAGE_PIN U3 [get_ports {pcie_pins_TXN[5]}]
set_property PACKAGE_PIN U4 [get_ports {pcie_pins_TXP[5]}]
set_property PACKAGE_PIN V1 [get_ports {pcie_pins_TXN[6]}]
set_property PACKAGE_PIN V2 [get_ports {pcie_pins_TXP[6]}]
set_property PACKAGE_PIN Y1 [get_ports {pcie_pins_TXN[7]}]
set_property PACKAGE_PIN Y2 [get_ports {pcie_pins_TXP[7]}]

