# Out-of-context constraints for raster_core on ZCU104 (xczu7ev-ffvc1156-2-e).

# Frontend clock: 300 MHz
create_clock -name frontend_clk -period 3.333 [get_ports frontend_clk]

# Thread clock (orchestrator and threads): 600 MHz
create_clock -name thread_clk -period 1.667 [get_ports thread_clk]

# APB clock: 150 MHz
create_clock -name apb_clk -period 6.667 [get_ports apb_clk]

# The clocks are unrelated; the orchestrator's input FIFO and the APB register blocks cross between
# them with their own synchronisers.
set_clock_groups -asynchronous \
    -group [get_clocks frontend_clk] \
    -group [get_clocks thread_clk] \
    -group [get_clocks apb_clk]
