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
//   ld7..ld0 (status LEDs)
//   rec_done, rep_done, busy, error
//------------------------------------------------------------------------------

module ir_recorder_replay_top #(
  parameter int CORE_CLK_HZ     = 10_000_000,
  parameter int RECORD_TIMEOUT_CYCLES = (3 * CORE_CLK_HZ), // ~3s at 10MHz core
  parameter int TX_CARRIER_HZ   = 38_000
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  ir_in,

  input  logic                  record_req,
  input  logic                  replay_req,
  input  logic [2:0]            slot_sel,

  // Externer Decoder-Bypass fuer Integrationstests/Debug.
  input  logic                  use_external_decoder_data,
  input  logic                  dec_valid,
  input  logic [31:0]           dec_payload,

  output logic                  ir_tx_npn_drive,
  output logic                  ir_led_out,
  output logic                  uart_tx,
  output logic                  ld7,
  output logic                  ld6,
  output logic                  ld5,
  output logic                  ld4,
  output logic                  ld3,
  output logic                  ld2,
  output logic                  ld1,
  output logic                  ld0,
  output logic                  rec_done,
  output logic                  rep_done,
  output logic                  busy,
  output logic                  error
);

  // ========================================================
  // Clocking and timing constants
  // ========================================================
  // - hardware: divide 100 MHz input clock down to 10 MHz core clock
  // - simulation: bypass divider and use testbench clock directly
  localparam int TICK_US_DIV = (CORE_CLK_HZ / 1_000_000 > 0) ? (CORE_CLK_HZ / 1_000_000) : 1;
  localparam int TICK_US_W   = (TICK_US_DIV > 1) ? $clog2(TICK_US_DIV) : 1;
  localparam int UART_CLKS_PER_BIT = (CORE_CLK_HZ / 9600 > 0) ? (CORE_CLK_HZ / 9600) : 1;

  logic [TICK_US_W-1:0] tick_cnt_q;
  logic                 tick_us;
  logic                 clk_core;
  logic                 clk_10mhz;
  logic [3:0]           clk_div_cnt_q;

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

  logic                 dec_valid_mux;
  logic                 dec_error_mux;
  logic [31:0]          dec_payload_mux;
  logic [31:0]          rec_payload;

  logic                 mem_wr_en;
  logic [2:0]           mem_wr_addr;
  logic [31:0]          mem_wr_data;
  logic                 mem_rd_en;
  logic [2:0]           mem_rd_addr;
  logic [31:0]          mem_rd_data;
  logic                 mem_rd_valid;

  logic                 rec_busy, rec_done_i, rec_error;
  logic                 rep_busy, rep_done_i, rep_error;
  logic                 enc_start, enc_mark_active, enc_frame_active, enc_frame_done, enc_busy, enc_error;
  logic                 tx_ready, enc_ready;
  logic [31:0]          enc_payload;
  logic [7:0]           uart_data;
  logic                 uart_tx_req, uart_ready;
  logic [7:0]           uart_addr, uart_cmd;
  logic                 error_raw;

  localparam int LED_HB_BIT = 23;
  localparam int LED_REC_BLINK_BIT = 22;
  localparam int LED_PULSE_TICKS = CORE_CLK_HZ / 5; // ~200ms
  localparam int LED_CNT_W = (LED_PULSE_TICKS > 1) ? $clog2(LED_PULSE_TICKS) : 1;
  logic [31:0]          hb_counter_q;
  logic [LED_CNT_W-1:0] led_ok_cnt_q, led_err_cnt_q, led_uart_cnt_q;

`ifndef SIMULATION
  // Divide by 10 by toggling every 5 cycles.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
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
`else
  // Simulation: feed core clock directly from the testbench clock.
  assign clk_10mhz = clk;
`endif

`ifdef SIMULATION
  assign clk_core = clk_10mhz;
