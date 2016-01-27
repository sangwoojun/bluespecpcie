set_param general.maxThreads 8

# NOTE: typical usage would be "vivado -mode tcl -source create_mkPcieTop_batch.tcl" 
#
# STEP#0: define output directory area.
#
set pciedir ../../../../
set flashdir ../../../flash/

set outputDir ./hw
file mkdir $outputDir
#
# STEP#1: setup design sources and constraints
#
#source board.tcl

set partname {xc7vx485tffg1761-2}

read_verilog [ glob {verilog/top/*.v} ]

set_property part $partname [current_project]

############# Pcie Stuff
read_ip $pciedir/core/pcie_7x_0/pcie_7x_0.xci
read_verilog [ glob $pciedir/src/*.v ]
read_xdc $pciedir/src/xilinx_pcie_7x_ep_x8g2_VC707.xdc
############## end Pcie Stuff

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


# STEP#2: run synthesis, report utilization and timing estimates, write checkpoint design
#
synth_design -name mkProjectTop -top mkProjectTop -part $partname -flatten rebuilt

write_checkpoint -force $outputDir/mkprojecttop_post_synth
report_timing_summary -verbose  -file $outputDir/mkprojecttop_post_synth_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkprojecttop_post_synth_timing.rpt
report_utilization -verbose -file $outputDir/mkprojecttop_post_synth_utilization.txt
report_datasheet -file $outputDir/mkprojecttop_post_synth_datasheet.txt
write_verilog -force $outputDir/mkprojecttop_netlist.v
write_debug_probes -force probes.ltx
#report_power -file $outputDir/mkprojecttop_post_synth_power.rpt

#
# STEP#3: run placement and logic optimization, report utilization and timing estimates, write checkpoint design
#


opt_design
# power_opt_design
place_design
phys_opt_design
write_checkpoint -force $outputDir/mkprojecttop_post_place
report_timing_summary -file $outputDir/mkprojecttop_post_place_timing_summary.rpt
#
# STEP#4: run router, report actual utilization and timing, write checkpoint design, run drc, write verilog and xdc out
#
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
#
# STEP#5: generate a bitstream
# 
write_bitstream -force -bin_file $outputDir/mkProjectTop.bit
