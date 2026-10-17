# Generate Xilinx IP simulation models for standalone xsim runs.
# Usage: vivado -mode batch -source gen_sim_ips.tcl -tclargs <out_dir> <part>

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} { set ::untraced 1; source -notrace [info script]; return }

set out_dir [file normalize [lindex $argv 0]]
set part [lindex $argv 1]
set script_dir [file dirname [file normalize [info script]]]

file delete -force $out_dir
create_project -force sim_ips $out_dir/proj -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

source $script_dir/xilinx_ips.tcl

generate_target simulation [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -force
export_simulation -of_objects [get_ips] -simulator xsim -directory $out_dir/export -use_ip_compiled_libs -force
close_project

# File lists for xsim.mk, so make never has to glob files created earlier in the same run
# (GNU make on Linux caches directory listings and would miss them).
set vhdl_files [lsort [glob $out_dir/proj/sim_ips.gen/sources_1/ip/*/sim/*.vhd]]
set prj [open $out_dir/ip_vhdl.prj w]
foreach vhdl_file $vhdl_files {
  puts $prj "vhdl xil_defaultlib \"$vhdl_file\""
}
close $prj

# The xelab -L options live in elab.opt on Windows but are inlined in <ip>.sh on Linux,
# so scan every exported xsim file.
set ip_libs {}
foreach export_file [glob -nocomplain -types f $out_dir/export/*/xsim/*] {
  set opt_file [open $export_file r]
  foreach {match lib} [regexp -all -inline {\-L\s+([A-Za-z0-9_]+)} [read $opt_file]] {
    lappend ip_libs $lib
  }
  close $opt_file
}
if {[llength $ip_libs] == 0} {
  error "no xelab -L libraries found in $out_dir/export/*/xsim"
}
set libs_file [open $out_dir/ip_libs.txt w]
puts $libs_file [lsort -unique $ip_libs]
close $libs_file

# Stamp consumed by scripts/vivado/xsim.mk; only written when generation succeeded.
set stamp [open $out_dir/.generated w]
puts $stamp $part
close $stamp
