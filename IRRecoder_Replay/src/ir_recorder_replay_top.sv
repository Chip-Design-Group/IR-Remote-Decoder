//------------------------------------------------------------------------------
// File: ir_recorder_replay_top.sv
// Zweck:
//   Verdrahtet Recorder, BRAM, Replay-FSM, Encoder und TX.
// Rein:
//   clk, rst_n
//   record_req, replay_req, slot_sel
//   dec_valid, dec_payload
// Raus:
//   ir_led_out
//   status_signale: rec_done, rep_done, busy, error
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_recorder_replay_top #(
  parameter int SLOT_COUNT = IR_SLOT_COUNT
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  record_req,
  input  logic                  replay_req,
  input  ir_slot_t              slot_sel,

  input  logic                  dec_valid,
  input  ir_payload_t           dec_payload,

  output logic                  ir_led_out,
  output logic                  rec_done,
  output logic                  rep_done,
  output logic                  busy,
  output logic                  error
);

  // TODO: Interne Busse/Signale definieren.
  // TODO: Submodule instanziieren und korrekt verbinden.
  // TODO: Statusaggregation (busy/error) festlegen.

endmodule
