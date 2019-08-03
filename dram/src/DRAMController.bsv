package DRAMController;

import Clocks          :: *;
import DDR3Controller::*;
import DDR3Common::*;

import Shifter::*;

import FIFO::*;
import BRAMFIFO::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import Counter::*;

import DRAMControllerTypes::*;

typedef 64 MaxReadReqs;

interface DebugProbe;
   method DDRRequest req;
   method DDRResponse resp;
endinterface

interface DRAMUserIfc;
	method Action write(Bit#(64) addr, Bit#(512) data, Bit#(7) bytes);

	method ActionValue#(Bit#(512)) read;
	method Action readReq(Bit#(64) addr, Bit#(7) bytes);
	
	interface Clock user_clk;
	interface Reset user_rst;
endinterface

interface DRAMControllerIfc;
	interface DRAMUserIfc user;
	interface DebugProbe debug;
	//interface DDR3Client ddr3_cli;
endinterface

typedef struct{
   Bit#(3) bankaddr;
   Bit#(14) rowaddr;
   Bit#(10) coladdr;
   Bit#(3) offset;
   } DDRPhyAddr deriving (Bits, Eq); //1GB



function Bit#(64) addrReMapping(Bit#(64) v);
   DDRPhyAddr addr;// = unpack(truncate(v));
   addr.offset = v[2:0];
   addr.coladdr = v[12:3];
   addr.rowaddr = {v[29:21],v[17:13]};
   addr.bankaddr = v[20:18];
   //9, 3, 5, 10, 3
   //return {0, addr.rowaddr[13:5], addr.bankaddr, addr.rowaddr[4:0],addr.coladdr,addr.offset};
   return zeroExtend(pack(addr));
endfunction
                                           

//(*synthesize*)
module mkDRAMController#(DDR3_User_1GB ddr3) (DRAMControllerIfc);
   Integer maxReadReqs = valueOf(MaxReadReqs);

   Clock cur_clk <- exposeCurrentClock;
   Reset rst_n <- exposeCurrentReset;

   Clock ddr_clk = ddr3.clock;
   Reset ddr_rst = ddr3.reset_n;
      
   SyncFIFOIfc#(DDRRequest) reqs <- mkSyncFIFOFromCC(32, ddr_clk);
   SyncFIFOIfc#(DDRResponse) respSyncQ <- mkSyncFIFOToCC(32, ddr_clk, ddr_rst);
   FIFO#(DDRResponse) resps <- mkSizedFIFO(maxReadReqs, clocked_by ddr_clk, reset_by ddr_rst);


   
   
   FIFO#(DRAMWrRequest) dramWrCmdQ <- mkFIFO();
   FIFO#(DRAMRdRequest) dramRdCmdQ <- mkFIFO();
   //FIFO#(Tuple2#(Bool,Bit#(6))) readOffsetQ <- mkSizedFIFO(32);
   //FIFO#(Tuple2#(Bool,Bit#(6))) readOffsetQ <- mkSizedFIFO(64);
   FIFO#(Tuple2#(Bool,Bit#(6))) readOffsetQ <- mkSizedFIFO(64);
   
   
   Reg#(Bool) nextRowW <- mkReg(False);
   
   //FIFO#(Bool) nextCmdTypeQ <- mkSizedFIFO(64);
   FIFO#(Bool) nextCmdTypeQ <- mkFIFO;   
   rule driverWrie (!nextCmdTypeQ.first);//(!dramCmdQ.first.rnw);
      let v = dramWrCmdQ.first;
      let addr = v.addr;
      let data = v.data;
      let mask0 = v.mask0;
      let mask1 = v.mask1;
      let nBytes = v.nBytes;
      
      let rowidx = addr>>6;
      
      let offset = addr[5:0];
      

      Bit#(7) firstNbytes = 64 - extend(offset);

      //$display("%t write nextRowW = %d, offset = %d", $time, nextRowW, offset);
      if ( !nextRowW ) begin  
         reqs.enq(DDRRequest{writeen: mask0,
                             address: rowidx << 3,
                             datain: data << {offset,3'b0}
                             });
         if (firstNbytes < v.nBytes) begin
            nextRowW <= True;
         end
         else begin
            dramWrCmdQ.deq;
            nextCmdTypeQ.deq;
         end
      end
      else begin
         reqs.enq(DDRRequest{writeen: mask1,
                             address: (rowidx + 1) << 3,
                             datain: data >> {(~offset+1),3'b0}
                             });
         nextRowW <= False;
         dramWrCmdQ.deq;
         nextCmdTypeQ.deq;
      end
   endrule

   
   Reg#(Bool) nextRowR <- mkReg(False);
   
   ByteShiftIfc#(Bit#(1024), 6) rightSft <- mkCombinationalRightShifter();
   
   rule driverReadC (nextCmdTypeQ.first);
      
      let v = dramRdCmdQ.first;
      let addr = v.addr;
      let nBytes = v.nBytes;
      let rowidx = addr>>6;
         
      //Bit#(7) offset = extend(addr[5:0]);
      Bit#(6) offset = truncate(addr);
      Bit#(7) firstNbytes = 64 - extend(offset);
      //$display("%t read nextRowR = %d, offset = %d", $time, nextRowR, offset);
      if ( !nextRowR ) begin
         reqs.enq(DDRRequest{writeen: 0,
                             address: rowidx<<3,
                             datain: ?
                             });
         if ( nBytes > firstNbytes ) begin
            nextRowR <= True;
            readOffsetQ.enq(tuple2(True,offset));
         end
         else begin
            //readOffsetQ.enq(tuple2(False,offset+64));
            readOffsetQ.enq(tuple2(False,offset));
            dramRdCmdQ.deq();
            nextCmdTypeQ.deq;
         end
      end
      else begin
         reqs.enq(DDRRequest{writeen: 0,
                             address: (rowidx + 1) << 3,
                             datain: ?
                             });
         dramRdCmdQ.deq();
         nextCmdTypeQ.deq;
         nextRowR <= False;
         readOffsetQ.enq(tuple2(False,offset));
      end
                  
      
   endrule

   Reg#(Bit#(TAdd#(1,TLog#(MaxReadReqs)))) reqCountUp <- mkReg(0, clocked_by ddr_clk, reset_by ddr_rst); 
   Reg#(Bit#(TAdd#(1,TLog#(MaxReadReqs)))) reqCountDown <- mkReg(0, clocked_by ddr_clk, reset_by ddr_rst); 
   
   Reg#(Bit#(512)) readCache <- mkRegU();
   //Reg#(Bit#(64)) cnt <- mkReg(0);
	rule recvRead;

		Bit#(512) res <- toGet(respSyncQ).get();
		let v <- toGet(readOffsetQ).get();
		//$display("dram recvRead = %h", res);
		//readOffsetQ.deq;
		let cache = tpl_1(v);
		let offset = tpl_2(v);
		//$display("(%t), cache = %d, offset = %d", $time, cache, offset);

		if ( cache ) begin
			readCache <= res;
		end
		else begin
			//cnt <= cnt + 1;
			if ( offset == 0)
				rightSft.rotateByteBy(extend(res), offset);
			else
				rightSft.rotateByteBy({res,readCache}, offset);
		end
	endrule

   Wire#(DDRRequest) req_wire <- mkWire;
   Wire#(DDRResponse) resp_wire <- mkWire;

   rule relayReqs (reqCountUp-reqCountDown < fromInteger(maxReadReqs));
	   reqs.deq;
	   let req = reqs.first;
	   ddr3.request(truncate(req.address), req.writeen, req.datain);
	   if ( req.writeen == 0 ) reqCountUp <= reqCountUp + 1;
   endrule

   rule relayResps;
	   let x <- ddr3.read_data;
	   resps.enq(x);
   endrule

	rule relayResps2;
		resps.deq;
		respSyncQ.enq(resps.first);
		reqCountDown <= reqCountDown + 1;
	endrule
    

   
   interface DRAMUserIfc user;
   interface Clock user_clk = cur_clk;
   interface Reset user_rst = rst_n;

   method Action write(Bit#(64) addr, Bit#(512) data, Bit#(7) bytes);
      let mappedaddr = addrReMapping(addr);
      DDRPhyAddr v = unpack(truncate(mappedaddr));      
      //$display("DRAMWrite Cmd, addr = %d, {bank = %d, row = %d, col = %d, offset = %d} data = %h, bytes = %d", mappedaddr, v.bankaddr, v.rowaddr, v.coladdr, v.offset, data, bytes);
      Bit#(6) offset = truncate(addr);
      Bit#(64) mask = (1<<bytes) - 1;
      let mask0 = mask << offset;
      let mask1 = mask >> ((~offset) + 1);

      //$display("DRAMWrite Cmd, addr = %d, data = %h, bytes = %h", addr, data, bytes);
      dramWrCmdQ.enq(DRAMWrRequest{nBytes: bytes, addr: mappedaddr, data: data, mask0:mask0, mask1:mask1});
      nextCmdTypeQ.enq(False);
   endmethod
   
   method Action readReq(Bit#(64) addr, Bit#(7) bytes);
      //$display("\x1b[35mDRAMController(%t): get read req, addr = %d, bytes = %d\x1b[0m", $time, addr, bytes);
      let mappedaddr = addrReMapping(addr);
      DDRPhyAddr v = unpack(truncate(mappedaddr));      
      //$display("DRAMRead Cmd, addr = %d, {bank = %d, row = %d, col = %d, offset = %d} , bytes = %d", mappedaddr, v.bankaddr, v.rowaddr, v.coladdr, v.offset, bytes);
      dramRdCmdQ.enq(DRAMRdRequest{nBytes: bytes, addr: mappedaddr});
      nextCmdTypeQ.enq(True);
   endmethod
   method ActionValue#(Bit#(512)) read;
      let v <- rightSft.getVal;
      return truncate(v);
   endmethod
   endinterface


   
   interface DebugProbe debug;
      method DDRRequest req;
         return req_wire;
      endmethod
      method DDRResponse resp;
         return resp_wire;
      endmethod
   endinterface
   
endmodule

endpackage: DRAMController
