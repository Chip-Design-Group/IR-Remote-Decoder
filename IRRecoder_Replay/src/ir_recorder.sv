//------------------------------------------------------------------------------
// File: ir_recorder.sv
// Zweck:
//   Uebernimmt dekodierte NEC-Daten und schreibt sie in den Speicher.
// Rein:
//   clk, rst_n
//   record_req, target_slot
//   dec_valid, dec_address[15:0], dec_command[7:0], dec_flags[7:0]
// Raus:
//   mem_wr_en, mem_wr_addr, mem_wr_data
//   busy, done, error
//------------------------------------------------------------------------------

module ir_recorder #(
  parameter int SLOT_COUNT = 8,
  parameter int SLOT_WIDTH = $clog2(SLOT_COUNT)
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  record_req,
  input  logic [SLOT_WIDTH-1:0] target_slot,

  input  logic                  dec_valid,
  input  logic [15:0]           dec_address,
  input  logic [7:0]            dec_command,
  input  logic [7:0]            dec_flags,

  output logic                  mem_wr_en,
  output logic [SLOT_WIDTH-1:0] mem_wr_addr,
  output logic [31:0]           mem_wr_data,

  output logic                  busy,
  output logic                  done,
  output logic                  error
);

  // TODO: Handshake-FSM implementieren (Idle -> WaitValid -> Write -> Done).
  // TODO: Daten packen: {dec_address, dec_command, dec_flags}.
  // TODO: Fehlerfall behandeln (z.B. record_req ohne gueltiges dec_valid Timeout).

endmodule
