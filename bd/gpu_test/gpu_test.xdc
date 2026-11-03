
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_nets gpu_test_i/clk_100]] \
    -group [get_clocks -of_objects [get_nets gpu_test_i/clk_333]] \
    -group [get_clocks -of_objects [get_nets gpu_test_i/clk_500]]
