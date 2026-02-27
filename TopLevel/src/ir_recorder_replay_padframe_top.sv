`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Padframe wrapper for ir_recorder_replay_chip_top (IHP SG13G2 IO pads).
//------------------------------------------------------------------------------
module ir_recorder_replay_padframe_top (
  inout wire io_clk_pad,
  inout wire io_rst_n_pad,
  inout wire io_ir_in_pad,

  // ESP32-C3 Software-SPI interface
  inout wire io_spi_clk_pad,
  inout wire io_spi_data_pad,

  inout wire io_ir_tx_npn_drive_pad,
  inout wire io_uart_tx_pad,
  inout wire io_receiving_pad,
  inout wire io_valid_pad,
  inout wire io_recording_pad
);
  wire core_clk;
  wire core_rst_n;
  wire core_ir_in;
  wire core_spi_clk;
  wire core_spi_data;
  wire core_ir_tx_npn_drive;
  wire core_uart_tx;
  wire core_receiving;
  wire core_valid;
  wire core_recording;

  // Dedicated supply pads for core and IO domains.
  // Intentionally left with implicit/unconnected PG pins for synthesis-model
  // compatibility (some IO Verilog views omit explicit iovdd/iovss/vdd/vss ports).
  sg13g2_IOPadVdd   u_vdd_pad   ();
  sg13g2_IOPadVss   u_vss_pad   ();
  sg13g2_IOPadIOVdd u_iovdd_pad ();
  sg13g2_IOPadIOVss u_iovss_pad ();

  // Inputs
  sg13g2_IOPadIn u_pad_clk        (.pad(io_clk_pad),        .p2c(core_clk));
  sg13g2_IOPadIn u_pad_rst_n      (.pad(io_rst_n_pad),      .p2c(core_rst_n));
  sg13g2_IOPadIn u_pad_ir_in      (.pad(io_ir_in_pad),      .p2c(core_ir_in));
  sg13g2_IOPadIn u_pad_spi_clk    (.pad(io_spi_clk_pad),    .p2c(core_spi_clk));
  sg13g2_IOPadIn u_pad_spi_data   (.pad(io_spi_data_pad),   .p2c(core_spi_data));

  // Outputs
  sg13g2_IOPadOut30mA u_pad_ir_tx_npn_drive (.pad(io_ir_tx_npn_drive_pad), .c2p(core_ir_tx_npn_drive));
  sg13g2_IOPadOut30mA u_pad_uart_tx         (.pad(io_uart_tx_pad),         .c2p(core_uart_tx));
  sg13g2_IOPadOut30mA u_pad_receiving       (.pad(io_receiving_pad),       .c2p(core_receiving));
  sg13g2_IOPadOut30mA u_pad_valid           (.pad(io_valid_pad),           .c2p(core_valid));
  sg13g2_IOPadOut30mA u_pad_recording       (.pad(io_recording_pad),       .c2p(core_recording));

  ir_recorder_replay_chip_top u_core (
    .clk(core_clk),
    .rst_n(core_rst_n),
    .ir_in(core_ir_in),
    .spi_clk(core_spi_clk),
    .spi_data(core_spi_data),
    .record_req(1'b0),
    .replay_req(1'b0),
    .slot_sel(6'd0),
    .ir_tx_npn_drive(core_ir_tx_npn_drive),
    .uart_tx(core_uart_tx),
    .receiving(core_receiving),
    .valid(core_valid),
    .recording(core_recording)
  );
endmodule
