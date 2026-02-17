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

  localparam int HALF_PERIOD_CLKS = ((CLK_HZ / CARRIER_HZ) > 1) ? (CLK_HZ / (2 * CARRIER_HZ)) : 1;
  localparam int DIV_W = (HALF_PERIOD_CLKS > 1) ? $clog2(HALF_PERIOD_CLKS) : 1;

  logic [DIV_W-1:0] div_cnt_q;
  logic             carrier_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_cnt_q     <= '0;
      carrier_q     <= 1'b0;
      ir_npn_drive  <= 1'b0;
      ready         <= 1'b1;
    end else begin
      ready <= 1'b1;

      if (mark_active) begin
        if (div_cnt_q == HALF_PERIOD_CLKS - 1) begin
          div_cnt_q <= '0;
          carrier_q <= ~carrier_q;
        end else begin
          div_cnt_q <= div_cnt_q + 1'b1;
        end
        ir_npn_drive <= carrier_q;
      end else begin
        div_cnt_q    <= '0;
        carrier_q    <= 1'b0;
        ir_npn_drive <= 1'b0;
      end
    end
  end

  assign ir_led_out = ir_npn_drive;

endmodule
