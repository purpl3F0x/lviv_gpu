# Generate Xilinx floating-point IP simulation models for standalone xsim runs.
# Usage: vivado -mode batch -source gen_sim_ips.tcl -tclargs <out_dir> <part>

set out_dir [file normalize [lindex $argv 0]]
set part [lindex $argv 1]
set script_dir [file dirname [file normalize [info script]]]

file delete -force $out_dir
create_project -force sim_ips $out_dir/proj -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

source $script_dir/floatin_point_units.tcl

generate_target simulation [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -force
export_simulation -of_objects [get_ips] -simulator xsim -directory $out_dir/export -use_ip_compiled_libs -force
close_project

# Stamp consumed by scripts/vivado/xsim.mk; only written when generation succeeded.
set stamp [open $out_dir/.generated w]
puts $stamp $part
close $stamp
