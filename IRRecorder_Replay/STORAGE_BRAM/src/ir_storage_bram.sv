//------------------------------------------------------------------------------
// File: ir_storage_bram.sv
// Zweck:
//   Speicher fuer aufgezeichnete IR-Worte (BRAM-Inferenz).
// Rein:
//   clk, rst_n
//   wr_en, wr_addr, wr_data
//   rd_en, rd_addr
// Raus:
//   rd_data, rd_valid
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_storage_bram #(
  parameter int SLOT_COUNT = IR_SLOT_COUNT
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  wr_en,
  input  ir_slot_t              wr_addr,
  input  ir_word_t              wr_data,

  input  logic                  rd_en,
  input  ir_slot_t              rd_addr,

  output ir_word_t              rd_data,
  output logic                  rd_valid
);

  // TODO: BRAM-Array mit ram_style="block" implementieren.
  // TODO: Schreibe bei wr_en in wr_addr.
  // TODO: Lese bei rd_en aus rd_addr, setze rd_valid fuer 1 Takt.
  // TODO: Reset-Verhalten fuer rd_data/rd_valid definieren.

endmodule
