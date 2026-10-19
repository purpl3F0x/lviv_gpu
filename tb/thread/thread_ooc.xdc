# Out-of-context constraints for thread on ZCU104 (xczu7ev-ffvc1156-2-e).

# Thread clock: ~667 MHz
create_clock -name clk -period 1.5 [get_ports clk]

# APB clock: 100 MHz
create_clock -name apb_clk -period 10.000 [get_ports apb_clk]

# The clocks are unrelated; ApbThreadRegs crosses between them with its own synchronisers.
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks apb_clk]
