if [ $# -eq 0 ] 
then
	vivado -mode batch -source /opt/shared/program.tcl -nolog -nojournal
else
	if [ $# -eq 1 ]
	then
		vivado -mode batch -source /opt/shared/program.tcl  -nolog -nojournal -tclargs $1
	else
		vivado -mode batch -source /opt/shared/program.tcl -nolog -nojournal -tclargs $1 $2
	fi
fi
sleep 2
bsrescan
