# Runs of a block design project made by bd_create.tcl. Used by bd.mk.
# Usage: vivado -mode batch -source bd_flow.tcl -tclargs <bd_args.tcl> <stage>
#   synth       synth_1
#   impl        impl_1 up to route_design
#   bitstream   impl_1 up to write_bitstream
#   xsa         bitstream, then the hardware platform (with the bitstream) to $xsa
#   export_bd   the block design, as it is now in the project, back to $bd_tcl
# A run that is already complete and up to date is not run again.

# Re-run this file untraced: Vivado echoes every command of a -source script (the "# ..." lines).
if {![info exists ::untraced]} { set ::untraced 1; source -notrace [info script]; return }

source [lindex $argv 0]
set stage [lindex $argv 1]

if {[info exists ::env(NUMBER_OF_PROCESSORS)]} {
  set ncpu $::env(NUMBER_OF_PROCESSORS)
} else {
  set ncpu [exec nproc]
}
set jobs [expr {min($ncpu, 32)}]
set_param general.maxThreads $jobs

open_project $proj_dir/$proj_name.xpr

proc print_color {color text} {
  puts "\033\[1;${color}m${text}\033\[0m"
}

# The run has finished the given step (or a later one) and nothing it depends on has changed.
proc run_done {run steps} {
  set r [get_runs $run]
  if {[get_property NEEDS_REFRESH $r]} { return 0 }
  return [expr {[get_property STATUS $r] in $steps}]
}

proc launch {run args} {
  global jobs
  set r [get_runs $run]
  # Start over unless the run finished an earlier step and is up to date: a routed impl_1 then
  # goes on to write_bitstream.
  if {[get_property NEEDS_REFRESH $r] || ![string match "*Complete!" [get_property STATUS $r]]} {
    reset_run $run
  }
  launch_runs $run -jobs $jobs {*}$args
  wait_on_run $run
  if {[string match "*ERROR*" [get_property STATUS $r]] || [get_property PROGRESS $r] ne "100%"} {
    print_color 31 "$run failed: [get_property STATUS $r]"
    exit 1
  }
}

proc synth {} {
  if {[run_done synth_1 {{synth_design Complete!}}]} {
    puts "synth_1 is up to date"
  } else {
    launch synth_1
  }
}

proc impl {to_bitstream} {
  synth
  if {$to_bitstream} {
    if {[run_done impl_1 {{write_bitstream Complete!}}]} {
      puts "impl_1 is up to date, with its bitstream"
      return
    }
    launch impl_1 -to_step write_bitstream
  } else {
    if {[run_done impl_1 {{route_design Complete!} {write_bitstream Complete!}}]} {
      puts "impl_1 is up to date"
      return
    }
    launch impl_1
  }
  open_run impl_1
  set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
  set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
  set color [expr {$wns < 0 || $whs < 0 ? 31 : 32}]
  print_color $color "impl_1: WNS $wns ns, WHS $whs ns"
}

switch $stage {
  synth { synth }
  impl { impl 0 }
  bitstream {
    impl 1
    puts "Bitstream: [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit]"
  }
  xsa {
    impl 1
    # Not rewritten for the same bitstream: a newer XSA makes bd.mk update the Vitis platform.
    set bit [lindex [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit] 0]
    if {[file exists $xsa] && [file mtime $xsa] >= [file mtime $bit]} {
      puts "$xsa is up to date"
    } else {
      write_hw_platform -fixed -include_bit -force -file $xsa
      print_color 32 "Wrote $xsa"
    }
  }
  export_bd {
    open_bd_design [get_files *.bd]
    # No IP versions, so the script still builds in a newer Vivado.
    write_bd_tcl -force -include_layout -no_ip_version $bd_tcl
    print_color 32 "Wrote $bd_tcl"
  }
  default {
    puts "unknown stage '$stage': synth, impl, bitstream, xsa or export_bd"
    exit 1
  }
}

close_project
