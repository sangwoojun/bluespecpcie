#proc core_gen_pcie {} {
	set coredir "./"
	set corename "pcie_7x_0"

	file mkdir $coredir
	if [file exists ./$coredir/$corename] {
		file delete -force ./$coredir/$corename
	}

	create_project -name local_synthesized_ip -in_memory -part xc7k325tffg900-2
	set_property board_part xilinx.com:kc705:part0:1.5 [current_project]
	create_ip -name pcie_7x -vendor xilinx.com -library ip -version 3.* -module_name $corename -dir ./$coredir
set_property -dict [list CONFIG.Maximum_Link_Width {X8} CONFIG.Interface_Width {128_bit} CONFIG.Bar0_Scale {Megabytes} CONFIG.Bar0_Size {1} CONFIG.Link_Speed {2.5_GT/s} CONFIG.User_Clk_Freq {125} CONFIG.Device_ID {7028} CONFIG.Max_Payload_Size {512_bytes} CONFIG.Trgt_Link_Speed {4'h1} CONFIG.PCIe_Blk_Locn {X0Y0} CONFIG.Trans_Buf_Pipeline {None} CONFIG.Ref_Clk_Freq {100_MHz}] [get_ips $corename]

	generate_target {instantiation_template} [get_files ./$coredir/$corename/$corename.xci]
	generate_target all [get_files  ./$coredir/$corename/$corename.xci]
	create_ip_run [get_files -of_objects [get_fileset sources_1] ./$coredir/$corename/$corename.xci]
	generate_target {Synthesis} [get_files  ./$coredir/$corename/$corename.xci]
	read_ip ./$coredir/$corename/$corename.xci
	synth_ip [get_ips $corename]
#}
#core_gen_pcie









