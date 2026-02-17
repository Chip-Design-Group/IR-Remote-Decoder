`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Common ASIC chip top for IR decoder + recorder/replay integration.
// This wrapper excludes FPGA-board specifics and disables FPGA clocking primitives.
//------------------------------------------------------------------------------
module ir_recorder_replay_chip_top (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       ir_in,
  input  logic       record_req,
  input  logic       replay_req,
  input  logic [2:0] slot_sel,

  output logic       ir_tx_npn_drive,
  output logic       uart_tx,
  output logic       ld7,
  output logic       ld6,
  output logic       ld5,
  output logic       ld4,
  output logic       ld3,
  output logic       ld2,
  output logic       ld1,
  output logic       ld0,
  output logic       rec_done,
  output logic       rep_done,
  output logic       busy,
  output logic       error
);
  logic ir_led_out_unused;

  ir_recorder_replay_top #(
    .FPGA_CLKING(1'b0)
  ) u_core (
    .clk(clk),
    .rst_n(rst_n),
    .ir_in(ir_in),
    .record_req(record_req),
    .replay_req(replay_req),
    .slot_sel(slot_sel),
    .use_external_decoder_data(1'b0),
    .dec_valid(1'b0),
    .dec_payload(32'h0000_0000),
    .ir_tx_npn_drive(ir_tx_npn_drive),
    .ir_led_out(ir_led_out_unused),
    .uart_tx(uart_tx),
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
endmodule
