create_clock -name core_clk -period 100.000 [get_ports io_clk_pad]
set_propagated_clock [get_clocks core_clk]
set_clock_uncertainty 0.25 [get_clocks core_clk]
set_clock_transition 0.15 [get_clocks core_clk]
