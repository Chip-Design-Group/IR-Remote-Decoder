`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Board wrapper for Arty A7-100T
// Exposes only real board I/O and ties off debug/config ports of the core.
//------------------------------------------------------------------------------
module ir_recorder_replay_arty_top (
  input  logic clk_PAD,
  input  logic rst_n_PAD,
  input  logic ir_in_PAD,
  input  logic btn_record_PAD,
  input  logic btn_replay_PAD,

  output logic uart_tx_PAD,
  output logic ir_tx_PAD,
  output logic led4_PAD,
  output logic led5_PAD,
  output logic led6_PAD,
  output logic led7_PAD
);

  logic ld7, ld6, ld5, ld4, ld3, ld2, ld1, ld0;
  logic rec_done, rep_done, busy, error;
  logic ir_led_alias_unused;

  ir_recorder_replay_top u_core (
    .clk(clk_PAD),
    .rst_n(rst_n_PAD),
    .ir_in(ir_in_PAD),
    .record_req(btn_record_PAD),
    .replay_req(btn_replay_PAD),
    .slot_sel(3'b000), // MVP: fixed slot 0 on hardware
    .use_external_decoder_data(1'b0),
    .dec_valid(1'b0),
    .dec_payload(32'h0000_0000),
    .ir_tx_npn_drive(ir_tx_PAD),
    .ir_led_out(ir_led_alias_unused),
    .uart_tx(uart_tx_PAD),
    .ld7(ld7),
    .ld6(ld6),
    .ld5(ld5),
    .ld4(ld4),
    .ld3(ld3),
    .ld2(ld2),
    .ld1(ld1),
    .ld0(ld0),
    .rec_done(rec_done),
    .rep_done(rep_done),
    .busy(busy),
    .error(error)
  );

  // Keep the user-requested semantics on visible board LEDs.
  assign led7_PAD = ld7;
  assign led6_PAD = ld6;
  assign led5_PAD = ld5;
  assign led4_PAD = ld4;

endmodule

