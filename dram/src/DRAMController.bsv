package DRAMController;


import Clocks          :: *;
//import XilinxVC707DDR3::*;
//import Xilinx       :: *;
//import XilinxCells ::*;
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

interface DebugProbe;
   method DDRRequest req;
   method DDRResponse resp;
endinterface

interface DRAMUserIfc;
	method Action write(Bit#(64) addr, Bit#(512) data, Bit#(7) bytes);

	method ActionValue#(Bit#(512)) read;
	method Action readReq(Bit#(64) addr, Bit#(7) bytes);
endinterface

interface DRAMControllerIfc;
	interface DRAMUserIfc user;
	interface DebugProbe debug;
	interface DDR3Client ddr3_cli;
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
                                           

(*synthesize*)
module mkDRAMController(DRAMControllerIfc);
   Clock clk <- exposeCurrentClock;
   Reset rst_n <- exposeCurrentReset;
      
   FIFO#(DDRRequest) reqs <- mkFIFO();
   FIFO#(DDRResponse) resps <- mkFIFO();
   
   
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
   
   Reg#(Bit#(512)) readCache <- mkRegU();
   Reg#(Bit#(64)) cnt <- mkReg(0);
   rule recvRead;

      Bit#(512) res <- toGet(resps).get();
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
         cnt <= cnt + 1;
         if ( offset == 0)
            rightSft.rotateByteBy(extend(res), offset);
         else
            rightSft.rotateByteBy({res,readCache}, offset);
      end
   endrule

   Wire#(DDRRequest) req_wire <- mkWire;
   Wire#(DDRResponse) resp_wire <- mkWire;
   
   interface DRAMUserIfc user;
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


   interface DDR3Client ddr3_cli;
      //interface Get request = toGet(reqs);
      //interface Put response = toPut(resps);
      interface Get request;// = toGet(reqs);
         method ActionValue#(DDRRequest) get();
            let v <- toGet(reqs).get();
            req_wire <= v;
            return v;
         endmethod
      endinterface
      
      interface Put response;
         method Action put(DDRResponse v);
            resp_wire <= v;
            toPut(resps).put(v);
         endmethod
      endinterface
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

typedef 64 MAX_OUTSTANDING_READS;

instance Connectable#(DDR3Client, DDR3_User_VC707_1GB);
   module mkConnection#(DDR3Client cli, DDR3_User_VC707_1GB usr)(Empty);
      
      // Make sure we have enough buffer space to not drop responses!
      Counter#(TLog#(MAX_OUTSTANDING_READS)) reads <- mkCounter(0, clocked_by(usr.clock), reset_by(usr.reset_n));
      FIFO#(DDRResponse) respbuf <- mkSizedFIFO(valueof(MAX_OUTSTANDING_READS), clocked_by(usr.clock), reset_by(usr.reset_n));
   
      rule request (reads.value() != fromInteger(valueof(MAX_OUTSTANDING_READS)-1));
         let req <- cli.request.get();
         usr.request(truncate(req.address), req.writeen, req.datain);
         
         if (req.writeen == 0) begin
            reads.up();
         end
      endrule
   
      rule response (True);
         let x <- usr.read_data;
         respbuf.enq(x);
      endrule
   
      rule forward (True);
         let x <- toGet(respbuf).get();
         cli.response.put(x);
         reads.down();
      endrule
   endmodule
endinstance
instance Connectable#(DDR3Client, DDR3_User_KC705_1GB);
   module mkConnection#(DDR3Client cli, DDR3_User_KC705_1GB usr)(Empty);
      
      // Make sure we have enough buffer space to not drop responses!
      Counter#(TLog#(MAX_OUTSTANDING_READS)) reads <- mkCounter(0, clocked_by(usr.clock), reset_by(usr.reset_n));
      FIFO#(DDRResponse) respbuf <- mkSizedFIFO(valueof(MAX_OUTSTANDING_READS), clocked_by(usr.clock), reset_by(usr.reset_n));
   
      rule request (reads.value() != fromInteger(valueof(MAX_OUTSTANDING_READS)-1));
         let req <- cli.request.get();
         usr.request(truncate(req.address), req.writeen, req.datain);
         
         if (req.writeen == 0) begin
            reads.up();
         end
      endrule
   
      rule response (True);
         let x <- usr.read_data;
         respbuf.enq(x);
      endrule
   
      rule forward (True);
         let x <- toGet(respbuf).get();
         cli.response.put(x);
         reads.down();
      endrule
   endmodule
endinstance


// Brings a DDR3Client from one clock domain to another.
module mkDDR3ClientSync#(DDR3Client ddr2,
    Clock sclk, Reset srst, Clock dclk, Reset drst
    ) (DDR3Client);

    SyncFIFOIfc#(DDRRequest) reqs <- mkSyncFIFO(32, sclk, srst, dclk);
    SyncFIFOIfc#(DDRResponse) resps <- mkSyncFIFO(32, dclk, drst, sclk);

    mkConnection(toPut(reqs), toGet(ddr2.request));
    mkConnection(toGet(resps), toPut(ddr2.response));

    interface Get request = toGet(reqs);
    interface Put response = toPut(resps);
endmodule

endpackage: DRAMController
