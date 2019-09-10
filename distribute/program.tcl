open_hw
connect_hw_server
open_hw_target 
set fpga [lindex [get_hw_devices] 2] 

if { $::argc > 0 } {
	set file [lindex $argv 0]
} else {
	set file ./vc707/hw/mkProjectTop.bit
}

set_property PROGRAM.FILE $file $fpga
puts "fpga is $fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices -verbose $fpga
refresh_hw_device $fpga
