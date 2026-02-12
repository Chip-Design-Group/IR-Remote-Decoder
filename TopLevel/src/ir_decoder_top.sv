`timescale 1ns/1ps

// ============================================================
// IR Decoder Top-Level
// ============================================================
//
// Connects the full NEC IR decoder pipeline:
//   IR_IN → edge_detector → pulse_timer → nec_decoder
//         → output_formatter → uart_tx → UART_TX
//
// LED outputs for visual feedback:
//   led_valid  = data_valid pulse (active-high, 1 clock)
//   led_error  = decode_error pulse
//   led_active = receiving signal (high during decoding)
// ============================================================

module ir_decoder_top (
    input  logic clk_PAD,
    input  logic rst_n_PAD,
    input  logic ir_in_PAD,

    output logic uart_tx_PAD,
    output logic led_valid_PAD,
    output logic led_error_PAD,
    output logic led_active_PAD
);

    // ========================================================
    // Internal Signals (directly assigned for simulation;
    // ASIC IO pads would be instantiated here for tapeout)
    // ========================================================
    logic clk, rst_n, ir_in;
    logic uart_tx_out;
    logic led_valid, led_error, led_active;

    assign clk   = clk_PAD;
    assign rst_n = rst_n_PAD;
    assign ir_in = ir_in_PAD;

    assign uart_tx_PAD   = uart_tx_out;
    assign led_valid_PAD = led_valid;
    assign led_error_PAD = led_error;
    assign led_active_PAD = led_active;

    // ========================================================
    // Edge Detector → Pulse Timer interconnect
    // ========================================================
    logic ir_in_sync;
    logic edge_rise;
    logic edge_fall;

    // ========================================================
    // Pulse Timer → NEC Decoder interconnect
    // ========================================================
    logic        pulse_done;
    logic [17:0] pulse_width;
    logic        pulse_level;
    logic        timeout;

    // ========================================================
    // NEC Decoder → Output Formatter interconnect
    // ========================================================
    logic        data_valid;
    logic        decode_error;
    logic [7:0]  address;
    logic [7:0]  command;
    logic        receiving;

    // ========================================================
    // Output Formatter ↔ UART TX interconnect
    // ========================================================
    logic [7:0]  uart_data;
    logic        uart_tx_req;
    logic        uart_ready;

    // ========================================================
    // Module Instantiations
    // ========================================================

    // --- Edge Detector ---
    edge_detector u_edge_detector (
        .clk          (clk),
        .rst_n        (rst_n),
        .ir_in_async  (ir_in),
        .ir_in_sync   (ir_in_sync),
        .edge_rise    (edge_rise),
        .edge_fall    (edge_fall)
    );

    // --- Pulse Timer ---
    pulse_timer u_pulse_timer (
        .clk          (clk),
        .rst_n        (rst_n),
        .ir_in_sync   (ir_in_sync),
        .edge_rise    (edge_rise),
        .edge_fall    (edge_fall),
        .pulse_done   (pulse_done),
        .pulse_width  (pulse_width),
        .pulse_level  (pulse_level),
        .timeout      (timeout)
    );

    // --- NEC Decoder ---
    nec_decoder u_nec_decoder (
        .clk          (clk),
        .rst_n        (rst_n),
        .pulse_done   (pulse_done),
        .pulse_width  (pulse_width),
        .pulse_level  (pulse_level),
        .timeout      (timeout),
        .data_valid   (data_valid),
        .decode_error (decode_error),
        .address      (address),
        .command      (command),
        .receiving    (receiving)
    );

    // --- Output Formatter ---
    output_formatter u_output_formatter (
        .clk          (clk),
        .rst_n        (rst_n),
        .address      (address),
        .command      (command),
        .valid_in     (data_valid),
        .decode_error (decode_error),
        .uart_ready   (uart_ready),
        .uart_data    (uart_data),
        .uart_tx_req  (uart_tx_req)
    );

    // --- UART Transmitter ---
    uart_tx #(
        .CLOCKS_PER_BIT(1042)  // 10 MHz / 9600 baud
    ) u_uart_tx (
        .clk          (clk),
        .rst_n        (rst_n),
        .data_in      (uart_data),
        .send_req     (uart_tx_req),
        .tx_out       (uart_tx_out),
        .ready        (uart_ready)
    );

    // ========================================================
    // LED Outputs
    // ========================================================
    assign led_valid  = data_valid;
    assign led_error  = decode_error;
    assign led_active = receiving;

endmodule
