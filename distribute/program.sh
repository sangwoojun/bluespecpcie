if [ $# -eq 0 ] 
then
	vivado -mode batch -source /opt/shared/program.tcl -nolog -nojournal
else
	vivado -mode batch -source /opt/shared/program.tcl -tclargs $1 -nolog -nojournal
fi
sleep 2
bsrescan
