////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2013  Bluespec, Inc.  ALL RIGHTS RESERVED.
////////////////////////////////////////////////////////////////////////////////
//  Filename      : DDR3.bsv
//  Description   : 
////////////////////////////////////////////////////////////////////////////////
package DDR3Common;

// Notes :

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Clocks            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import TriState          ::*;
import DefaultValue      ::*;
import Counter           ::*;
import CommitIfc         ::*;
import Memory            ::*;
import GetPut            ::*;
import ClientServer      ::*;
import BUtils            ::*;
//import I2C               ::*;
import Connectable       ::*;

//import Cntrs::*;

////////////////////////////////////////////////////////////////////////////////
/// Exports
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
/// Types
////////////////////////////////////////////////////////////////////////////////
typedef struct {
   Bool        simulation;
   Integer     reads_in_flight;
} DDR3_Configure;

instance DefaultValue#(DDR3_Configure);
   defaultValue = DDR3_Configure {
      simulation:       False,
      reads_in_flight:  8
      };
endinstance

typedef struct {
   Bit#(bewidth)    byteen;
   Bit#(addrwidth)  address;
   Bit#(datawidth)  data;
} DDR3Request#(numeric type addrwidth, numeric type datawidth, numeric type bewidth) deriving (Bits, Eq);

typedef struct {
   Bit#(datawidth)  data;
} DDR3Response#(numeric type datawidth) deriving (Bits, Eq);		

`define DDR3_PRM_DCL numeric type ddr3addrsize,\
                     numeric type ddr3datasize,\
                     numeric type ddr3besize,\
                     numeric type datawidth,\
                     numeric type bewidth,\
                     numeric type rowwidth,\
		     numeric type colwidth,\
		     numeric type bankwidth,\
		     numeric type rankwidth,\
		     numeric type clkwidth,\
		     numeric type cswidth,\
		     numeric type ckewidth,\
		     numeric type odtwidth,\
		     numeric type clkratio

`define DDR3_PRM     ddr3addrsize,\
                     ddr3datasize,\
                     ddr3besize,\
                     datawidth,\
                     bewidth,\
                     rowwidth,\
		     colwidth,\
		     bankwidth,\
		     rankwidth,\
		     clkwidth,\
		     cswidth,\
		     ckewidth,\
		     odtwidth,\
		     clkratio

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////
(* always_enabled, always_ready *)
interface DDR3_Pins#(`DDR3_PRM_DCL);
   (* prefix = "", result = "CLK_P" *)
   method    Bit#(clkwidth)           clk_p;
   (* prefix = "", result = "CLK_N" *)
   method    Bit#(clkwidth)           clk_n;
   (* prefix = "", result = "A" *)
   method    Bit#(rowwidth)           a;
   (* prefix = "", result = "BA" *)
   method    Bit#(bankwidth)          ba;
   (* prefix = "", result = "RAS_N" *)
   method    Bit#(1)                  ras_n;
   (* prefix = "", result = "CAS_N" *)
   method    Bit#(1)                  cas_n;
   (* prefix = "", result = "WE_N" *)
   method    Bit#(1)                  we_n;
   (* prefix = "", result = "RESET_N" *)
   method    Bit#(1)                  reset_n;
   (* prefix = "", result = "CS_N" *)
   method    Bit#(cswidth)            cs_n;
   (* prefix = "", result = "ODT" *)
   method    Bit#(odtwidth)           odt;
   (* prefix = "", result = "CKE" *)
   method    Bit#(ckewidth)           cke;
   (* prefix = "", result = "DM" *)
   method    Bit#(bewidth)            dm;
   (* prefix = "DQ" *)
   interface Inout#(Bit#(datawidth))  dq;
   (* prefix = "DQS_P" *)
   interface Inout#(Bit#(bewidth))    dqs_p;
   (* prefix = "DQS_N" *)
   interface Inout#(Bit#(bewidth))    dqs_n;
endinterface

interface DDR3_User#(`DDR3_PRM_DCL);
   interface Clock                    clock;
   interface Reset                    reset_n;
   method    Bool                     init_done;
   method    Action                   request(Bit#(ddr3addrsize) addr,
					      Bit#(TMul#(ddr3besize, TDiv#(clkratio,2)))   mask,
					      Bit#(TMul#(ddr3datasize, TDiv#(clkratio,2))) data
					      );
   method    ActionValue#(Bit#(TMul#(ddr3datasize, TDiv#(clkratio,2)))) read_data;
