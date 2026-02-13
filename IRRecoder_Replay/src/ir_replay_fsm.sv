//------------------------------------------------------------------------------
// File: ir_replay_fsm.sv
// Zweck:
//   Liest einen Slot aus dem Speicher und startet die NEC-Sende-Kette.
// Rein:
//   clk, rst_n
//   replay_req, target_slot
//   mem_rd_data, mem_rd_valid
//   enc_ready, tx_ready
// Raus:
//   mem_rd_en, mem_rd_addr
//   enc_start, enc_payload
//   busy, done, error
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_replay_fsm #(
  parameter int SLOT_COUNT = IR_SLOT_COUNT
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  replay_req,
  input  ir_slot_t              target_slot,

  output logic                  mem_rd_en,
  output ir_slot_t              mem_rd_addr,
  input  ir_word_t              mem_rd_data,
  input  logic                  mem_rd_valid,

  output logic                  enc_start,
  output ir_payload_t           enc_payload,
  input  logic                  enc_ready,
  input  logic                  tx_ready,

  output logic                  busy,
  output logic                  done,
  output logic                  error
);

  // TODO: FSM fuer Replay bauen (Idle -> Read -> DecodeWord -> StartEncode -> Done).
  // TODO: mem_rd_data mit ir_unpack_word(...) entpacken.
  // TODO: Start nur wenn enc_ready && tx_ready.

endmodule
