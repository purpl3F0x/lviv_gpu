# Elaborate one module (RTL analysis, as in "Open Elaborated Design") and export its top-level
# schematic to SVG.
# Usage: vivado -mode gui -source schematic.tcl -tclargs <schematic_args.tcl>
# schematic_args.tcl (written by the root Makefile) sets:
#   part top proj_dir svg sources include_dirs
# show_schematic and write_schematic need the GUI, so this runs in GUI mode and exits when done.

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} { set ::untraced 1; source -notrace [info script]; return }

source [lindex $argv 0]
set script_dir [file dirname [file normalize [info script]]]

if {[catch {
  create_project -force schematic_$top $proj_dir -part $part
  set_property target_language Verilog [current_project]
  add_files -norecurse $sources
  set_property include_dirs $include_dirs [current_fileset]
  set_property top $top [current_fileset]

  # The Xilinx IP is elaborated inline with the design, as in ooc_flow.tcl.
  source $script_dir/xilinx_ips.tcl
  set_property generate_synth_checkpoint false [get_files -of_objects [get_filesets sources_1] *.xci]
  generate_target synthesis [get_ips]

  synth_design -rtl -rtl_skip_mlo -top $top -part $part -name rtl_1
  show_schematic [concat [get_cells] [get_ports] [get_nets]]
  write_schematic -force -format svg -orientation landscape $svg
} result]} {
  puts "ERROR: $result"
  exit 1
}
exit
