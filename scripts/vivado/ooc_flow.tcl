# Out-of-context synthesis and/or implementation using the real Xilinx IP.
# Usage: vivado -mode batch -source ooc_flow.tcl -tclargs <ooc_args.tcl>
# ooc_args.tcl (written by the calling Makefile) sets:
#   part top out_dir xdc_files sources include_dirs
#   stages   any of {synth impl}; impl without synth starts from the existing synth checkpoint

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} { set ::untraced 1; source -notrace [info script]; return }

set flow_start [clock seconds]
source [lindex $argv 0]
set script_dir [file dirname [file normalize [info script]]]

set synth_dcp $out_dir/${top}_synth.dcp
set routed_dcp $out_dir/${top}_routed.dcp
file mkdir $out_dir/reports

proc elapsed {start} {
  return [clock format [expr {[clock seconds] - $start}] -format %H:%M:%S -gmt 1]
}
proc print_color {color text} {
  puts "\033\[1;${color}m${text}\033\[0m"
}
proc worst_slack {kind} {
  return [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -$kind]]
}

set summary {}

if {"synth" in $stages} {
  set start [clock seconds]
  # Never leave a stale checkpoint behind if this run fails.
  file delete -force $synth_dcp

  create_project -force synth_$top $out_dir/proj -part $part
  set_property target_language Verilog [current_project]
  add_files -norecurse $sources
  set_property include_dirs $include_dirs [current_fileset]
  set_property top $top [current_fileset]
  add_files -fileset constrs_1 -norecurse $xdc_files

  # Same IP configuration as the simulation flow; synthesised inline with the design.
  source $script_dir/xilinx_ips.tcl
  set_property generate_synth_checkpoint false [get_files -of_objects [get_filesets sources_1] *.xci]
  generate_target all [get_ips]

  synth_design -top $top -part $part -mode out_of_context

  report_timing_summary -max_paths 20 -file $out_dir/reports/synth_timing_summary.rpt
  report_utilization -file $out_dir/reports/synth_utilization.rpt
  report_utilization -hierarchical -file $out_dir/reports/synth_utilization_hier.rpt
  report_clock_interaction -file $out_dir/reports/synth_clock_interaction.rpt
  report_cdc -details -file $out_dir/reports/synth_cdc.rpt
  write_checkpoint -force $synth_dcp

  lappend summary [list "Synthesis" [elapsed $start] "WNS [worst_slack setup] ns"]
} elseif {"impl" in $stages} {
  open_checkpoint $synth_dcp
}

if {"impl" in $stages} {
  set start [clock seconds]
  file delete -force $routed_dcp

  opt_design
  place_design
  phys_opt_design
  route_design

  report_timing_summary -max_paths 20 -file $out_dir/reports/impl_timing_summary.rpt
  report_utilization -file $out_dir/reports/impl_utilization.rpt
  report_utilization -hierarchical -file $out_dir/reports/impl_utilization_hier.rpt
  report_clock_interaction -file $out_dir/reports/impl_clock_interaction.rpt
  report_cdc -details -file $out_dir/reports/impl_cdc.rpt
  report_route_status -file $out_dir/reports/impl_route_status.rpt
  write_checkpoint -force $routed_dcp

  lappend summary [list "Implementation" [elapsed $start] "WNS [worst_slack setup] ns, WHS [worst_slack hold] ns"]
}

puts ""
print_color 36 "OOC $top on $part (reports in $out_dir/reports)"
foreach entry $summary {
  lassign $entry stage time result
  print_color 32 [format "  %-15s %s   %s" $stage $time $result]
}
print_color 33 [format "  %-15s %s" "Total" [elapsed $flow_start]]
puts ""
