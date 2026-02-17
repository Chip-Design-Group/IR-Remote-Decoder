# Synopsys Design Constraints (SDC)

# Create clock
create_clock -name clk -period 100.0 [get_ports clk_PAD]

# Set IO delays (Example values)
# set_input_delay  -clock clk 5.0 [get_ports ir_in_PAD]
# set_output_delay -clock clk 5.0 [get_ports uart_tx_PAD]
