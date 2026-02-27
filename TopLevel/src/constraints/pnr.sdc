create_clock -name core_clk -period 100.000 [get_ports io_clk_pad]
set_propagated_clock [get_clocks core_clk]
set_clock_uncertainty 0.25 [get_clocks core_clk]
set_clock_transition 0.15 [get_clocks core_clk]

# Padframe top has only these inout pads; removed stale record/replay/slot pads.
set_input_delay 20.0 -clock [get_clocks core_clk] [get_ports {io_rst_n_pad io_ir_in_pad io_spi_clk_pad io_spi_data_pad io_ir_tx_npn_drive_pad io_uart_tx_pad io_receiving_pad io_valid_pad io_recording_pad}]
set_output_delay 20.0 -clock [get_clocks core_clk] [get_ports {io_rst_n_pad io_ir_in_pad io_spi_clk_pad io_spi_data_pad io_ir_tx_npn_drive_pad io_uart_tx_pad io_receiving_pad io_valid_pad io_recording_pad}]

# External status/tx pads are slow, highly loaded off-chip nets.
# Relax transition specifically on output-facing pad ports.
set_max_transition 1.30 [get_ports {io_ir_tx_npn_drive_pad io_uart_tx_pad io_receiving_pad io_valid_pad io_recording_pad}]
