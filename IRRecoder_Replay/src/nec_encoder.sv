//------------------------------------------------------------------------------
// File: nec_encoder.sv
// Zweck:
//   Wandelt address/command in NEC-Bitstream-Ereignisse um.
// Rein:
//   clk, rst_n
//   start, payload
//   tick_us (Timing-Basis in us)
// Raus:
//   mark_active (1=IR Burst aktiv, 0=Space)
//   frame_active, frame_done, busy, error
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module nec_encoder (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        start,
  input  ir_payload_t payload,
  input  logic        tick_us,

  output logic        mark_active,
  output logic        frame_active,
  output logic        frame_done,
  output logic        busy,
  output logic        error
);

  // TODO: NEC-Frame-Sequencer implementieren (Leader, 32 Bits, Stop).
  // TODO: Bit-Reihenfolge LSB-first sicherstellen.
  // TODO: Optional Repeat-Flag aus payload.flags auswerten.

endmodule
