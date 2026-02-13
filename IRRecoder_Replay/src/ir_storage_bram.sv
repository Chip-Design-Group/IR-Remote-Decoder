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

module ir_storage_bram #(
  parameter int WORD_WIDTH = 32,
  parameter int SLOT_COUNT = 8,
  parameter int ADDR_WIDTH = $clog2(SLOT_COUNT)
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  wr_en,
  input  logic [ADDR_WIDTH-1:0] wr_addr,
  input  logic [WORD_WIDTH-1:0] wr_data,

  input  logic                  rd_en,
  input  logic [ADDR_WIDTH-1:0] rd_addr,

  output logic [WORD_WIDTH-1:0] rd_data,
  output logic                  rd_valid
);

  // TODO: BRAM-Array mit ram_style="block" implementieren.
  // TODO: Schreibe bei wr_en in wr_addr.
  // TODO: Lese bei rd_en aus rd_addr, setze rd_valid fuer 1 Takt.
  // TODO: Reset-Verhalten fuer rd_data/rd_valid definieren.

endmodule
