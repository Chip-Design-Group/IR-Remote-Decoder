//------------------------------------------------------------------------------
// File: ir_recorder_replay_top.sv
// Zweck:
//   Verdrahtet Recorder, BRAM, Replay-FSM, Encoder und TX.
// Rein:
//   clk, rst_n
//   record_req, replay_req, slot_sel
//   dec_valid, dec_address, dec_command, dec_flags
// Raus:
//   ir_led_out
//   status_signale: rec_done, rep_done, busy, error
//------------------------------------------------------------------------------

module ir_recorder_replay_top #(
  parameter int SLOT_COUNT = 8,
  parameter int SLOT_WIDTH = $clog2(SLOT_COUNT)
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  record_req,
  input  logic                  replay_req,
  input  logic [SLOT_WIDTH-1:0] slot_sel,

  input  logic                  dec_valid,
  input  logic [15:0]           dec_address,
  input  logic [7:0]            dec_command,
  input  logic [7:0]            dec_flags,

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
