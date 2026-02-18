`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Board wrapper for Arty A7-100T
// Exposes only real board I/O and ties off debug/config ports of the core.
// Incorporates clock generation (100MHz -> 10MHz) and debug LED logic.
//------------------------------------------------------------------------------
module ir_recorder_replay_arty_top (
  input  logic clk_PAD,
  input  logic rst_n_PAD,
  input  logic ir_in_PAD,
  input  logic btn_record_PAD,
  input  logic btn_replay_PAD,

  output logic uart_tx_PAD,
  output logic ir_tx_PAD,
  output logic led4_PAD, // status_ok
  output logic led5_PAD, // status_record/activity
  output logic led6_PAD, // status_receiving
  output logic led7_PAD  // heartbeat
);

  localparam int CORE_CLK_HZ = 10_000_000;
  
  // ========================================================
  // Clock Generation (100MHz PAD -> 10MHz Core)
  // ========================================================
  logic       clk_10mhz;
  logic       clk_core;
  logic [3:0] clk_div_cnt_q;

  always_ff @(posedge clk_PAD or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      clk_div_cnt_q <= '0;
      clk_10mhz     <= 1'b0;
    end else begin
      if (clk_div_cnt_q == 4) begin
        clk_div_cnt_q <= '0;
        clk_10mhz     <= ~clk_10mhz;
      end else begin
        clk_div_cnt_q <= clk_div_cnt_q + 1'b1;
      end
    end
  end

  // Use BUFG for the core clock distribution
  BUFG clk_core_bufg_i (.I(clk_10mhz), .O(clk_core));

  // ========================================================
  // Status LED Logic
  // ========================================================
  localparam int LED_HB_BIT = 23;      // ~0.8s period at 10MHz
  localparam int LED_REC_BLINK_BIT = 22; // ~0.4s period
  localparam int LED_PULSE_TICKS = CORE_CLK_HZ / 5; // ~200ms stretch
  localparam int LED_CNT_W = (LED_PULSE_TICKS > 1) ? $clog2(LED_PULSE_TICKS) : 1;

  logic [31:0]          hb_counter_q;
  logic [LED_CNT_W-1:0] led_ok_cnt_q;     // For valid code
  logic [LED_CNT_W-1:0] led_err_cnt_q;    // For error
  logic [LED_CNT_W-1:0] led_uart_cnt_q;   // For UART activity

  // Core status signals
  logic stat_receiving;
  logic stat_code_valid;
  logic stat_record_active;
  logic stat_uart_active;
  logic stat_error;

  logic rec_done, rep_done, busy, error;
  logic ir_led_alias_unused;
  logic ir_tx_npn_drive;

  // Heartbeat counter
  always_ff @(posedge clk_core or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      hb_counter_q <= '0;
    end else begin
      hb_counter_q <= hb_counter_q + 1'b1;
    end
  end

  // Pulse stretchers
  always_ff @(posedge clk_core or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      led_ok_cnt_q   <= '0;
      led_err_cnt_q  <= '0;
      led_uart_cnt_q <= '0;
    end else begin
      // Stretch "Code Valid" pulse
      if (stat_code_valid) begin
        led_ok_cnt_q <= LED_PULSE_TICKS - 1;
      end else if (led_ok_cnt_q != '0) begin
        led_ok_cnt_q <= led_ok_cnt_q - 1'b1;
      end

      // Stretch "Error" pulse
      if (stat_error) begin
        led_err_cnt_q <= LED_PULSE_TICKS - 1;
      end else if (led_err_cnt_q != '0) begin
        led_err_cnt_q <= led_err_cnt_q - 1'b1;
      end

      // Stretch "UART" pulse (optional debug usage)
      if (stat_uart_active) begin
        led_uart_cnt_q <= LED_PULSE_TICKS - 1;
      end else if (led_uart_cnt_q != '0) begin
        led_uart_cnt_q <= led_uart_cnt_q - 1'b1;
      end
    end
  end

  // Instantiate Core
  ir_recorder_replay_top #(
    .CORE_CLK_HZ(CORE_CLK_HZ),
    .UART_BAUD(1_000_000),
    .RAW_UART_DEBUG(1'b0)
  ) u_core (
    .clk(clk_core),
    .rst_n(rst_n_PAD),
    .ir_in(ir_in_PAD),
    .record_req(btn_record_PAD),
    .replay_req(btn_replay_PAD),
    .slot_sel(3'b000), // MVP: fixed slot 0 on hardware
    .use_external_decoder_data(1'b0),
    .dec_valid(1'b0),
    .dec_payload(32'h0000_0000),
    
    .ir_tx_npn_drive(ir_tx_npn_drive),
    .ir_led_out(ir_led_alias_unused),
    .uart_tx(uart_tx_PAD),
    
    .stat_receiving(stat_receiving),
    .stat_code_valid(stat_code_valid),
    .stat_record_active(stat_record_active),
    .stat_uart_active(stat_uart_active),
    .stat_error(stat_error),

    .rec_done(rec_done),
    .rep_done(rep_done),
    .busy(busy),
    .error(error)
  );

  assign ir_tx_PAD = ir_tx_npn_drive;

  // LED Mapping
  // LD7: Heartbeat
  assign led7_PAD = hb_counter_q[LED_HB_BIT];
  
  // LD6: Receiving indicator
  assign led6_PAD = stat_receiving;

  // LD5: Record blink / Busy solid / Error pulse
  // Logic: 
  //   If Recording -> Blink
  //   Else if Busy -> Solid On
  //   Else if Error Pulse -> Solid On
  //   Else -> Off
  assign led5_PAD = stat_record_active ? hb_counter_q[LED_REC_BLINK_BIT] :
                    (busy ? 1'b1 : (led_err_cnt_q != '0));

  // LD4: Code Valid Pulse
  assign led4_PAD = (led_ok_cnt_q != '0);

  // Note: LD3..LD0 are not physically wired on Arty according to this wrapper's port list 
  // (led4_PAD..led7_PAD are the standard RGB or discrete LEDs, checking typical Arty constraint mapping would confirm, 
  // but we stick to the existing wrapper ports).

endmodule
