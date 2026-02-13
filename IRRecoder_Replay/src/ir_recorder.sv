//------------------------------------------------------------------------------
// File: ir_recorder.sv
// Zweck:
//   Uebernimmt dekodierte NEC-Daten und schreibt sie in den Speicher.
// Rein:
//   clk, rst_n
//   record_req, target_slot
//   dec_valid, dec_payload
// Raus:
//   mem_wr_en, mem_wr_addr, mem_wr_data
//   busy, done, error
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_recorder #(
  parameter int SLOT_COUNT = IR_SLOT_COUNT
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  record_req,
  input  ir_slot_t              target_slot,

  input  logic                  dec_valid,
  input  ir_payload_t           dec_payload,

  output logic                  mem_wr_en,
  output ir_slot_t              mem_wr_addr,
  output ir_word_t              mem_wr_data,

  output logic                  busy,
  output logic                  done,
  output logic                  error
);

  // TODO: Handshake-FSM implementieren (Idle -> WaitValid -> Write -> Done).
  // TODO: Daten packen mit ir_pack_word(dec_payload).
  // TODO: Fehlerfall behandeln (z.B. record_req ohne gueltiges dec_valid Timeout).

endmodule
