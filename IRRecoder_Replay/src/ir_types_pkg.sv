//------------------------------------------------------------------------------
// File: ir_types_pkg.sv
// Zweck:
//   Gemeinsame Typen und Parameter fuer Recorder/Replay.
// Rein:
//   Keine Laufzeit-Signale (Package).
// Raus:
//   Typen/Konstanten fuer andere Module.
//------------------------------------------------------------------------------

package ir_types_pkg;

  // TODO: Parameter an Board/Top-Level anpassen.
  parameter int IR_WORD_WIDTH = 32;
  parameter int IR_ADDR_WIDTH = 16;
  parameter int IR_CMD_WIDTH  = 8;
  parameter int IR_FLAG_WIDTH = 8;
  parameter int IR_SLOT_COUNT = 8;
  parameter int IR_SLOT_WIDTH = $clog2(IR_SLOT_COUNT);

  // {addr[15:0], cmd[7:0], flags[7:0]}
  typedef logic [IR_WORD_WIDTH-1:0] ir_word_t;

endpackage