endinterface

interface DDR3_Controller#(`DDR3_PRM_DCL);
   (* prefix = "" *)
   interface DDR3_Pins#(`DDR3_PRM)  ddr3;
   (* prefix = "" *)
   interface DDR3_User#(`DDR3_PRM)  user;
endinterface

(* always_ready, always_enabled *)
interface VDDR3_User_Xilinx#(`DDR3_PRM_DCL);
   interface Clock             clock;
   interface Reset             reset;
   method    Bool              init_done;
   method    Action            app_addr(Bit#(ddr3addrsize) i);
   method    Action            app_cmd(Bit#(3) i);
   method    Action            app_en(Bool i);
   method    Action            app_wdf_data(Bit#(ddr3datasize) i);
   method    Action            app_wdf_end(Bool i);
   method    Action            app_wdf_mask(Bit#(ddr3besize) i);
   method    Action            app_wdf_wren(Bool i);
   method    Bit#(ddr3datasize) app_rd_data;
   method    Bool              app_rd_data_end;
   method    Bool              app_rd_data_valid;
   method    Bool              app_rdy;
   method    Bool              app_wdf_rdy;   
endinterface

interface VDDR3_Controller_Xilinx#(`DDR3_PRM_DCL);
   (* prefix = "" *)
   interface DDR3_Pins#(`DDR3_PRM)  ddr3;
   (* prefix = "" *)
   interface VDDR3_User_Xilinx#(`DDR3_PRM)  user;   
endinterface

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
///
///
///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
module mkAsyncResetLong#(Integer cycles, Reset rst_in, Clock clk_out)(Reset);
   Reg#(UInt#(32)) count <- mkReg(fromInteger(cycles), clocked_by clk_out, reset_by rst_in);
   let rstifc <- mkReset(0, True, clk_out);
   
   rule count_down if (count > 0);
      count <= count - 1;
      rstifc.assertReset();
   endrule
   
   return rstifc.new_rst;
endmodule

module mkXilinxDDR3Controller_2_1_#(VDDR3_Controller_Xilinx#(`DDR3_PRM) ddr3Ifc, DDR3_Configure cfg)(DDR3_Controller#(`DDR3_PRM))
   provisos( Add#(0, 2, clkratio)
	   , Add#(_1, 8, ddr3datasize)
	   , Add#(_2, 1, ddr3addrsize)
	   , Add#(_3, 1, ddr3besize)
	   );

   if (cfg.reads_in_flight < 1)
      error("The number of reads in flight has to be at least 1");

   Integer reads = cfg.reads_in_flight;
   
   ////////////////////////////////////////////////////////////////////////////////
   /// Clocks & Resets
   ////////////////////////////////////////////////////////////////////////////////
   Clock                                     clock               <- exposeCurrentClock;
   Reset                                     reset_n             <- exposeCurrentReset;
   Reset                                     dly_reset_n         <- mkAsyncResetLong( 40000, reset_n, clock );

   Clock                                     user_clock           = ddr3Ifc.user.clock;
   Reset                                     user_reset0_n       <- mkResetInverter(ddr3Ifc.user.reset);
   Reset                                     user_reset_n        <- mkAsyncReset(2, user_reset0_n, user_clock);

   ////////////////////////////////////////////////////////////////////////////////
   /// Design Elements
   ////////////////////////////////////////////////////////////////////////////////
   FIFO#(DDR3Request#(ddr3addrsize,
		      ddr3datasize,
		      ddr3besize))           fRequest            <- mkFIFO(clocked_by user_clock, reset_by user_reset_n);
   //FIFO#(DDR3Response#(ddr3datasize))        fResponse           <- mkSizedFIFO(reads, clocked_by user_clock, reset_by user_reset_n);
   FIFO#(DDR3Response#(ddr3datasize))        fResponse           <- mkFIFO(clocked_by user_clock, reset_by user_reset_n);
   
   //Count#(Int#(32))                         rReadsPending       <- mkCount(0, clocked_by user_clock, reset_by user_reset_n);
   Counter#(32)                              rReadsPending       <- mkCounter(0, clocked_by user_clock, reset_by user_reset_n);

  
   PulseWire                                 pwAppEn             <- mkPulseWire(clocked_by user_clock, reset_by user_reset_n);
   PulseWire                                 pwAppWdfWren        <- mkPulseWire(clocked_by user_clock, reset_by user_reset_n);
   PulseWire                                 pwAppWdfEnd         <- mkPulseWire(clocked_by user_clock, reset_by user_reset_n);
   
   Wire#(Bit#(3))                            wAppCmd             <- mkDWire(0, clocked_by user_clock, reset_by user_reset_n);
   Wire#(Bit#(ddr3addrsize))                 wAppAddr            <- mkDWire(0, clocked_by user_clock, reset_by user_reset_n);
   Wire#(Bit#(ddr3besize))                   wAppWdfMask         <- mkDWire('1, clocked_by user_clock, reset_by user_reset_n);
   Wire#(Bit#(ddr3datasize))                 wAppWdfData         <- mkDWire(0, clocked_by user_clock, reset_by user_reset_n);
   
   Bool initialized      = ddr3Ifc.user.init_done;
   Bool ctrl_ready_req   = ddr3Ifc.user.app_rdy;
   Bool write_ready_req  = ddr3Ifc.user.app_wdf_rdy;
   Bool read_data_ready  = ddr3Ifc.user.app_rd_data_valid;
   
   ////////////////////////////////////////////////////////////////////////////////
   /// Rules
   ////////////////////////////////////////////////////////////////////////////////
   (* fire_when_enabled, no_implicit_conditions *)
   rule drive_enables;
      ddr3Ifc.user.app_en(pwAppEn);
      ddr3Ifc.user.app_wdf_wren(pwAppWdfWren);
      ddr3Ifc.user.app_wdf_end(pwAppWdfEnd);
   endrule

   (* fire_when_enabled, no_implicit_conditions *)
   rule drive_data_signals;
      ddr3Ifc.user.app_cmd(wAppCmd);
      ddr3Ifc.user.app_addr(wAppAddr);
      ddr3Ifc.user.app_wdf_data(wAppWdfData);
      ddr3Ifc.user.app_wdf_mask(wAppWdfMask);
   endrule
   
   rule ready(initialized);
      rule process_write_request((fRequest.first.byteen != 0) && ctrl_ready_req && write_ready_req);
	 let request <- toGet(fRequest).get;
	 wAppCmd      <= 0;
	 wAppAddr     <= request.address;
	 wAppWdfData  <= request.data;
	 wAppWdfMask  <= ~request.byteen;
	 pwAppEn.send;
	 pwAppWdfWren.send;
	 pwAppWdfEnd.send;
      endrule
      
      //rule process_read_request(fRequest.first.byteen == 0 && ctrl_ready_req && rReadsPending < fromInteger(reads));
      rule process_read_request(fRequest.first.byteen == 0 && ctrl_ready_req);
	 let request <- toGet(fRequest).get;
	 wAppCmd  <= 1;
	 wAppAddr <= request.address;
	 pwAppEn.send;
	 //rReadsPending.incr(1);
         rReadsPending.up;
      endrule
      
      rule process_read_response(read_data_ready);
	 fResponse.enq(unpack(ddr3Ifc.user.app_rd_data));
	 //rReadsPending.decr(1);
         rReadsPending.down;
      endrule
   endrule

   ////////////////////////////////////////////////////////////////////////////////
   /// Interface Connections / Methods
   ////////////////////////////////////////////////////////////////////////////////
   interface ddr3 = ddr3Ifc.ddr3;
   interface DDR3_User user;
      interface clock   = user_clock;
      interface reset_n = user_reset_n;
      method init_done  = initialized;
      
      method Action request(Bit#(ddr3addrsize) addr, Bit#(ddr3besize) mask, Bit#(ddr3datasize) data);
	 let req = DDR3Request { byteen: mask, address: addr, data: data };
	 fRequest.enq(req);
      endmethod
	 
      method ActionValue#(Bit#(ddr3datasize)) read_data;
	 fResponse.deq;
	 return fResponse.first.data;
      endmethod
   endinterface
endmodule

endpackage: DDR3Common

