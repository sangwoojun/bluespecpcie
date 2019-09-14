set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Type1 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-1 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
set_property CONFIG_MODE BPI16 [current_design]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

set_property IOSTANDARD LVCMOS18 [get_ports led[0]]
set_property IOSTANDARD LVCMOS18 [get_ports led[1]]
set_property IOSTANDARD LVCMOS18 [get_ports led[2]]
set_property IOSTANDARD LVCMOS18 [get_ports led[3]]
set_property LOC AM39 [get_ports led[0]]
set_property LOC AN39 [get_ports led[1]]
set_property LOC AR37 [get_ports led[2]]
set_property LOC AT37 [get_ports led[3]]

set_property IOSTANDARD DIFF_SSTL15 [get_ports CLK_sys_clk_*]
set_property LOC E18 [get_ports CLK_sys_clk_n]
set_property LOC E19 [get_ports CLK_sys_clk_p]

set_property IOSTANDARD LVCMOS18 [get_ports CLK_emcclk]
#set_property LOC AP37 [get_ports CLK_emcclk]


###################################################### Base board stuff done

set_property LOC IBUFDS_GTE2_X1Y5 [get_cells -hier refclk_ibuf]

set_property IOSTANDARD DIFF_SSTL15 [get_ports CLK_pcie_clk_*]
set_property LOC AB7 [get_ports CLK_pcie_clk_n]
set_property LOC AB8 [get_ports CLK_pcie_clk_p]
create_clock -name pcie_clk -period 10 [get_pins -hier refclk_ibuf/O]

set_property IOSTANDARD LVCMOS18 [get_ports RST_N_pcie_rst_n]
set_property PULLUP true [get_ports RST_N_pcie_rst_n]
set_property LOC AV35 [get_ports RST_N_pcie_rst_n]
set_false_path -from [get_ports RST_N_pcie_rst_n]



#############################################################

create_clock -name sys_clk_200 -period 5 [get_pins sys_clk_200mhz_buf/O] 

create_generated_clock -name pcie_clk_125mhz [get_pins -hier -filter {NAME =~ *pcie_7x_0_support_i/pipe_clock_i/mmcm_i/CLKOUT0}]
create_generated_clock -name pcie_clk_250mhz [get_pins -hier -filter {NAME =~ *pcie_7x_0_support_i/pipe_clock_i/mmcm_i/CLKOUT1}]

create_generated_clock -name pcie_clk_125mhz_mux \ 
                        -source [get_pins -hier pclk_i1_bufgctrl.pclk_i1/I0] \
                        -divide_by 1 \
                        [get_pins -hier pclk_i1_bufgctrl.pclk_i1/O]
#
create_generated_clock -name pcie_clk_250mhz_mux \ 
                        -source [get_pins -hier pclk_i1_bufgctrl.pclk_i1/I1] \
                        -divide_by 1 -add -master_clock [get_clocks -of [get_pins -hier pclk_i1_bufgctrl.pclk_i1/I1]] \
                        [get_pins -hier pclk_i1_bufgctrl.pclk_i1/O]
#
set_clock_groups -name pcieclkmux -physically_exclusive -group clk_125mhz_mux -group clk_250mhz_mux





set_false_path -from [get_ports RST_N_sys_rst_n]

set_clock_groups -asynchronous -group {pcie_clk} -group {userclk2}
set_clock_groups -asynchronous -group {pcie_clk_125mhz} -group {userclk2}
set_clock_groups -asynchronous -group {pcie_clk_250mhz} -group {userclk2}

#set_false_path -to [get_pins -hier {pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S0}]
#set_false_path -to [get_pins -hier {pcie_7x_0_support_i/pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S1}]
set_false_path -to [get_pins -hier {pclk_i1_bufgctrl.pclk_i1/S0}]
set_false_path -to [get_pins -hier {pclk_i1_bufgctrl.pclk_i1/S1}]
#

#set_false_path -from [get_cells -hierarchical -regexp {NAME=~rst125*}]
#set_false_path -from [get_cells -hierarchical -regexp {NAME=~rst250*}]
#set_false_path -from [get_cells -hierarchical -regexp {NAME=~*pcie_7x_0_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_reset.pipe_reset_i/dclk_rst_reg*}]
#set_false_path -from [get_cells -hierarchical -regexp {NAME=~*pcie_7x_0_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_reset.pipe_reset_i/cpllreset_reg/C}]
#set_false_path -from [get_pins -hierarchical -filter {NAME=~*pcie_7x_0_i/inst/inst/user_reset_out_reg/C}]

set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/dEnqPtr*}] -filter {NAME =~ *CLR}]
set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/dNotEmptyReg*}] -filter {NAME =~ *CLR}]
set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/dGDeqPtr*}] -filter {NAME =~ *CLR}]
set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/dGDeqPtr*}] -filter {NAME =~ *PRE}]

