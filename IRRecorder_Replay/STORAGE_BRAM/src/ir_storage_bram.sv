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

  // Inferred block RAM for stored IR words.
  (* ram_style = "block" *) ir_word_t mem [0:SLOT_COUNT-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Do not clear BRAM content on reset; only clear read interface state.
      rd_data  <= '0;
      rd_valid <= 1'b0;
    end else begin
      // Default: no read response unless rd_en is asserted in this cycle.
      rd_valid <= 1'b0;

      if (wr_en) begin
        mem[wr_addr] <= wr_data;
      end

      if (rd_en) begin
        rd_data  <= mem[rd_addr];
        rd_valid <= 1'b1;
      end
    end
  end

endmodule
