set_param general.maxThreads 8

set pciedir ../../../
set ddr3dir ../../../dram/vc707/

set outputDir ./hw
file mkdir $outputDir
#source board.tcl

set partname {xc7vx485tffg1761-2}

read_verilog [ glob {verilog/top/*.v} ]

set_property part $partname [current_project]

############# Pcie Stuff
read_ip $pciedir/core/vc707/pcie_7x_0/pcie_7x_0.xci
read_verilog [ glob $pciedir/src/*.v ]
read_xdc $pciedir/src/xilinx_pcie_7x_ep_x8g2_VC707.xdc
############## end Pcie Stuff

############# DDR3 Stuff
read_ip $ddr3dir/core/ddr3_0/ddr3_0.xci
read_verilog [ glob $ddr3dir/*.v ]
read_xdc $ddr3dir/dram.xdc
############# end Flash Stuff

############# Flash Stuff
#read_ip $flashdir/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
#read_verilog [ glob $flashdir/xilinx/*.v ]
#read_xdc $flashdir/xilinx/aurora_8b10b_fmc1_exdes.xdc
############# end Flash Stuff


#generate_target {Synthesis} [get_files ../../xilinx/vio_7series/vio_7series.xci]
#read_ip ../../xilinx/vio_7series/vio_7series.xci
#
#generate_target {Synthesis} [get_files ../../xilinx/ila_7series/ila_7series.xci]
#read_ip ../../xilinx/ila_7series/ila_7series.xci
#
#read_verilog [ glob {../../xilinx/nullreset/*.v} ]

#read_xdc {../../xilinx/constraints/ac701.xdc}


synth_design -name mkProjectTop -top mkProjectTop -part $partname -flatten rebuilt

write_checkpoint -force $outputDir/mkprojecttop_post_synth
report_timing_summary -verbose  -file $outputDir/mkprojecttop_post_synth_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkprojecttop_post_synth_timing.rpt
report_utilization -verbose -file $outputDir/mkprojecttop_post_synth_utilization.txt
report_datasheet -file $outputDir/mkprojecttop_post_synth_datasheet.txt
write_verilog -force $outputDir/mkprojecttop_netlist.v
write_debug_probes -force probes.ltx
#report_power -file $outputDir/mkprojecttop_post_synth_power.rpt


opt_design
# power_opt_design
place_design
phys_opt_design
write_checkpoint -force $outputDir/mkprojecttop_post_place
report_timing_summary -file $outputDir/mkprojecttop_post_place_timing_summary.rpt
route_design
write_checkpoint -force $outputDir/mkprojecttop_post_route
report_timing_summary -file $outputDir/mkprojecttop_post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkprojecttop_post_route_timing.rpt
report_clock_utilization -file $outputDir/mkprojecttop_clock_util.rpt
report_utilization -file $outputDir/mkprojecttop_post_route_util.rpt
report_datasheet -file $outputDir/mkprojecttop_post_route_datasheet.rpt
#report_power -file $outputDir/mkprojecttop_post_route_power.rpt
#report_drc -file $outputDir/mkprojecttop_post_imp_drc.rpt
#write_verilog -force $outputDir/mkprojecttop_impl_netlist.v
write_xdc -no_fixed_only -force $outputDir/mkprojecttop_impl.xdc
write_bitstream -force -bin_file $outputDir/mkProjectTop.bit
