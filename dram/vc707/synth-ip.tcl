set coredir "./core/"
set corename "ddr3_0"

file mkdir $coredir
if [file exists ./$coredir/$corename] {
	file delete -force ./$coredir/$corename
}

create_project -name local_synthesized_ip -in_memory -part xc7vx485tffg1761-2
set_property board_part xilinx.com:vc707:part0:1.0 [current_project]
create_ip -name mig_7series -version 4.* -vendor xilinx.com -library ip -module_name $corename -dir ./$coredir

set_property -dict [list CONFIG.XML_INPUT_FILE "../../mig_a.prj" CONFIG.RESET_BOARD_INTERFACE {Custom} CONFIG.MIG_DONT_TOUCH_PARAM {Custom} CONFIG.BOARD_MIG_PARAM {Custom}] [get_ips $corename]

generate_target {instantiation_template} [get_files ./$coredir/$corename/$corename.xci]
generate_target all [get_files  ./$coredir/$corename/$corename.xci]
create_ip_run [get_files -of_objects [get_fileset sources_1] ./$coredir/$corename/$corename.xci]
generate_target {Synthesis} [get_files  ./$coredir/$corename/$corename.xci]
read_ip ./$coredir/$corename/$corename.xci
synth_ip [get_ips $corename]
