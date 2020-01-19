set_param general.maxThreads 8

set boardname kc705

set pciedir ../../../

if { $::argc > 0 } {
	set pciedir [lindex $argv 0]
	puts $pciedir
} else {
	puts "using default pcie core path"
	
}

set outputDir ./hw
file mkdir $outputDir

set partname {xc7k325tffg900-2}

read_verilog [ glob {verilog/top/*.v} ]

set_property part $partname [current_project]

############# Pcie Stuff
read_ip $pciedir/core/kc705/pcie_7x_0/pcie_7x_0.xci
read_verilog [ glob $pciedir/src/*.v ]
read_xdc $pciedir/src/xilinx_pcie_7x_ep_x8g2_KC705.xdc
############## end Pcie Stuff

if { [file exists "user-ip.tcl"] == 1} {
	source user-ip.tcl
}


synth_design -name mkProjectTop -top mkProjectTop -part $partname -flatten rebuilt

write_checkpoint -force $outputDir/mkprojecttop_post_synth
report_timing_summary -verbose  -file $outputDir/mkprojecttop_post_synth_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkprojecttop_post_synth_timing.rpt
report_utilization -verbose -file $outputDir/mkprojecttop_post_synth_utilization.txt
report_utilization -hierarchical  -file $outputDir/mkprojecttop_post_synth_util_hier.rpt
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
