# Out-of-context constraints for thread_orchestrator on ZCU104 (xczu7ev-ffvc1156-2-e).

# Orchestrator and thread clock: ~700 MHz
create_clock -name clk -period 1.4 [get_ports clk]

# Frontend clock: 300 MHz
create_clock -name in_clk -period 3.333 [get_ports in_clk]


set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks in_clk]
