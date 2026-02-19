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

  // ESP32-C3 Software-SPI interface
  input  logic spi_clk_PAD,
  input  logic spi_data_PAD,

  output logic uart_tx_PAD,
  output logic ir_tx_PAD,
  output logic led4_PAD, // status_ok
  output logic led5_PAD, // status_record/activity
  output logic led6_PAD, // status_receiving
  output logic led7_PAD  // heartbeat
);

  localparam int CORE_CLK_HZ = 10_000_000;
  localparam int TX_TEST_CARRIER_HZ = 38_000;
  localparam int TX_TEST_HALF_PERIOD = (CORE_CLK_HZ / (2 * TX_TEST_CARRIER_HZ) > 0)
                                       ? (CORE_CLK_HZ / (2 * TX_TEST_CARRIER_HZ)) : 1;
  localparam int TX_TEST_DIV_W = (TX_TEST_HALF_PERIOD > 1) ? $clog2(TX_TEST_HALF_PERIOD) : 1;
  localparam int TICK_US_DIV = (CORE_CLK_HZ / 1_000_000 > 0) ? (CORE_CLK_HZ / 1_000_000) : 1;
  localparam int TICK_US_W = (TICK_US_DIV > 1) ? $clog2(TICK_US_DIV) : 1;
  
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
  localparam int LED_HB_BIT = 23;         // ~0.8s period at 10MHz
  localparam int LED_REC_BLINK_BIT = 20;  // ~0.1s period (fast blink = recording)
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
  logic ir_tx_test;

  // ESP32 SPI receiver outputs
  logic esp_replay_req, esp_record_req;
  logic [5:0] esp_slot_addr;           // [5:4]=remote_id, [3:0]=slot_num
  logic [5:0] esp_slot_addr_lat;       // latched slot — held until next command

  // Combined control signals (button OR ESP32)
  logic combined_record_req, combined_replay_req;
  logic [5:0] combined_slot_sel;
  logic btn_replay_prev_q;
  logic tx_test_active;
  logic tx_test_busy_q;
  logic tx_test_mark_q;
  logic [4:0] tx_test_step_q;
  logic [13:0] tx_test_us_cnt_q;
  logic [TX_TEST_DIV_W-1:0] tx_test_div_q;
  logic tx_test_carrier_q;
  logic [TICK_US_W-1:0] tick_us_div_q;
  logic tick_us;

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

  // 1us tick for local test frame timing.
  always_ff @(posedge clk_core or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      tick_us_div_q <= '0;
      tick_us <= 1'b0;
    end else begin
      tick_us <= 1'b0;
      if (tick_us_div_q == TICK_US_DIV - 1) begin
        tick_us_div_q <= '0;
        tick_us <= 1'b1;
      end else begin
        tick_us_div_q <= tick_us_div_q + 1'b1;
      end
    end
  end

  function automatic logic [13:0] tx_step_us(input logic [4:0] idx);
    case (idx)
      5'd0:  tx_step_us = 14'd8894;
      5'd1:  tx_step_us = 14'd4057;
      5'd2:  tx_step_us = 14'd532;
      5'd3:  tx_step_us = 14'd502;
      5'd4:  tx_step_us = 14'd534;
      5'd5:  tx_step_us = 14'd503;
      5'd6:  tx_step_us = 14'd533;
      5'd7:  tx_step_us = 14'd503;
      5'd8:  tx_step_us = 14'd533;
      5'd9:  tx_step_us = 14'd503;
      5'd10: tx_step_us = 14'd533;
      5'd11: tx_step_us = 14'd1033;
      5'd12: tx_step_us = 14'd532;
      5'd13: tx_step_us = 14'd503;
      5'd14: tx_step_us = 14'd531;
      5'd15: tx_step_us = 14'd1031;
      5'd16: tx_step_us = 14'd531;
      5'd17: tx_step_us = 14'd503;
      5'd18: tx_step_us = 14'd531;
      default: tx_step_us = 14'd0;
    endcase
  endfunction

  // One-shot TX test frame on replay button edge.
  // This validates the JA2 transmit path with a NEC-like waveform.
  always_ff @(posedge clk_core or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      btn_replay_prev_q <= 1'b0;
      tx_test_busy_q    <= 1'b0;
      tx_test_mark_q    <= 1'b0;
      tx_test_step_q    <= 5'd0;
      tx_test_us_cnt_q  <= 14'd0;
      tx_test_div_q     <= '0;
      tx_test_carrier_q <= 1'b0;
    end else begin
      btn_replay_prev_q <= btn_replay_PAD;

      if (btn_replay_PAD && !btn_replay_prev_q) begin
        tx_test_busy_q   <= 1'b1;
        tx_test_mark_q   <= 1'b1;
        tx_test_step_q   <= 5'd0;
        tx_test_us_cnt_q <= 14'd0;
      end else if (tx_test_busy_q && tick_us) begin
        if (tx_test_us_cnt_q == tx_step_us(tx_test_step_q) - 1) begin
          tx_test_us_cnt_q <= 14'd0;
          if (tx_test_step_q == 5'd18) begin
            tx_test_busy_q <= 1'b0;
            tx_test_mark_q <= 1'b0;
          end else begin
            tx_test_step_q <= tx_test_step_q + 1'b1;
            tx_test_mark_q <= ~tx_test_mark_q;
          end
        end else begin
          tx_test_us_cnt_q <= tx_test_us_cnt_q + 1'b1;
        end
      end

      if (tx_test_busy_q && tx_test_mark_q) begin
        if (tx_test_div_q == TX_TEST_HALF_PERIOD - 1) begin
          tx_test_div_q     <= '0;
          tx_test_carrier_q <= ~tx_test_carrier_q;
        end else begin
          tx_test_div_q <= tx_test_div_q + 1'b1;
        end
      end else begin
        tx_test_div_q     <= '0;
        tx_test_carrier_q <= 1'b0;
      end
    end
  end

  assign tx_test_active = tx_test_busy_q;
  assign ir_tx_test = (tx_test_busy_q && tx_test_mark_q) ? tx_test_carrier_q : 1'b0;

  // ========================================================
  // ESP32 SPI Receiver
  // ========================================================
  esp32_spi_receiver u_esp32_spi (
    .clk         (clk_core),
    .rst_n       (rst_n_PAD),
    .spi_clk_in  (spi_clk_PAD),
    .spi_data_in (spi_data_PAD),
    .replay_req  (esp_replay_req),
    .record_req  (esp_record_req),
    .slot_addr   (esp_slot_addr)
  );

  // Latch esp_slot_addr when a SPI command fires so slot_sel stays
  // stable after the 1-cycle pulse has gone low.
  always_ff @(posedge clk_core or negedge rst_n_PAD) begin
    if (!rst_n_PAD)
      esp_slot_addr_lat <= 6'd0;
    else if (esp_record_req || esp_replay_req)
      esp_slot_addr_lat <= esp_slot_addr;
  end

  // Merge physical buttons with ESP32 commands.
  // Latched slot used so value persists after the 1-cycle SPI pulse.
  assign combined_record_req = btn_record_PAD | esp_record_req;
  assign combined_replay_req = btn_replay_PAD | esp_replay_req;
  assign combined_slot_sel   = (esp_record_req || esp_replay_req)
                               ? esp_slot_addr : esp_slot_addr_lat;

  // Instantiate Core
  ir_recorder_replay_top #(
    .CORE_CLK_HZ(CORE_CLK_HZ),
    .UART_BAUD(1_000_000),
    .RAW_UART_DEBUG(1'b0)
  ) u_core (
    .clk(clk_core),
    .rst_n(rst_n_PAD),
    .ir_in(ir_in_PAD),
    .record_req(combined_record_req),
    .replay_req(combined_replay_req),
    .slot_sel(combined_slot_sel),
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

  assign ir_tx_PAD = ir_tx_npn_drive | ir_tx_test;

  // LED Mapping
  // LD7: Heartbeat
  assign led7_PAD = hb_counter_q[LED_HB_BIT];
  
  // LD6: Receiving indicator
  assign led6_PAD = stat_receiving;

  // LD5: Fast blink while recording, off after signal stored
  //   Recording  → fast blink (LED_REC_BLINK_BIT ~0.1s)
  //   Done/Idle  → OFF
  assign led5_PAD = tx_test_active | (stat_record_active ? hb_counter_q[LED_REC_BLINK_BIT] : 1'b0);

  // LD4: Code Valid Pulse
  assign led4_PAD = (led_ok_cnt_q != '0);

  // Note: LD3..LD0 are not physically wired on Arty according to this wrapper's port list 
  // (led4_PAD..led7_PAD are the standard RGB or discrete LEDs, checking typical Arty constraint mapping would confirm, 
  // but we stick to the existing wrapper ports).

endmodule
