# Open a design checkpoint in the Vivado GUI.
# Usage: vivado -mode gui -source open_dcp.tcl -tclargs <checkpoint.dcp>

open_checkpoint [lindex $argv 0]
