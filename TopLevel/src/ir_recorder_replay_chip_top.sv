`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Common ASIC chip top for IR decoder + recorder/replay integration.
// This wrapper excludes FPGA-board specifics and disables FPGA clocking primitives.
//------------------------------------------------------------------------------
module ir_recorder_replay_chip_top (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       ir_in,
  input  logic       spi_clk,
  input  logic       spi_data,
  input  logic       record_req,
  input  logic       replay_req,
  input  logic [5:0] slot_sel,  // [5:4]=remote_id (0..3), [3:0]=slot_num (0..9)

  output logic       ir_tx_npn_drive,
  output logic       uart_tx,
  // User requested optimization: expose activity signals, remove handshake signals to save pins
  output logic       receiving,
  output logic       valid,
  output logic       recording
);

  logic ir_led_out_unused;
  logic rec_done_unused;
  logic rep_done_unused;
  logic busy_unused;
  logic error_unused;
  
  // Internal status signals
  logic stat_receiving;
  logic stat_code_valid;
  logic stat_record_active;
  logic stat_uart_active;
  logic stat_error;
  logic esp_replay_req;
  logic esp_record_req;
  logic [5:0] esp_slot_addr;
  logic combined_record_req;
  logic combined_replay_req;
  logic [5:0] combined_slot_sel;

  esp32_spi_receiver u_esp32_spi (
    .clk        (clk),
    .rst_n      (rst_n),
    .spi_clk_in (spi_clk),
    .spi_data_in(spi_data),
    .replay_req (esp_replay_req),
    .record_req (esp_record_req),
    .slot_addr  (esp_slot_addr)
  );

  // External pad requests remain supported; ESP commands are ORed in.
  assign combined_record_req = record_req | esp_record_req;
  assign combined_replay_req = replay_req | esp_replay_req;
  assign combined_slot_sel   = (esp_record_req | esp_replay_req) ? esp_slot_addr : slot_sel;

  ir_recorder_replay_top #(
    .CORE_CLK_HZ(10_000_000) // Default core clock assumption for ASIC integration
  ) u_core (
    .clk(clk),
    .rst_n(rst_n),
    .ir_in(ir_in),
    .record_req(combined_record_req),
    .replay_req(combined_replay_req),
    .slot_sel(combined_slot_sel),
    .use_external_decoder_data(1'b0),
    .dec_valid(1'b0),
    .dec_payload(32'h0000_0000),
    .ir_tx_npn_drive(ir_tx_npn_drive),
    .ir_led_out(ir_led_out_unused),
    .uart_tx(uart_tx),
    .stat_receiving(stat_receiving),
    .stat_code_valid(stat_code_valid),
    .stat_record_active(stat_record_active),
    .stat_uart_active(stat_uart_active),
    .stat_error(stat_error),
    .rec_done(rec_done_unused),
    .rep_done(rep_done_unused),
    .busy(busy_unused),
    .error(error_unused)
  );

  // Map requested status to output pins
  assign receiving = stat_receiving;
  assign valid     = stat_code_valid;
  assign recording = stat_record_active;

endmodule
