open_hw
connect_hw_server
open_hw_target 
set fpga [lindex [get_hw_devices] 0] 

set file ./build/hw/mkProjectTop.bit
set_property PROGRAM.FILE $file $fpga
puts "fpga is $fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $fpga
