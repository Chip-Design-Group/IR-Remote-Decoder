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

  // ESP32 SPI receiver outputs
  logic esp_replay_req, esp_record_req;
  logic [2:0] esp_slot_addr;
  logic [2:0] esp_slot_addr_lat; // latched slot — held until next command

  // Combined control signals (button OR ESP32)
  logic combined_record_req, combined_replay_req;
  logic [2:0] combined_slot_sel;

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
      esp_slot_addr_lat <= 3'd0;
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

  assign ir_tx_PAD = ir_tx_npn_drive;

  // LED Mapping
  // LD7: Heartbeat
  assign led7_PAD = hb_counter_q[LED_HB_BIT];
  
  // LD6: Receiving indicator
  assign led6_PAD = stat_receiving;

  // LD5: Fast blink while recording, off after signal stored
  //   Recording  → fast blink (LED_REC_BLINK_BIT ~0.1s)
  //   Done/Idle  → OFF
  assign led5_PAD = stat_record_active ? hb_counter_q[LED_REC_BLINK_BIT] : 1'b0;

  // LD4: Code Valid Pulse
  assign led4_PAD = (led_ok_cnt_q != '0);

  // Note: LD3..LD0 are not physically wired on Arty according to this wrapper's port list 
  // (led4_PAD..led7_PAD are the standard RGB or discrete LEDs, checking typical Arty constraint mapping would confirm, 
  // but we stick to the existing wrapper ports).

endmodule
