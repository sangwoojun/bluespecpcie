package PcieImport;

typedef 128 PcieInterfaceSz;
typedef TDiv#(PcieInterfaceSz, 8) PcieKeepSz;

(* always_enabled, always_ready *)
interface PcieImportPins;
	(* prefix = "", result = "RXN" *)
	method Action rxn_in(Bit#(8) rxn_i);
	(* prefix = "", result = "RXP" *)
	method Action rxp_in(Bit#(8) rxp_i);

	(* prefix = "", result = "TXN" *)
	method Bit#(8) txn_out();
	(* prefix = "", result = "TXP" *)
	method Bit#(8) txp_out();

endinterface

interface PcieImportUser;
	method Bit#(1) user_link_up;
	method Bit#(16) cfg_completer_id;

	method Bit#(32) debug_data;
	
	method Action assertInterrupt(Bit#(1) value);
	method Action assertUptrain(Bit#(1) value);

	method Action sendData(Bit#(PcieInterfaceSz) word);
	method Action sendKeep(Bit#(PcieKeepSz) keep);
	method Action sendLast(Bit#(1) last);

	method ActionValue#(Bit#(PcieInterfaceSz)) receiveData;
	method ActionValue#(Bit#(PcieKeepSz)) receiveKeep;
	method ActionValue#(Bit#(1)) receiveLast;
	method ActionValue#(Bit#(22)) receiveUser;
endinterface

interface PcieImportIfc;
	interface Clock sys_clk_o;
	interface Reset sys_rst_n_o;
	interface Clock user_clk;
	interface Reset user_reset;
	interface PcieImportPins pins;
	interface PcieImportUser user;
endinterface

import "BVI" xilinx_pcie_2_1_ep_7x =
module mkPcieImport#(Clock sys_clk_p, Clock sys_clk_n, Reset sys_rst_n, Clock emcclk) (PcieImportIfc);

	default_clock no_clock;
	default_reset no_reset;

	input_clock (sys_clk_p) = sys_clk_p;
	input_clock (sys_clk_n) = sys_clk_n;

	input_reset (sys_rst_n) = sys_rst_n;
	input_clock (emcclk) = emcclk;

	output_clock sys_clk_o(sys_clk_o);
	output_reset sys_rst_n_o(sys_rst_n_o);
	output_clock user_clk(user_clk);
	output_reset user_reset(user_reset_n) clocked_by(user_clk);

	interface PcieImportPins pins;
		method rxn_in(pci_exp_rxn) enable((*inhigh*) rx_n_en_0) reset_by(no_reset) clocked_by(sys_clk_n);
		method rxp_in(pci_exp_rxp) enable((*inhigh*) rx_p_en_0) reset_by(no_reset) clocked_by(sys_clk_p);
		method pci_exp_txn txn_out() reset_by(no_reset) clocked_by(sys_clk_n); 
		method pci_exp_txp txp_out() reset_by(no_reset) clocked_by(sys_clk_p);
	endinterface

	interface PcieImportUser user;
		method user_lnk_up user_link_up;
		method cfg_completer_id cfg_completer_id;

		method debug_data debug_data;

		method assertInterrupt(assert_interrupt_data) enable(assert_interrupt) ready(assert_interrupt_rdy) clocked_by(user_clk) reset_by(user_reset);
		method assertUptrain(asser_uptrain_data) enable(assert_uptrain) ready(assert_interrupt_rdy) clocked_by(user_clk) reset_by(user_reset);

		method sendData(s_axis_tx_tdata) enable(s_axis_tx_tvalid) ready(s_axis_tx_tready) clocked_by(user_clk) reset_by(user_reset);
		method sendKeep(s_axis_tx_tkeep) enable(tx_en_keep) ready(s_axis_tx_tready) clocked_by(user_clk) reset_by(user_reset);
		method sendLast(s_axis_tx_tlast) enable(tx_en_last) ready(s_axis_tx_tready) clocked_by(user_clk) reset_by(user_reset);

		method m_axis_rx_tdata receiveData enable(m_axis_rx_tready) ready(m_axis_rx_tvalid) clocked_by(user_clk) reset_by(user_reset);
		method m_axis_rx_tkeep receiveKeep enable(rx_en_keep) ready(m_axis_rx_tvalid) clocked_by(user_clk) reset_by(user_reset);
		method m_axis_rx_tlast receiveLast enable(rx_en_last) ready(m_axis_rx_tvalid) clocked_by(user_clk) reset_by(user_reset);
		method m_axis_rx_tuser receiveUser enable(rx_en_user) ready(m_axis_rx_tvalid) clocked_by(user_clk) reset_by(user_reset);
	endinterface

	schedule (
		pins_rxn_in, pins_rxp_in, pins_txn_out, pins_txp_out
		) CF (
		pins_rxn_in, pins_rxp_in, pins_txn_out, pins_txp_out
		);

	schedule (
		user_receiveData, user_receiveKeep, user_receiveLast, user_receiveUser,
		user_cfg_completer_id,
		user_assertInterrupt,
		user_sendData, user_sendKeep, user_sendLast, user_user_link_up,
		user_debug_data, user_assertUptrain


		) CF (
		user_receiveData, user_receiveKeep, user_receiveLast, user_receiveUser,
		user_cfg_completer_id,
		user_assertInterrupt,
		user_sendData, user_sendKeep, user_sendLast, user_user_link_up,
		user_debug_data, user_assertUptrain
		);
endmodule

endpackage: PcieImport
