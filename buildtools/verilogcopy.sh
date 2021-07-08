#!/bin/bash

VFILES="
	SyncResetA.v
	SyncRegister.v
	SyncHandshake.v
	MakeReset0.v
	MakeResetA.v
	SizedFIFO.v
	Counter.v
	TriState.v
	FIFOL1.v
	FIFOL2.v
	FIFO1.v
	FIFO2.v
	ResetInverter.v
	SyncFIFO.v
	ClockDiv.v
	ResetEither.v
	MakeReset.v
	SyncReset0.v
	BRAM2.v
	SyncWire.v
	"

CURDIR=`pwd`
cd $BLUESPECDIR/Verilog;
#cp *.v $CURDIR/

for VFILE in $VFILES ;
do
	echo $VFILE
	cp $VFILE $CURDIR/
done
