# Out-of-context constraints for raster_frontend on ZCU104 (xczu7ev-ffvc1156-2-e).

# Core clock: 700 MHz
create_clock -name clk -period 1.429 [get_ports clk]

# APB clock: 100 MHz
create_clock -name apb_clk -period 10.000 [get_ports apb_clk]

# The clocks are unrelated; APBFrontendRegs crosses between them with its own synchronisers.
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks apb_clk]
