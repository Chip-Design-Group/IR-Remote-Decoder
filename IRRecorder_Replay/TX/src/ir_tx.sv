//------------------------------------------------------------------------------
// File: ir_tx.sv
// Zweck:
//   Erzeugt 38kHz-Traeger und moduliert ihn mit mark_active.
//   Ausgang ist fuer eine NPN-Treiberstufe gedacht (Low-Side-IR-LED-Treiber).
// Rein:
//   clk, rst_n
//   mark_active
// Raus:
//   ir_npn_drive
//   ir_led_out
//   ready
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_tx #(
  parameter int CLK_HZ     = 10_000_000,
  parameter int CARRIER_HZ = 38_000
) (
  input  logic clk,
  input  logic rst_n,

  input  logic mark_active,

  output logic ir_npn_drive,
  output logic ir_led_out,
  output logic ready
);

  // TODO: Teiler fuer 38kHz implementieren.
  // TODO: Bei mark_active Traeger auf ir_npn_drive ausgeben, sonst idle Pegel.
  //       (ir_npn_drive -> Basiswiderstand -> NPN-Basis; LED extern an Kollektor).
  // TODO: ready definieren (z.B. immer 1 bei einfacher TX-Stufe).
  // NOTE: ir_led_out bleibt als Kompatibilitaets-Alias erhalten.
  assign ir_led_out = ir_npn_drive;

endmodule
