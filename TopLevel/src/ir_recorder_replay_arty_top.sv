`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Board wrapper for Arty A7-100T
// Maps the 4 board buttons directly to 4 storage slots:
// - short press: replay slot
// - long press : record slot
//------------------------------------------------------------------------------
module ir_recorder_replay_arty_top (
  input  logic clk_PAD,
  input  logic rst_n_PAD,
  input  logic ir_in_PAD,
  input  logic btn0_PAD,
  input  logic btn1_PAD,
  input  logic btn2_PAD,
  input  logic btn3_PAD,

  output logic uart_tx_PAD,
  output logic ir_tx_PAD,
  output logic led4_PAD,
  output logic led5_PAD,
  output logic led6_PAD,
  output logic led7_PAD
);

  localparam int LONG_PRESS_CYCLES = 60_000_000; // 0.6s @ 100MHz
  localparam int REQ_PULSE_CYCLES  = 200_000;    // 2ms @ 100MHz
  localparam int BTN_CNT_W = $clog2(LONG_PRESS_CYCLES + 1);
  localparam int REQ_CNT_W = $clog2(REQ_PULSE_CYCLES + 1);

  logic ld7, ld6, ld5, ld4, ld3, ld2, ld1, ld0;
  logic rec_done, rep_done, busy, error;
  logic ir_led_alias_unused;

  logic [3:0] btn_async;
  logic [3:0] btn_sync_q, btn_sync_qq;
  logic [3:0] btn_prev_q;
  logic [BTN_CNT_W-1:0] press_cnt_q [0:3];

  logic [2:0] slot_sel_q;
  logic record_req_q, replay_req_q;
  logic record_pending_q, replay_pending_q;
  logic [2:0] record_slot_q, replay_slot_q;
  logic [REQ_CNT_W-1:0] req_cnt_q;

  integer i;

  assign btn_async = {btn3_PAD, btn2_PAD, btn1_PAD, btn0_PAD};

  // Synchronize buttons into clk_PAD domain.
  always_ff @(posedge clk_PAD or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      btn_sync_q  <= '0;
      btn_sync_qq <= '0;
      btn_prev_q  <= '0;
    end else begin
      btn_sync_q  <= btn_async;
      btn_sync_qq <= btn_sync_q;
      btn_prev_q  <= btn_sync_qq;
    end
  end

  // Press classification and request generation.
  always_ff @(posedge clk_PAD or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      for (i = 0; i < 4; i = i + 1) begin
        press_cnt_q[i] <= '0;
      end
      slot_sel_q       <= 3'd0;
      record_req_q     <= 1'b0;
      replay_req_q     <= 1'b0;
      record_pending_q <= 1'b0;
      replay_pending_q <= 1'b0;
      record_slot_q    <= 3'd0;
      replay_slot_q    <= 3'd0;
      req_cnt_q        <= '0;
    end else begin
      record_req_q <= 1'b0;
      replay_req_q <= 1'b0;

      // Measure press length, classify on falling edge.
      for (i = 0; i < 4; i = i + 1) begin
        if (btn_sync_qq[i]) begin
          if (press_cnt_q[i] < LONG_PRESS_CYCLES) begin
            press_cnt_q[i] <= press_cnt_q[i] + 1'b1;
          end
        end

        if (!btn_sync_qq[i] && btn_prev_q[i]) begin
          if (press_cnt_q[i] >= LONG_PRESS_CYCLES) begin
            record_pending_q <= 1'b1;
            record_slot_q    <= i[2:0];
          end else begin
            replay_pending_q <= 1'b1;
            replay_slot_q    <= i[2:0];
          end
          press_cnt_q[i] <= '0;
        end else if (!btn_sync_qq[i]) begin
          press_cnt_q[i] <= '0;
        end
      end

      // Stretch one request pulse so core edge detection always sees it.
      if (req_cnt_q != '0) begin
        req_cnt_q <= req_cnt_q - 1'b1;
        if (record_pending_q) begin
          slot_sel_q   <= record_slot_q;
          record_req_q <= 1'b1;
        end else if (replay_pending_q) begin
          slot_sel_q   <= replay_slot_q;
          replay_req_q <= 1'b1;
        end
      end else if (!busy) begin
        if (record_pending_q) begin
          slot_sel_q   <= record_slot_q;
          record_req_q <= 1'b1;
          req_cnt_q    <= REQ_PULSE_CYCLES - 1;
        end else if (replay_pending_q) begin
          slot_sel_q   <= replay_slot_q;
          replay_req_q <= 1'b1;
          req_cnt_q    <= REQ_PULSE_CYCLES - 1;
        end
      end

      // Clear pending after pulse completion.
      if ((req_cnt_q == 1) && record_pending_q) begin
        record_pending_q <= 1'b0;
      end
      if ((req_cnt_q == 1) && replay_pending_q) begin
        replay_pending_q <= 1'b0;
      end
    end
  end

  ir_recorder_replay_top u_core (
    .clk(clk_PAD),
    .rst_n(rst_n_PAD),
    .ir_in(ir_in_PAD),
    .record_req(record_req_q),
    .replay_req(replay_req_q),
    .slot_sel(slot_sel_q),
    .use_external_decoder_data(1'b0),
    .dec_valid(1'b0),
    .dec_payload(32'h0000_0000),
    .ir_tx_npn_drive(ir_tx_PAD),
    .ir_led_out(ir_led_alias_unused),
    .uart_tx(uart_tx_PAD),
    .ld7(ld7),
    .ld6(ld6),
    .ld5(ld5),
    .ld4(ld4),
    .ld3(ld3),
    .ld2(ld2),
    .ld1(ld1),
    .ld0(ld0),
    .rec_done(rec_done),
    .rep_done(rep_done),
    .busy(busy),
    .error(error)
  );

  // Keep visible board LED semantics.
  assign led7_PAD = ld7;
  assign led6_PAD = ld6;
  assign led5_PAD = ld5;
  assign led4_PAD = ld4;

endmodule