`else
  // Hardware: route the derived clock via global buffer.
  BUFG clk_core_bufg_i (.I(clk_10mhz), .O(clk_core));
`endif

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

  // Slow heartbeat counter for LD7.
  always_ff @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
      hb_counter_q <= '0;
    end else begin
      hb_counter_q <= hb_counter_q + 1'b1;
    end
  end

  // Pulse stretcher so short events are visible on LEDs.
  always_ff @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
      led_ok_cnt_q   <= '0;
      led_err_cnt_q  <= '0;
      led_uart_cnt_q <= '0;
    end else begin
      if (dec_valid_mux) begin
        led_ok_cnt_q <= LED_PULSE_TICKS - 1;
      end else if (led_ok_cnt_q != '0) begin
        led_ok_cnt_q <= led_ok_cnt_q - 1'b1;
      end

      if (error_raw) begin
        led_err_cnt_q <= LED_PULSE_TICKS - 1;
      end else if (led_err_cnt_q != '0) begin
        led_err_cnt_q <= led_err_cnt_q - 1'b1;
      end

      if (uart_tx_req) begin
        led_uart_cnt_q <= LED_PULSE_TICKS - 1;
      end else if (led_uart_cnt_q != '0) begin
        led_uart_cnt_q <= led_uart_cnt_q - 1'b1;
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
  always_ff @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
      record_hold_q <= 1'b0;
    end else begin
      if (rec_done_i || rec_error) begin
        record_hold_q <= 1'b0;
      end else if (record_pulse && !busy) begin
        // Keep recording active until a valid decoded frame is stored.
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
    .receiving  (dec_receiving_i)
  );

  // Select decoded payload source:
  // - internal NEC decoder path, or
  // - external decoded stream for test/debug injection.
  always_comb begin
    if (use_external_decoder_data) begin
      dec_valid_mux   = dec_valid;
      dec_payload_mux = dec_payload;
      dec_error_mux   = 1'b0;
    end else begin
      dec_valid_mux           = dec_data_valid_i;
      // Internal decoder provides 8-bit NEC address. For replay encoding we
      // store it in 8-bit NEC form: {addr_inv, addr}.
      dec_payload_mux[31:16]  = {~dec_addr_i, dec_addr_i};
      dec_payload_mux[15:8]   = dec_cmd_i;
      dec_payload_mux[7:0]    = 8'h00;
      dec_error_mux           = dec_error_i;
    end
  end

  // Build recorder payload:
  // - force slot-valid bit
  // - expose address/command bytes for UART formatter.
  always_comb begin
    rec_payload = dec_payload_mux;
    rec_payload[0] = 1'b1; // valid bit
    uart_addr = dec_payload_mux[23:16];
    uart_cmd  = dec_payload_mux[15:8];
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
  output_formatter u_output_formatter (
    .clk        (clk_core),
    .rst_n      (rst_n),
    .address    (uart_addr),
    .command    (uart_cmd),
    .valid_in   (dec_valid_mux),
    .decode_error(dec_error_mux),
    .uart_ready (uart_ready),
    .uart_data  (uart_data),
    .uart_tx_req(uart_tx_req)
  );

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

  // LED mapping (LD7..LD0):
  // LD7: slow heartbeat
  // LD6: IR receive activity
  // LD5: record active (blink); replay active (solid); when idle, error pulse (stretched)
  // LD4: decode-OK pulse (stretched)
  // LD3: error pulse (stretched)
  // LD2: replay/transmit activity
  // LD1: global busy
  // LD0: UART activity pulse (stretched)
  assign ld7 = hb_counter_q[LED_HB_BIT];
  assign ld6 = dec_receiving_i;
  assign ld5 = record_hold_q ? hb_counter_q[LED_REC_BLINK_BIT] :
               ((rep_busy || enc_busy) ? 1'b1 : (led_err_cnt_q != '0));
  assign ld4 = (led_ok_cnt_q  != '0);
  assign ld3 = (led_err_cnt_q != '0);
  assign ld2 = rep_busy || enc_busy;
  assign ld1 = busy;
  assign ld0 = (led_uart_cnt_q != '0);

endmodule
