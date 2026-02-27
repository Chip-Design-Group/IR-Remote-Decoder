//------------------------------------------------------------------------------
// File: ir_recorder_replay_top.sv
// Purpose:
//   Integrates the complete IR receive / record / replay datapath:
//     IR input -> edge detection -> pulse timing -> NEC decode
//              -> BRAM recording -> replay FSM -> NEC encode -> IR transmit
//   In parallel, decoded frames are formatted and transmitted over UART.
//
// Inputs:
//   clk, rst_n
//   ir_in
//   record_req, replay_req, slot_sel
//   optional external decoded stream: use_external_decoder_data, dec_valid, dec_payload
//
// Outputs:
//   ir_tx_npn_drive, ir_led_out
//   uart_tx
//   rec_done, rep_done, busy, error
//   status flags for wrapper/debug
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_recorder_replay_top #(
  parameter int CORE_CLK_HZ     = 10_000_000,
  parameter int RECORD_TIMEOUT_CYCLES = (3 * CORE_CLK_HZ), // ~3s at 10MHz core
  parameter int TX_CARRIER_HZ   = 38_000,
  parameter int UART_BAUD       = 1_000_000,
  parameter bit RAW_UART_DEBUG  = 1'b0
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  ir_in,

  input  logic                  record_req,
  input  logic                  replay_req,
  input  ir_slot_t              slot_sel,

  // Externer Decoder-Bypass fuer Integrationstests/Debug.
  input  logic                  use_external_decoder_data,
  input  logic                  dec_valid,
  input  logic [31:0]           dec_payload,

  output logic                  ir_tx_npn_drive,
  output logic                  ir_led_out,
  output logic                  uart_tx,

  // Status outputs for wrapper/debug
  output logic                  stat_receiving,     // IR activity
  output logic                  stat_code_valid,    // Valid code decoded
  output logic                  stat_record_active, // Recording in progress
  output logic                  stat_uart_active,   // UART TX in progress
  output logic                  stat_error,         // Error condition

  output logic                  rec_done,
  output logic                  rep_done,
  output logic                  busy,
  output logic                  error
);

  // ========================================================
  // Clocking and timing constants
  // ========================================================
  // Input clk is expected to be the core clock (e.g. 10MHz).
  localparam int TICK_US_DIV = (CORE_CLK_HZ / 1_000_000 > 0) ? (CORE_CLK_HZ / 1_000_000) : 1;
  localparam int TICK_US_W   = (TICK_US_DIV > 1) ? $clog2(TICK_US_DIV) : 1;
  localparam int UART_CLKS_PER_BIT = (CORE_CLK_HZ / UART_BAUD > 0) ? (CORE_CLK_HZ / UART_BAUD) : 1;

  logic [TICK_US_W-1:0] tick_cnt_q;
  logic                 tick_us;
  logic                 clk_core;

  logic record_prev_q, replay_prev_q;
  logic record_pulse, replay_pulse;
  logic record_hold_q;
  logic replay_fire;

  logic                 ir_in_sync;
  logic                 edge_rise, edge_fall;
  logic                 pulse_done, pulse_level, timeout;
  logic [17:0]          pulse_width;
  logic                 dec_data_valid_i, dec_error_i, dec_receiving_i;
  logic [7:0]           dec_addr_i, dec_cmd_i;
  logic [4:0]           dec_protocol_i;
  logic [47:0]          dec_frame_data_i;
  logic [5:0]           dec_frame_bits_i;
  logic [7:0]           ext_addr;
  logic [7:0]           ext_cmd;
  logic [4:0]           ext_protocol_id;
  logic [47:0]          ext_frame_data;

  logic                 dec_valid_mux;
  logic                 dec_error_mux;

  ir_payload_t          rec_payload;

  logic                 mem_wr_en;
  logic [2:0]           mem_wr_addr;
  ir_word_t             mem_wr_data;
  logic                 mem_rd_en;
  ir_slot_t             mem_rd_addr;
  ir_word_t             mem_rd_data;
  logic                 mem_rd_valid;

  logic                 rec_busy, rec_done_i, rec_error;
  logic                 rep_busy, rep_done_i, rep_error;
  logic                 enc_start, enc_mark_active, enc_frame_active, enc_frame_done, enc_busy, enc_error;
  logic                 tx_ready, enc_ready;
  ir_payload_t          enc_payload;
  logic [7:0]           uart_data, uart_data_raw, uart_data_fmt;
  logic                 uart_tx_req, uart_tx_req_raw, uart_tx_req_fmt, uart_ready;
  logic                 uart_ready_raw, uart_ready_fmt;
  logic [7:0]           uart_addr, uart_cmd;
  logic [4:0]           uart_protocol_id;
  logic                 error_raw;

  assign clk_core = clk;
  assign ext_addr = dec_payload[23:16];
  assign ext_cmd  = dec_payload[15:8];
  assign ext_protocol_id = dec_payload[7:3];
  assign ext_frame_data = {16'h0000, {~ext_cmd, ext_cmd, ~ext_addr, ext_addr}};

  // 1 us pulse generator in core clock domain.
  always_ff @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
      tick_cnt_q <= '0;
      tick_us    <= 1'b0;
    end else begin
      tick_us <= 1'b0;
      if (tick_cnt_q == TICK_US_DIV - 1) begin
        tick_cnt_q <= '0;
        tick_us    <= 1'b1;
      end else begin
        tick_cnt_q <= tick_cnt_q + 1'b1;
      end
    end
  end

  // Synchronize and edge-detect record/replay button requests.
  always_ff @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
      record_prev_q <= 1'b0;
      replay_prev_q <= 1'b0;
    end else begin
      record_prev_q <= record_req;
      replay_prev_q <= replay_req;
    end
  end

  assign record_pulse = record_req & ~record_prev_q;
  assign replay_pulse = replay_req & ~replay_prev_q;

  // Latch record request until recorder finishes (done/error).
  // No busy guard: short ESP32 pulses must not be dropped.
  always_ff @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
      record_hold_q <= 1'b0;
    end else begin
      if (rec_done_i || rec_error) begin
        record_hold_q <= 1'b0;
      end else if (record_pulse) begin
        record_hold_q <= 1'b1;
      end
    end
  end

  // Replay request is forwarded as a one-shot pulse.
  assign replay_fire = replay_pulse;

  // -------------------------
  // IR receive/decode pipeline
  // -------------------------
  edge_detector u_edge_detector (
    .clk        (clk_core),
    .rst_n      (rst_n),
    .ir_in_async(ir_in),
    .ir_in_sync (ir_in_sync),
    .edge_rise  (edge_rise),
    .edge_fall  (edge_fall)
  );

  pulse_timer u_pulse_timer (
    .clk       (clk_core),
    .rst_n     (rst_n),
    .ir_in_sync(ir_in_sync),
    .edge_rise (edge_rise),
    .edge_fall (edge_fall),
    .pulse_done(pulse_done),
    .pulse_width(pulse_width),
    .pulse_level(pulse_level),
    .timeout   (timeout)
  );

  nec_decoder u_nec_decoder (
    .clk        (clk_core),
    .rst_n      (rst_n),
    .pulse_done (pulse_done),
    .pulse_width(pulse_width),
    .pulse_level(pulse_level),
    .timeout    (timeout),
    .data_valid (dec_data_valid_i),
    .decode_error(dec_error_i),
    .address    (dec_addr_i),
    .command    (dec_cmd_i),
    .protocol_id(dec_protocol_i),
    .frame_data (dec_frame_data_i),
    .frame_bits (dec_frame_bits_i),
    .receiving  (dec_receiving_i)
  );

  // Select decoded payload source:
  // - internal NEC decoder path, or
  // - external decoded stream for test/debug injection.
  always_comb begin
    if (use_external_decoder_data) begin
      dec_valid_mux = dec_valid;
      dec_error_mux = 1'b0;
      uart_addr     = ext_addr;
      uart_cmd      = ext_cmd;
      uart_protocol_id = ext_protocol_id;
      rec_payload.frame_data = ext_frame_data;
      rec_payload.frame_bits = 6'd32;
      rec_payload.protocol_id = ext_protocol_id;
      rec_payload.flags = dec_payload[7:0];
      rec_payload.flags[IR_FLAG_VALID_BIT] = 1'b1;
    end else begin
      dec_valid_mux = dec_data_valid_i;
      dec_error_mux = dec_error_i;
      uart_addr     = dec_addr_i;
      uart_cmd      = dec_cmd_i;
      uart_protocol_id = dec_protocol_i;
      rec_payload.frame_data = dec_frame_data_i;
      rec_payload.frame_bits = dec_frame_bits_i;
      rec_payload.protocol_id = dec_protocol_i;
      rec_payload.flags = IR_FLAGS_DEFAULT;
      rec_payload.flags[IR_FLAG_VALID_BIT] = 1'b1;
    end
  end

  // -------------------------
  // Record / replay datapath
  // -------------------------
  ir_recorder #(
    .WAIT_TIMEOUT_CYCLES(RECORD_TIMEOUT_CYCLES)
  ) u_recorder (
    .clk       (clk_core),
    .rst_n     (rst_n),
    .record_req(record_hold_q),
    .target_slot(slot_sel),
    .dec_valid (dec_valid_mux),
    .dec_payload(rec_payload),
    .mem_wr_en (mem_wr_en),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data),
    .busy      (rec_busy),
    .done      (rec_done_i),
    .error     (rec_error)
  );

  ir_storage_bram u_storage_bram (
    .clk      (clk_core),
    .rst_n    (rst_n),
    .wr_en    (mem_wr_en),
    .wr_addr  (mem_wr_addr),
    .wr_data  (mem_wr_data),
    .rd_en    (mem_rd_en),
    .rd_addr  (mem_rd_addr),
    .rd_data  (mem_rd_data),
    .rd_valid (mem_rd_valid)
  );

  assign enc_ready = ~enc_busy;

  ir_replay_fsm u_replay_fsm (
    .clk       (clk_core),
    .rst_n     (rst_n),
    .replay_req(replay_fire),
    .target_slot(slot_sel),
    .mem_rd_en (mem_rd_en),
    .mem_rd_addr(mem_rd_addr),
    .mem_rd_data(mem_rd_data),
    .mem_rd_valid(mem_rd_valid),
    .enc_start (enc_start),
    .enc_payload(enc_payload),
    .enc_ready (enc_ready),
    .tx_ready  (tx_ready),
    .busy      (rep_busy),
    .done      (rep_done_i),
    .error     (rep_error)
  );

  // -------------------------
  // Replay transmit datapath
  // -------------------------
  nec_encoder u_nec_encoder (
    .clk       (clk_core),
    .rst_n     (rst_n),
    .start     (enc_start),
    .payload   (enc_payload),
    .tick_us   (tick_us),
    .mark_active(enc_mark_active),
    .frame_active(enc_frame_active),
    .frame_done(enc_frame_done),
    .busy      (enc_busy),
    .error     (enc_error)
  );

  ir_tx #(
    .CLK_HZ    (CORE_CLK_HZ),
    .CARRIER_HZ(TX_CARRIER_HZ)
  ) u_ir_tx (
    .clk        (clk_core),
    .rst_n      (rst_n),
    .mark_active(enc_mark_active),
    .ir_npn_drive(ir_tx_npn_drive),
    .ir_led_out (ir_led_out),
    .ready      (tx_ready)
  );

  // -------------------------
  // UART diagnostics datapath
  // -------------------------
  // Always build both formatters. In RAW mode we still prioritize decoded frames
  // when available, so protocol recognition stays visible during pulse debugging.
  assign uart_ready_fmt = uart_ready;
  assign uart_ready_raw = uart_ready & ~uart_tx_req_fmt;

  raw_pulse_uart_formatter u_raw_pulse_uart_formatter (
    .clk         (clk_core),
    .rst_n       (rst_n),
    .pulse_done  (pulse_done),
    .pulse_width (pulse_width),
    .pulse_level (pulse_level),
    .pulse_timeout(timeout),
    .uart_ready  (uart_ready_raw),
    .uart_data   (uart_data_raw),
    .uart_tx_req (uart_tx_req_raw)
  );

  output_formatter u_output_formatter (
    .clk        (clk_core),
    .rst_n      (rst_n),
    .address    (uart_addr),
    .command    (uart_cmd),
    .protocol_id(uart_protocol_id),
    .valid_in   (dec_valid_mux),
    .decode_error(dec_error_mux),
    .frame_data (dec_frame_data_i),
    .frame_bits (dec_frame_bits_i),
    .uart_ready (uart_ready_fmt),
    .uart_data  (uart_data_fmt),
    .uart_tx_req(uart_tx_req_fmt)
  );

  always_comb begin
    if (RAW_UART_DEBUG) begin
      if (uart_tx_req_fmt) begin
        uart_data   = uart_data_fmt;
        uart_tx_req = uart_tx_req_fmt;
      end else begin
        uart_data   = uart_data_raw;
        uart_tx_req = uart_tx_req_raw;
      end
    end else begin
      uart_data   = uart_data_fmt;
      uart_tx_req = uart_tx_req_fmt;
    end
  end

  uart_tx #(
    .CLOCKS_PER_BIT(UART_CLKS_PER_BIT)
  ) u_uart_tx (
    .clk        (clk_core),
    .rst_n      (rst_n),
    .data_in    (uart_data),
    .send_req   (uart_tx_req),
    .tx_out     (uart_tx),
    .ready      (uart_ready)
  );

  // -------------------------
  // Aggregated status outputs
  // -------------------------
  assign rec_done = rec_done_i;
  // Replay is completed only after the encoder finished the full frame.
  assign rep_done = enc_frame_done;
  assign busy     = rec_busy || rep_busy || enc_busy;
  // Decoder errors can occur on noise/incomplete frames and are reported via UART.
  // Keep top-level error focused on hard record/replay/encode failures.
  assign error_raw = rec_error || rep_error || enc_error;
  assign error     = error_raw;

  // Status mapping
  assign stat_receiving = dec_receiving_i;
  assign stat_code_valid = dec_valid_mux;
  assign stat_record_active = record_hold_q;
  assign stat_uart_active = uart_tx_req;
  assign stat_error = error_raw;

endmodule
