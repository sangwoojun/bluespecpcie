#proc core_gen_pcie {} {
	set coredir "./"
	set corename "pcie_7x_0"

	file mkdir $coredir
	if [file exists ./$coredir/$corename] {
		file delete -force ./$coredir/$corename
	}

	create_project -name local_synthesized_ip -in_memory -part xc7vx485tffg1761-2
	set_property board_part xilinx.com:vc707:part0:1.0 [current_project]
	create_ip -name pcie_7x -version 3.* -vendor xilinx.com -library ip -module_name $corename -dir ./$coredir
	#set_property -dict [list CONFIG.Maximum_Link_Width {X8} CONFIG.Link_Speed {5.0_GT/s} CONFIG.Bar0_Scale {Megabytes} CONFIG.Bar0_Size {1} CONFIG.Bar1_Enabled {false} CONFIG.Use_Class_Code_Lookup_Assistant {false} CONFIG.Xlnx_Ref_Board {VC707}] [get_ips $corename]
	set_property -dict [list CONFIG.Maximum_Link_Width {X8} CONFIG.Link_Speed {5.0_GT/s} CONFIG.Bar0_Scale {Megabytes} CONFIG.Bar0_Size {1} CONFIG.Base_Class_Menu {Memory_controller} CONFIG.Use_Class_Code_Lookup_Assistant {true} CONFIG.Xlnx_Ref_Board {VC707} CONFIG.Ref_Clk_Freq {100_MHz} CONFIG.Max_Payload_Size {256_bytes}] [get_ips $corename]

	generate_target {instantiation_template} [get_files ./$coredir/$corename/$corename.xci]
	generate_target all [get_files  ./$coredir/$corename/$corename.xci]
	create_ip_run [get_files -of_objects [get_fileset sources_1] ./$coredir/$corename/$corename.xci]
	generate_target {Synthesis} [get_files  ./$coredir/$corename/$corename.xci]
	read_ip ./$coredir/$corename/$corename.xci
	synth_ip [get_ips $corename]
#}
#core_gen_pcie
