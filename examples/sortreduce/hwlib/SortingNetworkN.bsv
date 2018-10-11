import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
	
import SortingNetwork::*;
	
module mkSortingNetwork8#(Bool descending) (SortingNetworkIfc#(inType, 8))
	provisos(
	Bits#(Vector::Vector#(8, inType), inVSz),
	Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz)
	);


	Vector#(8, FIFO#(inType)) st0Q <- replicateM(mkFIFO);


	Vector#(4, OptCompareAndSwapIfc#(inType)) cas1 <- replicateM(mkOptCompareAndSwap(descending));
	rule stage0;
		let td0 = st0Q[0].first;
		st0Q[0].deq;
		let td1 = st0Q[1].first;
		st0Q[1].deq;
		let td2 = st0Q[2].first;
		st0Q[2].deq;
		let td3 = st0Q[3].first;
		st0Q[3].deq;
		let td4 = st0Q[4].first;
		st0Q[4].deq;
		let td5 = st0Q[5].first;
		st0Q[5].deq;
		let td6 = st0Q[6].first;
		st0Q[6].deq;
		let td7 = st0Q[7].first;
		st0Q[7].deq;
		cas1[0].put(tuple2(td0, td7));
		cas1[1].put(tuple2(td1, td6));
		cas1[2].put(tuple2(td2, td5));
		cas1[3].put(tuple2(td3, td4));
	endrule
	Vector#(4, OptCompareAndSwapIfc#(inType)) cas2 <- replicateM(mkOptCompareAndSwap(descending));
	rule stage1;
		let casd0 <- cas1[0].get;
		let td0 = tpl_1(casd0);
		let casd1 <- cas1[1].get;
		let td1 = tpl_1(casd1);
		let casd2 <- cas1[2].get;
		let td2 = tpl_1(casd2);
		let casd3 <- cas1[3].get;
		let td3 = tpl_1(casd3);
		let td4 = tpl_2(casd3);
		let td5 = tpl_2(casd2);
		let td6 = tpl_2(casd1);
		let td7 = tpl_2(casd0);
		cas2[0].put(tuple2(td0, td3));
		cas2[1].put(tuple2(td4, td7));
		cas2[2].put(tuple2(td1, td2));
		cas2[3].put(tuple2(td5, td6));
	endrule
	Vector#(4, OptCompareAndSwapIfc#(inType)) cas3 <- replicateM(mkOptCompareAndSwap(descending));
	rule stage2;
		let casd0 <- cas2[0].get;
		let td0 = tpl_1(casd0);
		let casd2 <- cas2[2].get;
		let td1 = tpl_1(casd2);
		let td2 = tpl_2(casd2);
		let td3 = tpl_2(casd0);
		let casd1 <- cas2[1].get;
		let td4 = tpl_1(casd1);
		let casd3 <- cas2[3].get;
		let td5 = tpl_1(casd3);
		let td6 = tpl_2(casd3);
		let td7 = tpl_2(casd1);
		cas3[0].put(tuple2(td0, td1));
		cas3[1].put(tuple2(td2, td3));
		cas3[2].put(tuple2(td4, td5));
		cas3[3].put(tuple2(td6, td7));
	endrule
	Vector#(2, OptCompareAndSwapIfc#(inType)) cas4 <- replicateM(mkOptCompareAndSwap(descending));
	Vector#(4, FIFO#(inType)) st4Q <- replicateM(mkFIFO);
	rule stage3;
		let casd0 <- cas3[0].get;
		let td0 = tpl_1(casd0);
		let td1 = tpl_2(casd0);
		let casd1 <- cas3[1].get;
		let td2 = tpl_1(casd1);
		let td3 = tpl_2(casd1);
		let casd2 <- cas3[2].get;
		let td4 = tpl_1(casd2);
		let td5 = tpl_2(casd2);
		let casd3 <- cas3[3].get;
		let td6 = tpl_1(casd3);
		let td7 = tpl_2(casd3);
		cas4[0].put(tuple2(td3, td5));
		cas4[1].put(tuple2(td2, td4));
		st4Q[0].enq(td0);
		st4Q[1].enq(td1);
		st4Q[2].enq(td6);
		st4Q[3].enq(td7);
	endrule
	Vector#(3, OptCompareAndSwapIfc#(inType)) cas5 <- replicateM(mkOptCompareAndSwap(descending));
	Vector#(2, FIFO#(inType)) st5Q <- replicateM(mkFIFO);
	rule stage4;
		let td0 = st4Q[0].first;
		st4Q[0].deq;
		let td1 = st4Q[1].first;
		st4Q[1].deq;
		let casd1 <- cas4[1].get;
		let td2 = tpl_1(casd1);
		let casd0 <- cas4[0].get;
		let td3 = tpl_1(casd0);
		let td4 = tpl_2(casd1);
		let td5 = tpl_2(casd0);
		let td6 = st4Q[2].first;
		st4Q[2].deq;
		let td7 = st4Q[3].first;
		st4Q[3].deq;
		cas5[0].put(tuple2(td1, td2));
		cas5[1].put(tuple2(td3, td4));
		cas5[2].put(tuple2(td5, td6));
		st5Q[0].enq(td0);
		st5Q[1].enq(td7);
	endrule
	Vector#(2, OptCompareAndSwapIfc#(inType)) cas6 <- replicateM(mkOptCompareAndSwap(descending));
	Vector#(4, FIFO#(inType)) st6Q <- replicateM(mkFIFO);
	rule stage5;
		let td0 = st5Q[0].first;
		st5Q[0].deq;
		let casd0 <- cas5[0].get;
		let td1 = tpl_1(casd0);
		let td2 = tpl_2(casd0);
		let casd1 <- cas5[1].get;
		let td3 = tpl_1(casd1);
		let td4 = tpl_2(casd1);
		let casd2 <- cas5[2].get;
		let td5 = tpl_1(casd2);
		let td6 = tpl_2(casd2);
		let td7 = st5Q[1].first;
		st5Q[1].deq;
		cas6[0].put(tuple2(td2, td3));
		cas6[1].put(tuple2(td4, td5));
		st6Q[0].enq(td0);
		st6Q[1].enq(td1);
		st6Q[2].enq(td6);
		st6Q[3].enq(td7);
	endrule
	method Action enq(Vector#(8, inType) data);
		for (Integer i = 0; i < 8; i=i+1 ) begin
			st0Q[i].enq(data[i]);
		end
	endmethod
	method ActionValue#(Vector#(8, inType)) get;
		Vector#(8,inType) outd;
		let td0 = st6Q[0].first;
		st6Q[0].deq;
		outd[0] = td0;
		let td1 = st6Q[1].first;
		st6Q[1].deq;
		outd[1] = td1;
		let casd0 <- cas6[0].get;
		let td2 = tpl_1(casd0);
		outd[2] = td2;
		let td3 = tpl_2(casd0);
		outd[3] = td3;
		let casd1 <- cas6[1].get;
		let td4 = tpl_1(casd1);
		outd[4] = td4;
		let td5 = tpl_2(casd1);
		outd[5] = td5;
		let td6 = st6Q[2].first;
		st6Q[2].deq;
		outd[6] = td6;
		let td7 = st6Q[3].first;
		st6Q[3].deq;
		outd[7] = td7;
		return outd;
	endmethod


endmodule

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
	
import SortingNetwork::*;
	
module mkSortingNetwork4#(Bool descending) (SortingNetworkIfc#(inType, 4))
	provisos(
	Bits#(Vector::Vector#(4, inType), inVSz),
	Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz)
	);


	Vector#(4, FIFO#(inType)) st0Q <- replicateM(mkFIFO);


	Vector#(2, OptCompareAndSwapIfc#(inType)) cas1 <- replicateM(mkOptCompareAndSwap(descending));
	rule stage0;
		let td0 = st0Q[0].first;
		st0Q[0].deq;
		let td1 = st0Q[1].first;
		st0Q[1].deq;
		let td2 = st0Q[2].first;
		st0Q[2].deq;
		let td3 = st0Q[3].first;
		st0Q[3].deq;
		cas1[0].put(tuple2(td0, td1));
		cas1[1].put(tuple2(td2, td3));
	endrule
	Vector#(2, OptCompareAndSwapIfc#(inType)) cas2 <- replicateM(mkOptCompareAndSwap(descending));
	rule stage1;
		let casd0 <- cas1[0].get;
		let td0 = tpl_1(casd0);
		let td1 = tpl_2(casd0);
		let casd1 <- cas1[1].get;
		let td2 = tpl_1(casd1);
		let td3 = tpl_2(casd1);
		cas2[0].put(tuple2(td1, td3));
		cas2[1].put(tuple2(td0, td2));
	endrule
	Vector#(1, OptCompareAndSwapIfc#(inType)) cas3 <- replicateM(mkOptCompareAndSwap(descending));
	Vector#(2, FIFO#(inType)) st3Q <- replicateM(mkFIFO);
	rule stage2;
		let casd1 <- cas2[1].get;
		let td0 = tpl_1(casd1);
		let casd0 <- cas2[0].get;
		let td1 = tpl_1(casd0);
		let td2 = tpl_2(casd1);
		let td3 = tpl_2(casd0);
		cas3[0].put(tuple2(td1, td2));
		st3Q[0].enq(td0);
		st3Q[1].enq(td3);
	endrule
	method Action enq(Vector#(4, inType) data);
		for (Integer i = 0; i < 4; i=i+1 ) begin
			st0Q[i].enq(data[i]);
		end
	endmethod
	method ActionValue#(Vector#(4, inType)) get;
		Vector#(4,inType) outd;
		let td0 = st3Q[0].first;
		st3Q[0].deq;
		outd[0] = td0;
		let casd0 <- cas3[0].get;
		let td1 = tpl_1(casd0);
		outd[1] = td1;
		let td2 = tpl_2(casd0);
		outd[2] = td2;
		let td3 = st3Q[1].first;
		st3Q[1].deq;
		outd[3] = td3;
		return outd;
	endmethod

endmodule
