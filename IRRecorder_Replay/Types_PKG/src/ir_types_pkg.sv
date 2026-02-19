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
  localparam int IR_FRAME_DATA_WIDTH    = 48;
  localparam int IR_FRAME_BITS_WIDTH    = 6;
  localparam int IR_PROTOCOL_ID_WIDTH   = 5;
  localparam int IR_FLAG_WIDTH          = 8;
  localparam int IR_WORD_WIDTH = IR_FRAME_DATA_WIDTH +
                                IR_FRAME_BITS_WIDTH +
                                IR_PROTOCOL_ID_WIDTH +
                                IR_FLAG_WIDTH;
  localparam int IR_SLOT_COUNT = 8;
  localparam int IR_SLOT_WIDTH = 3;

  //--------------------------------------------------------------------------
  // Slot-/Frame-Datentypen
  //--------------------------------------------------------------------------
  typedef logic [66:0] ir_word_t;    // 67-bit storage word
  typedef logic [2:0]  ir_slot_t;    // 8 slots

  typedef struct packed {
    logic [IR_FRAME_DATA_WIDTH-1:0] frame_data;
    logic [IR_FRAME_BITS_WIDTH-1:0] frame_bits;
    logic [IR_PROTOCOL_ID_WIDTH-1:0] protocol_id;
    logic [IR_FLAG_WIDTH-1:0] flags;
  } ir_payload_t;

  //--------------------------------------------------------------------------
  // Feste Bitpositionen fuer transparentes Debugging
  //--------------------------------------------------------------------------
  localparam int IR_FLAGS_LSB = 0;
  localparam int IR_FLAGS_MSB = IR_FLAG_WIDTH - 1;
  localparam int IR_PROTOCOL_ID_LSB = IR_FLAGS_MSB + 1;
  localparam int IR_PROTOCOL_ID_MSB = IR_PROTOCOL_ID_LSB + IR_PROTOCOL_ID_WIDTH - 1;
  localparam int IR_FRAME_BITS_LSB = IR_PROTOCOL_ID_MSB + 1;
  localparam int IR_FRAME_BITS_MSB = IR_FRAME_BITS_LSB + IR_FRAME_BITS_WIDTH - 1;
  localparam int IR_FRAME_DATA_LSB = IR_FRAME_BITS_MSB + 1;
  localparam int IR_FRAME_DATA_MSB = IR_FRAME_DATA_LSB + IR_FRAME_DATA_WIDTH - 1;

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
    ir_pack_word = {p.frame_data, p.frame_bits, p.protocol_id, p.flags};
  endfunction

  function automatic ir_payload_t ir_unpack_word(ir_word_t w);
    ir_payload_t p;
    p.frame_data = w[IR_FRAME_DATA_MSB:IR_FRAME_DATA_LSB];
    p.frame_bits = w[IR_FRAME_BITS_MSB:IR_FRAME_BITS_LSB];
    p.protocol_id = w[IR_PROTOCOL_ID_MSB:IR_PROTOCOL_ID_LSB];
    p.flags = w[IR_FLAGS_MSB:IR_FLAGS_LSB];
    return p;
  endfunction

  function automatic logic ir_is_slot_valid(ir_word_t w);
    ir_is_slot_valid = w[IR_FLAG_VALID_BIT];
  endfunction

  function automatic logic ir_is_repeat(ir_word_t w);
    ir_is_repeat = w[IR_FLAG_REPEAT_BIT];
  endfunction

endpackage
