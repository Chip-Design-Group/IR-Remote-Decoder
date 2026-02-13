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
//   enc_start, enc_address, enc_command, enc_flags
//   busy, done, error
//------------------------------------------------------------------------------

module ir_replay_fsm #(
  parameter int SLOT_COUNT = 8,
  parameter int SLOT_WIDTH = $clog2(SLOT_COUNT)
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  replay_req,
  input  logic [SLOT_WIDTH-1:0] target_slot,

  output logic                  mem_rd_en,
  output logic [SLOT_WIDTH-1:0] mem_rd_addr,
  input  logic [31:0]           mem_rd_data,
  input  logic                  mem_rd_valid,

  output logic                  enc_start,
  output logic [15:0]           enc_address,
  output logic [7:0]            enc_command,
  output logic [7:0]            enc_flags,
  input  logic                  enc_ready,
  input  logic                  tx_ready,

  output logic                  busy,
  output logic                  done,
  output logic                  error
);

  // TODO: FSM fuer Replay bauen (Idle -> Read -> DecodeWord -> StartEncode -> Done).
  // TODO: mem_rd_data entpacken: addr/cmd/flags.
  // TODO: Start nur wenn enc_ready && tx_ready.

endmodule