set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/sSyncReg*}] -filter {NAME =~ *CLR}]
#set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/sSyncReg*}] -filter {NAME =~ *PRE}]

set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/dSyncReg*}] -filter {NAME =~ *CLR}]
#set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/dSyncReg*}] -filter {NAME =~ *PRE}]

set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/*}] -filter {NAME =~ *CLR}]
set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *ioRecvQ/*}] -filter {NAME =~ *PRE}]

#rst125/reset_hold_reg[7]_replica/C
set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME=~ *rst125/*}] -filter {NAME=~ *C}]
set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME=~ *rst200/*}] -filter {NAME=~ *C}]
set_false_path -from [get_pins -hier -filter {NAME =~ *pcie_7x_0_i/inst/inst/user_reset_out_*/C}]

###############################################################################
# End
###############################################################################


# PCIe Lane 0
set_property LOC GTXE2_CHANNEL_X1Y11 [get_cells -hierarchical -regexp {.*pipe_lane\[0\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 1
set_property LOC GTXE2_CHANNEL_X1Y10 [get_cells -hierarchical -regexp {.*pipe_lane\[1\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 2
set_property LOC GTXE2_CHANNEL_X1Y9 [get_cells -hierarchical -regexp {.*pipe_lane\[2\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 3
set_property LOC GTXE2_CHANNEL_X1Y8 [get_cells -hierarchical -regexp {.*pipe_lane\[3\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 4
set_property LOC GTXE2_CHANNEL_X1Y7 [get_cells -hierarchical -regexp {.*pipe_lane\[4\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 5
set_property LOC GTXE2_CHANNEL_X1Y6 [get_cells -hierarchical -regexp {.*pipe_lane\[5\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 6
set_property LOC GTXE2_CHANNEL_X1Y5 [get_cells -hierarchical -regexp {.*pipe_lane\[6\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]
# PCIe Lane 7
set_property LOC GTXE2_CHANNEL_X1Y4 [get_cells -hierarchical -regexp {.*pipe_lane\[7\].gt_wrapper_i/gtx_channel.gtxe2_channel_i}]

set_property LOC PCIE_X1Y0 [get_cells -hierarchical -regexp {.*pcie_7x_i/pcie_block_i}]

set_property LOC Y4   [get_ports { pcie_pins_rxp_i[0] }]
set_property LOC AA6  [get_ports { pcie_pins_rxp_i[1] }]
set_property LOC AB4  [get_ports { pcie_pins_rxp_i[2] }]
set_property LOC AC6  [get_ports { pcie_pins_rxp_i[3] }]
set_property LOC AD4  [get_ports { pcie_pins_rxp_i[4] }]
set_property LOC AE6  [get_ports { pcie_pins_rxp_i[5] }]
set_property LOC AF4  [get_ports { pcie_pins_rxp_i[6] }]
set_property LOC AG6  [get_ports { pcie_pins_rxp_i[7] }]

set_property LOC Y3   [get_ports { pcie_pins_rxn_i[0] }]
set_property LOC AA5  [get_ports { pcie_pins_rxn_i[1] }]
set_property LOC AB3  [get_ports { pcie_pins_rxn_i[2] }]
set_property LOC AC5  [get_ports { pcie_pins_rxn_i[3] }]
set_property LOC AD3  [get_ports { pcie_pins_rxn_i[4] }]
set_property LOC AE5  [get_ports { pcie_pins_rxn_i[5] }]
set_property LOC AF3  [get_ports { pcie_pins_rxn_i[6] }]
set_property LOC AG5  [get_ports { pcie_pins_rxn_i[7] }]

set_property LOC W2   [get_ports { pcie_pins_TXP[0] }]
set_property LOC AA2  [get_ports { pcie_pins_TXP[1] }]
set_property LOC AC2  [get_ports { pcie_pins_TXP[2] }]
set_property LOC AE2  [get_ports { pcie_pins_TXP[3] }]
set_property LOC AG2  [get_ports { pcie_pins_TXP[4] }]
set_property LOC AH4  [get_ports { pcie_pins_TXP[5] }]
set_property LOC AJ2  [get_ports { pcie_pins_TXP[6] }]
set_property LOC AK4  [get_ports { pcie_pins_TXP[7] }]

set_property LOC W1   [get_ports { pcie_pins_TXN[0] }]
set_property LOC AA1  [get_ports { pcie_pins_TXN[1] }]
set_property LOC AC1  [get_ports { pcie_pins_TXN[2] }]
set_property LOC AE1  [get_ports { pcie_pins_TXN[3] }]
set_property LOC AG1  [get_ports { pcie_pins_TXN[4] }]
set_property LOC AH3  [get_ports { pcie_pins_TXN[5] }]
set_property LOC AJ1  [get_ports { pcie_pins_TXN[6] }]
set_property LOC AK3  [get_ports { pcie_pins_TXN[7] }]
