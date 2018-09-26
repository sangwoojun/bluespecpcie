package Shifter;

import GetPut::*;
import FIFO::*;
import BRAMFIFO::*;
import SpecialFIFOs::*;
import Vector::*;

function Bit#(tDataWidth) rotateRByte (Bit#(tDataWidth) inData, Bit#(tShiftWidth) shift);
   return inData >> {shift, 3'b0};
endfunction

function Bit#(tDataWidth) rotateLByte (Bit#(tDataWidth) inData, Bit#(tShiftWidth) shift);
   return inData << {shift, 3'b0};
endfunction   
                                                                                            


interface ByteShiftIfc#(type element_type, numeric type size);
   //provisos(Bits#(elment_type, a__));
   //method Action rotateByte(element_type v, Bit#(TLog#(TDiv#(SizeOf#(element_type),8))) shift);
   method Action rotateByteBy(element_type v, Bit#(size) shift);
   method ActionValue#(element_type) getVal;
endinterface

typedef TLog#(TDiv#(SizeOf#(element_type),8)) ElementShiftSz#(type element_type);
typedef ByteShiftIfc#(element_type, ElementShiftSz#(element_type)) ByteSftIfc#(type element_type);


module mkCombinationalRightShifter(ByteShiftIfc#(element_type, size))
   provisos(Bits#(element_type, a__),
            Bitwise#(element_type),
            Add#(1, b__, a__));
   
   FIFO#(element_type) inputFifo;
   FIFO#(Bit#(size)) inputFifo_sft <- mkFIFO;
   //if ( fromInteger(valueOf(SizeOf#(element_type))) > 512 ) 
   //inputFifo <- mkSizedFIFO(1);
//else
      inputFifo <- mkFIFO;
   
   //FIFO#(element_type) outputFifo <- mkBypassFIFO;
   
   /*rule doRotation;
      let data <- toGet(inputFifo).get();
      let shft <- toGet(inputFifo_sft).get();
      outputFifo.enq(data >> {shft, 3'b0});
   endrule*/
   
   method Action rotateByteBy(element_type v, Bit#(size) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      inputFifo.enq(v);
      inputFifo_sft.enq(shift);
   endmethod
   method ActionValue#(element_type) getVal;
      let data <- toGet(inputFifo).get();
      let shft <- toGet(inputFifo_sft).get();
      return data >> {shft, 3'b0};
   endmethod
endmodule

module mkCombinationalLeftShifter(ByteShiftIfc#(element_type, size))
   provisos(Bits#(element_type, a__),
            Bitwise#(element_type),
            Add#(1, b__, a__));
   
   
   //FIFO#(Tuple2#(element_type, Bit#(size))) inputFifo;
   FIFO#(element_type) inputFifo;
   FIFO#(Bit#(size)) inputFifo_sft <- mkFIFO;
   //if ( fromInteger(valueOf(SizeOf#(element_type))) > 512 ) 
   //   inputFifo <- mkSizedFIFO(1);
   //else
      inputFifo <- mkFIFO;
   
   //FIFO#(element_type) outputFifo <- mkBypassFIFO;
   /*
   rule doRotation;
      let data <- toGet(inputFifo).get();
      let shft <- toGet(inputFifo_sft).get();
      outputFifo.enq(data << {shft, 3'b0});
   endrule
   */
   method Action rotateByteBy(element_type v, Bit#(size) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      inputFifo.enq(v);
      inputFifo_sft.enq(shift);
   endmethod
   method ActionValue#(element_type) getVal;
      let data <- toGet(inputFifo).get();
      let shft <- toGet(inputFifo_sft).get();
      return data << {shft, 3'b0};
   endmethod
endmodule

module mkPipelineRightShifter(ByteShiftIfc#(element_type, size))
   provisos(Bits#(element_type, a__),
            Bitwise#(element_type));
   
   Integer numStages =  valueOf(size);
   
   Vector#(size, FIFO#(Tuple2#(element_type, Bit#(size)))) stageFifos <- replicateM(mkFIFO);
   
   FIFO#(element_type) outputFifo <- mkBypassFIFO;
   
   for (Integer i = numStages - 1; i >= 0; i = i - 1) begin
      rule doStage;
         let args <- toGet(stageFifos[i]).get();
         let val = tpl_1(args);
         let shift = tpl_2(args);
         
         if ( shift[i] == 1 ) begin
            val = val >> ((1<<i)*8);
         end
         
         if ( i > 0 ) begin
            stageFifos[i-1].enq(tuple2(val,shift));
         end
         else begin
            outputFifo.enq(val);
         end
      endrule
   end
      
   method Action rotateByteBy(element_type v, Bit#(size) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      stageFifos[numStages-1].enq(tuple2(v,shift));
   endmethod
   method ActionValue#(element_type) getVal;
      let v <- toGet(outputFifo).get();
      return v;
   endmethod
endmodule


module mkPipelineLeftShifter(ByteShiftIfc#(element_type, size))
   provisos(Bits#(element_type, a__),
            Bitwise#(element_type));
   
   Integer numStages =  valueOf(size);
   
   Vector#(size, FIFO#(Tuple2#(element_type, Bit#(size)))) stageFifos <- replicateM(mkFIFO);
   
   FIFO#(element_type) outputFifo <- mkBypassFIFO;
   
   for (Integer i = numStages - 1; i >= 0; i = i - 1) begin
      rule doStage;
         let args <- toGet(stageFifos[i]).get();
         let val = tpl_1(args);
         let shift = tpl_2(args);
         
         if ( shift[i] == 1 ) begin
            val = val << ((1<<i)*8);
         end
         
         if ( i > 0 ) begin
            stageFifos[i-1].enq(tuple2(val,shift));
         end
         else begin
            outputFifo.enq(val);
         end
      endrule
   end
      
   method Action rotateByteBy(element_type v, Bit#(size) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      stageFifos[numStages-1].enq(tuple2(v,shift));
   endmethod
   method ActionValue#(element_type) getVal;
      let v <- toGet(outputFifo).get();
      return v;
   endmethod
endmodule

endpackage
