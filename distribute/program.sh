rm -rf build

tar xzf $BLUEDBM_BINARY_DIR/c.tgz

vivado -mode batch -source program.tcl
