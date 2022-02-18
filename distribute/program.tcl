open_hw_manager
connect_hw_server
set hwtargets [get_hw_targets]

if { $::argc > 1 } {
	open_hw_target [lindex [get_hw_targets] [lindex $argv 1] ]
} else {
	open_hw_target [lindex [get_hw_targets] 0]
}

if { $::argc > 0 } {
	set file [lindex $argv 0]
} else {
	set file ./vc707/hw/mkProjectTop.bit
}

foreach fpga [get_hw_devices] {
	if {[string first "xc7vx485t" $fpga] != -1} {
		puts "fpga is $fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
		
		set_property PROGRAM.FILE $file $fpga
		program_hw_devices -verbose $fpga
		refresh_hw_device $fpga
		break
	}
}


