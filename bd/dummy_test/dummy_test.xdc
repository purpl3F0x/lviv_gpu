# One clock for now: pl_clk0 (100 MHz) drives aclk, frontend_clk and thread_clk, and the PS IP
# constrains it. With separate clocks, declare them asynchronous here; every crossing in gpu_top
# has its own synchroniser:
#   set_clock_groups -asynchronous -group [get_clocks clk_pl_0] -group [get_clocks clk_pl_1] ...
