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

  //--------------------------------------------------------------------------
  // Versionierter Team-Vertrag
  //--------------------------------------------------------------------------
  localparam int IR_TYPES_PKG_VERSION_MAJOR = 1;
  localparam int IR_TYPES_PKG_VERSION_MINOR = 0;

  //--------------------------------------------------------------------------
  // Globale Breiten/Parameter
  //--------------------------------------------------------------------------
  parameter int IR_WORD_WIDTH = 32;
  parameter int IR_ADDR_WIDTH = 16;
  parameter int IR_CMD_WIDTH  = 8;
  parameter int IR_FLAG_WIDTH = 8;
  parameter int IR_SLOT_COUNT = 8;
  parameter int IR_SLOT_WIDTH = $clog2(IR_SLOT_COUNT);

  //--------------------------------------------------------------------------
  // Slot-/Frame-Datentypen
  // Vertrag fuer alle Module:
  //   IR-Wort = {address[31:16], command[15:8], flags[7:0]}
  //--------------------------------------------------------------------------
  typedef logic [IR_WORD_WIDTH-1:0] ir_word_t;
  typedef logic [IR_SLOT_WIDTH-1:0] ir_slot_t;

  typedef struct packed {
    logic [IR_ADDR_WIDTH-1:0] address; // word[31:16]
    logic [IR_CMD_WIDTH-1:0]  command; // word[15:8]
    logic [IR_FLAG_WIDTH-1:0] flags;   // word[7:0]
  } ir_payload_t;

  //--------------------------------------------------------------------------
  // Feste Bitpositionen fuer transparentes Debugging
  //--------------------------------------------------------------------------
  localparam int IR_FLAGS_LSB = 0;
  localparam int IR_FLAGS_MSB = IR_FLAG_WIDTH - 1;
  localparam int IR_CMD_LSB   = IR_FLAG_WIDTH;
  localparam int IR_CMD_MSB   = IR_CMD_LSB + IR_CMD_WIDTH - 1;
  localparam int IR_ADDR_LSB  = IR_CMD_MSB + 1;
  localparam int IR_ADDR_MSB  = IR_ADDR_LSB + IR_ADDR_WIDTH - 1;

  //--------------------------------------------------------------------------
  // Flag-Bits (flags[7:0])
  //--------------------------------------------------------------------------
  localparam int IR_FLAG_VALID_BIT  = 0; // 1 = Slot enthaelt gueltige Daten
  localparam int IR_FLAG_REPEAT_BIT = 1; // 1 = als NEC Repeat senden
  localparam int IR_FLAG_USER0_BIT  = 2; // frei fuer Erweiterungen
  localparam int IR_FLAG_USER1_BIT  = 3; // frei fuer Erweiterungen
  // bits [7:4] reserviert fuer spaetere Erweiterungen

  localparam logic [IR_FLAG_WIDTH-1:0] IR_FLAGS_DEFAULT = '0;

  //--------------------------------------------------------------------------
  // Statuscodes fuer Recorder/Replay (optional nutzbar)
  //--------------------------------------------------------------------------
  typedef enum logic [1:0] {
    IR_STATUS_OK      = 2'b00,
    IR_STATUS_BUSY    = 2'b01,
    IR_STATUS_INVALID = 2'b10,
    IR_STATUS_TIMEOUT = 2'b11
  } ir_status_t;

  //--------------------------------------------------------------------------
  // Pack-/Unpack-Helfer: EIN Datenvertrag fuer RTL + Tests
  //--------------------------------------------------------------------------
  function automatic ir_word_t ir_pack_word(ir_payload_t p);
    ir_pack_word = {p.address, p.command, p.flags};
  endfunction

  function automatic ir_payload_t ir_unpack_word(ir_word_t w);
    ir_payload_t p;
    p.address = w[IR_ADDR_MSB:IR_ADDR_LSB];
    p.command = w[IR_CMD_MSB:IR_CMD_LSB];
    p.flags   = w[IR_FLAGS_MSB:IR_FLAGS_LSB];
    return p;
  endfunction

  function automatic logic ir_is_slot_valid(ir_word_t w);
    ir_is_slot_valid = w[IR_FLAG_VALID_BIT];
  endfunction

  function automatic logic ir_is_repeat(ir_word_t w);
    ir_is_repeat = w[IR_FLAG_REPEAT_BIT];
  endfunction

endpackage
