import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import BRAM::*;
import BRAMFIFO::*;

import Shifter::*;

interface ShiftUnpackerIfc#(type packType, type elemType);
	method Action put(Maybe#(packType) data);
	method ActionValue#(Maybe#(elemType)) get;
endinterface

module mkShiftUnpacker (ShiftUnpackerIfc#(packType, elemType))
	provisos(
		Bits#(packType, packTypeSz), Bits#(elemType, elemTypeSz),
		Mul#(packTypeSz,2,packTypeSzT),
		Add#(packTypeSz,b__, packTypeSzT),
		Add#(elemTypeSz,c__, packTypeSzT),
		Add#(elemTypeSz, a__, packTypeSz), 
		Div#(packTypeSz,8,packTypeBytes),
		Div#(elemTypeSz, 8, elemTypeBytes),
		Log#(packTypeBytes,packTypeLogF),
		Add#(packTypeLogF,1,packTypeLog)
	);

	Integer iPackTypeSz = valueOf(packTypeSz);
	Integer iElemTypeSz = valueOf(elemTypeSz);
	Integer iPackTypeBytes = valueOf(packTypeBytes);
	Integer iElemTypeBytes = valueOf(elemTypeBytes);

	FIFO#(Maybe#(packType)) inQ <- mkFIFO;
	FIFO#(Maybe#(elemType)) outQ <- mkFIFO;

	ByteShiftIfc#(Bit#(packTypeSzT), packTypeLog) byteShifter <- mkPipelineRightShifter;
	Reg#(Bit#(packTypeLog)) curShift <- mkReg(0);
	Reg#(Maybe#(Bit#(packTypeSz))) curBuffer <- mkReg(tagged Invalid);
	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(16);

	rule unpackData;
		if ( !isValid(curBuffer) ) begin
			inQ.deq;
			let d = inQ.first;
			if ( !isValid(d) ) begin
				curShift <= 0;
				byteShifter.rotateByteBy(0,0);
				isShiftedValidQ.enq(False);
			end else begin
				Bit#(packTypeSz) dd = pack(fromMaybe(?,d));

				curBuffer <= tagged Valid dd;

				byteShifter.rotateByteBy({0,dd},0);
				curShift <= fromInteger(iElemTypeBytes);
				isShiftedValidQ.enq(True);
			end
		end else if ( curShift + fromInteger(iElemTypeBytes) >= fromInteger(iPackTypeBytes) ) begin
			inQ.deq;
			let d = inQ.first;
			let dd0 = fromMaybe(?,curBuffer);
			if ( !isValid(d) ) begin
				byteShifter.rotateByteBy(0,0);
				isShiftedValidQ.enq(False);
				curShift <= 0;
				curBuffer <= tagged Invalid;
			end else begin
				let dd = pack(fromMaybe(?,d));
				curBuffer <= tagged Valid dd;

				let dt = {dd,dd0};
				byteShifter.rotateByteBy(dt,curShift);
				isShiftedValidQ.enq(True);

				curShift <= curShift + fromInteger(iElemTypeBytes) - fromInteger(iPackTypeBytes);
			end
		end else begin
			let dd0 = fromMaybe(?,curBuffer);
			byteShifter.rotateByteBy({0,dd0}, curShift);
			isShiftedValidQ.enq(True);

			curShift <= curShift + fromInteger(iElemTypeBytes);
		end
	endrule

	rule relayUnpack;
		let d <- byteShifter.getVal;
		let v = isShiftedValidQ.first;
		isShiftedValidQ.deq;

		if ( !v ) begin
			outQ.enq(tagged Invalid);
		end else begin
			outQ.enq(tagged Valid unpack(truncate(d)));
		end

	endrule

	
	method Action put(Maybe#(packType) data);
		inQ.enq(data);
	endmethod
	method ActionValue#(Maybe#(elemType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

interface ShiftPackerIfc#(type packType, type elemType);
	method Action put(Maybe#(elemType) data);
	method ActionValue#(Maybe#(packType)) get;
endinterface

module mkShiftPacker (ShiftPackerIfc#(packType, elemType))
	provisos(
		Bits#(packType, packTypeSz), Bits#(elemType, elemTypeSz),
		Mul#(packTypeSz,2,packTypeSzT),
		Add#(packTypeSz,b__, packTypeSzT),
		Add#(elemTypeSz,c__, packTypeSzT),
		Add#(elemTypeSz, a__, packTypeSz), 
		Div#(packTypeSz,8,packTypeBytes),
		Div#(elemTypeSz, 8, elemTypeBytes),
		Log#(packTypeBytes,packTypeLogF),
		Add#(packTypeLogF,1,packTypeLog)
	);

	Integer iPackTypeSz = valueOf(packTypeSz);
	Integer iElemTypeSz = valueOf(elemTypeSz);
	Integer iPackTypeBytes = valueOf(packTypeBytes);
	Integer iElemTypeBytes = valueOf(elemTypeBytes);

	FIFO#(Maybe#(packType)) outQ <- mkFIFO;
	FIFO#(Maybe#(elemType)) inQ <- mkFIFO;

	ByteShiftIfc#(Bit#(packTypeSzT), packTypeLog) byteShifter <- mkPipelineLeftShifter;
	Reg#(Bit#(packTypeLog)) curShift <- mkReg(0);
	Reg#(Maybe#(Bit#(packTypeSz))) curBuffer <- mkReg(tagged Invalid);
	FIFO#(Bool) isShiftedValidQ <- mkSizedFIFO(16);

	rule shiftData;
		inQ.deq;
		let d = inQ.first;
		if ( isValid(d) ) begin
			let dd = pack(fromMaybe(?,d));

			if ( curShift + fromInteger(iElemTypeBytes) >= fromInteger(iPackTypeBytes) ) begin
				byteShifter.rotateByteBy({0,dd}, curShift);
				curShift <= curShift + fromInteger(iElemTypeBytes) - fromInteger(iPackTypeBytes);
				isShiftedValidQ.enq(True);
			end else begin
				byteShifter.rotateByteBy({0,dd}, curShift);
				curShift <= curShift + fromInteger(iElemTypeBytes);
				isShiftedValidQ.enq(True);
			end
		end else begin
			curShift <= 0;
			byteShifter.rotateByteBy(0,0);
			isShiftedValidQ.enq(False);
		end
	endrule

	Reg#(Bool) packFlushing <- mkReg(False);
	Reg#(Bit#(packTypeLog)) packShiftBytes <- mkReg(0);
	Reg#(Maybe#(Bit#(packTypeSz))) writeBuffer <- mkReg(tagged Invalid);

	rule packData(!packFlushing);
		let d <- byteShifter.getVal;
		let v = isShiftedValidQ.first;
		isShiftedValidQ.deq;

		if ( v ) begin
			if ( packShiftBytes + fromInteger(iElemTypeBytes) >= fromInteger(iPackTypeBytes) ) begin
				packShiftBytes <= packShiftBytes + fromInteger(iElemTypeBytes) - fromInteger(iPackTypeBytes);

				writeBuffer <= tagged Valid truncateLSB(d);
				
				// no need to check for isValid(writeBuffer) because iElemTypeBytes < iPackTypeBytes
				outQ.enq(tagged Valid unpack(fromMaybe(?,writeBuffer) | truncate(d)) );
			end else begin
				if ( isValid(writeBuffer) ) begin
					writeBuffer <= tagged Valid (fromMaybe(?,writeBuffer) | truncate(d));
				end else begin
					writeBuffer <= tagged Valid truncate(d);
				end
				packShiftBytes <= packShiftBytes + fromInteger(iElemTypeBytes);
			end
		end else begin
			packShiftBytes <= 0;
			if ( isValid(writeBuffer) ) begin
				outQ.enq(tagged Valid unpack(fromMaybe(?,writeBuffer)));
				packFlushing <= True;
			end else begin
				outQ.enq(tagged Invalid);
			end
			writeBuffer <= tagged Invalid;
		end
	endrule
	
	rule packFlush ( packFlushing );
		packFlushing <= False;
		outQ.enq(tagged Invalid);
	endrule




	method Action put(Maybe#(elemType) data);
		inQ.enq(data);
	endmethod
	method ActionValue#(Maybe#(packType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

