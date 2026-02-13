//------------------------------------------------------------------------------
// File: ir_tx.sv
// Zweck:
//   Erzeugt 38kHz-Traeger und moduliert ihn mit mark_active.
// Rein:
//   clk, rst_n
//   mark_active
// Raus:
//   ir_led_out
//   ready
//------------------------------------------------------------------------------

module ir_tx #(
  parameter int CLK_HZ     = 10_000_000,
  parameter int CARRIER_HZ = 38_000
) (
  input  logic clk,
  input  logic rst_n,

  input  logic mark_active,

  output logic ir_led_out,
  output logic ready
);

  // TODO: Teiler fuer 38kHz implementieren.
  // TODO: Bei mark_active Traeger ausgeben, sonst idle Pegel.
  // TODO: ready definieren (z.B. immer 1 bei einfacher TX-Stufe).

endmodule
