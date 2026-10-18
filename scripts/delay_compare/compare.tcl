# Synthesizes delay_pipe (shift registers) and delay_pipe_fifo (dual and single pointer) out of context
# for every WIDTHxSTAGES config and prints their utilization.
# Usage: vivado -mode batch -source compare.tcl -tclargs <args.tcl>
# args.tcl (written by the Makefile) sets: part period in_reg configs sources out_dir

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} {set ::untraced 1; source -notrace [info script]; return}

source [lindex $argv 0]
file mkdir $out_dir

set xdc $out_dir/clk.xdc
set fh [open $xdc w]
puts $fh "create_clock -name clk -period $period \[get_ports clk\]"
close $fh

# name top generics
set impls [list \
  [list pipe delay_pipe_top {}] \
  [list dual delay_pipe_fifo [list IN_REG=$in_reg PTR_MODE=2]] \
  [list single delay_pipe_fifo [list IN_REG=$in_reg PTR_MODE=1]]]

proc util {rpt pattern} {
  set n 0
  regexp "$pattern\\s*\\|\\s*(\\d+)" $rpt -> n
  return $n
}

set rows {}
foreach cfg $configs {
  lassign [split $cfg x] width stages
  foreach impl $impls {
    lassign $impl name top generics
    read_verilog -sv $sources
    read_xdc $xdc
    set args [list -generic WIDTH=$width -generic STAGES=$stages]
    foreach g $generics {lappend args -generic $g}
    synth_design -top $top -part $part -mode out_of_context {*}$args

    set rpt [report_utilization -return_string]
    set refs [get_property REF_NAME [get_cells -quiet -hier -filter {IS_PRIMITIVE && (REF_NAME =~ RAM* || REF_NAME =~ SRL*)}]]
    set prims {}
    foreach r [lsort -unique $refs] {lappend prims "$r=[llength [lsearch -all $refs $r]]"}
    lappend rows [list $width $stages $name \
      [util $rpt {CLB LUTs\*?}] [util $rpt {LUT as Logic}] [util $rpt {LUT as Distributed RAM}] \
      [util $rpt {LUT as Shift Register}] [util $rpt {CLB Registers}] \
      [format %.3f [get_property SLACK [get_timing_paths -max_paths 1 -setup]]] [join $prims " "]]
    close_design
  }
}

set header {WIDTH STAGES IMPL LUT LOGIC LUTRAM SRL FF WNS PRIMITIVES}
set fh [open $out_dir/results.csv w]
puts $fh [join $header ,]
foreach row $rows {puts $fh [join $row ,]}
close $fh

set fmt "%-6s %-6s %-7s %-6s %-6s %-7s %-6s %-6s %-7s %s"
puts ""
puts "Delay line utilization on $part (pipe = delay_pipe, dual/single = delay_pipe_fifo IN_REG=$in_reg),\
    synth WNS at $period ns"
puts [format $fmt {*}$header]
foreach row $rows {puts [format $fmt {*}$row]}
puts "\nCSV: $out_dir/results.csv"
