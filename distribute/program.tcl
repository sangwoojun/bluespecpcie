connect_hw_server
open_hw_target 
set vc707fpga [lindex [get_hw_devices] 2] 

set file ./build/hw/mkProjectTop.bit
set_property PROGRAM.FILE $file $vc707fpga
puts "fpga is $vc707fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $vc707fpga
