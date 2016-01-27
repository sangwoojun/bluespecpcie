#!/bin/bash

./bsim/obj/bsim &
export BDBM_BSIM_PID=$!
echo "running sw"
echo $BDBM_BSIM_PID
sleep 1
../sw/obj/bsim
kill -9 $BDBM_BSIM_PID
