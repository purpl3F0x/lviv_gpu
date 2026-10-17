# Open a design checkpoint in the Vivado GUI.
# Usage: vivado -mode gui -source open_dcp.tcl -tclargs <checkpoint.dcp>

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} { set ::untraced 1; source -notrace [info script]; return }

open_checkpoint [lindex $argv 0]
