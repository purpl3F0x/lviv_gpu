# Create the Vivado project of a block design under bd/<name>/: the RTL, the Xilinx IP of
# xilinx_ips.tcl, the block design (sourced from its Tcl), its wrapper as the top, and the
# constraints. Used by bd.mk.
# Usage: vivado -mode batch -source bd_create.tcl -tclargs <bd_args.tcl>
# bd_args.tcl (written by bd.mk) sets:
#   part board_part proj_dir proj_name sources include_dirs bd_tcl xdc_files

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} { set ::untraced 1; source -notrace [info script]; return }

source [lindex $argv 0]
set script_dir [file dirname [file normalize [info script]]]
set xpr $proj_dir/$proj_name.xpr

create_project -force $proj_name $proj_dir -part $part

if {[catch {
  set_property board_part $board_part [current_project]
  set_property target_language Verilog [current_project]

  add_files -norecurse $sources
  set_property include_dirs $include_dirs [current_fileset]
  # A module reference only sees `include files that are part of the project.
  foreach dir $include_dirs {
    set headers [glob -nocomplain $dir/*.svh]
    if {[llength $headers]} { add_files -norecurse $headers }
  }
  add_files -fileset constrs_1 -norecurse $xdc_files

  # Same IP configuration as the simulation and OOC flows.
  source $script_dir/xilinx_ips.tcl
  update_compile_order -fileset sources_1

  source $bd_tcl
  set bd_file [get_files [current_bd_design].bd]
  make_wrapper -files $bd_file -top -import
  set_property top [current_bd_design]_wrapper [current_fileset]
  update_compile_order -fileset sources_1
} result]} {
  # No half-made project: make would take the .xpr for a finished one.
  puts "ERROR: $result"
  close_project
  file delete -force $xpr
  exit 1
}

puts "Created $xpr"
close_project
