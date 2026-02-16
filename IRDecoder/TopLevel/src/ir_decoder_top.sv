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
//   led_valid  = Blinks to show new program version (hb[24])
//   led_error  = decode_error pulse
//   led_active = receiving signal (high during decoding)
// ============================================================

module ir_decoder_top (
    input  logic clk_PAD,
    input  logic rst_n_PAD,
    input  logic ir_in_PAD,
    input  logic btn_test_PAD,

    output logic uart_tx_PAD,
    output logic led_valid_PAD,
    output logic led_error_PAD,
    output logic led_active_PAD,
    output logic led_heartbeat_PAD
);

    // Core interconnect signals
    logic clk, rst_n, ir_in;
    logic uart_tx_out;
    logic led_valid, led_error, led_active;

    // ========================================================
    // Clock Divider: 100 MHz -> 10 MHz
    // ========================================================
    logic clk_10mhz;
    logic [3:0] clk_div_cnt;

`ifndef SIMULATION
    // Divide by 10: Toggle every 5 cycles
    always_ff @(posedge clk_PAD) begin
        if (!rst_n) begin // Reset active-low (run=1, reset=0)
            clk_div_cnt <= 0;
            clk_10mhz   <= 0;
        end else begin
            if (clk_div_cnt == 4) begin
                clk_div_cnt <= 0;
                clk_10mhz   <= ~clk_10mhz;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end
    end
`else
    // Simulation: feed core clock directly from testbench clock.
    assign clk_10mhz = clk_PAD;
`endif

    // Use the divided clock for the core logic
`ifdef SIMULATION
    assign clk = clk_10mhz;
`else
    // Use global buffer for the derived clock to improve timing routing
    BUFG clk_bufg_i (.I(clk_10mhz), .O(clk));
`endif
    
`ifdef DEBUG_NO_IR
    // Bring-up mode without IR sensor: keep core running independent of reset switch.
    assign rst_n = 1'b1;
`elsif SIMULATION
    // Keep legacy active-high reset behavior in cocotb tests.
    assign rst_n = ~rst_n_PAD;
`else
    // Hardware: SW0 is active-low reset (up=1 run, down=0 reset).
    assign rst_n = rst_n_PAD;
`endif

    // Optional raw-input debug mode: keep decoder/UART chain in reset
    // so only input activity is observed.
    logic rst_n_decode;
`ifdef DEBUG_INPUT_ONLY
    assign rst_n_decode = 1'b0;
`else
    assign rst_n_decode = rst_n;
`endif

    // Synchronize BTN1 into clk domain and create one-cycle trigger pulse.
    logic btn_ff1, btn_ff2, btn_prev;
    logic btn_pulse;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_ff1  <= 1'b0;
            btn_ff2  <= 1'b0;
            btn_prev <= 1'b0;
        end else begin
            btn_ff1  <= btn_test_PAD;
            btn_ff2  <= btn_ff1;
            btn_prev <= btn_ff2;
        end
    end
    // Trigger only on rising edge: one frame per button press.
    assign btn_pulse = btn_ff2 & ~btn_prev;

    // ========================================================
    // Internal NEC Test Pattern Generator (optional)
    // Enable with DEBUG_NO_IR for bring-up without IR sensor.
    // ========================================================
`ifdef DEBUG_NO_IR
    logic ir_test_signal;
    logic [31:0] test_data = 32'hBA45FF00; // Addr=0x00, Cmd=0x45 (LSB-first packed)
    logic [19:0] test_timer;
    logic [5:0]  test_bit_cnt;
    enum logic [2:0] {
        T_IDLE, T_LEADER_LOW, T_LEADER_HIGH, T_DATA_LOW, T_DATA_HIGH, T_STOP
    } test_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_state     <= T_IDLE;
            ir_test_signal <= 1'b1;
            test_timer     <= 20'd0;
            test_bit_cnt   <= 6'd0;
        end else begin
            case (test_state)
                T_IDLE: begin
                    ir_test_signal <= 1'b1;
                    if (btn_pulse) begin
                        test_state <= T_LEADER_LOW;
                        test_timer <= 20'd0;
                    end
                end
                T_LEADER_LOW: begin
                    ir_test_signal <= 1'b0; // 9ms mark
                    if (test_timer >= 20'd90000) begin
                        test_state <= T_LEADER_HIGH;
                        test_timer <= 20'd0;
                    end else test_timer <= test_timer + 1'b1;
                end
                T_LEADER_HIGH: begin
                    ir_test_signal <= 1'b1; // 4.5ms space
                    if (test_timer >= 20'd45000) begin
                        test_state   <= T_DATA_LOW;
                        test_timer   <= 20'd0;
                        test_bit_cnt <= 6'd0;
                    end else test_timer <= test_timer + 1'b1;
                end
                T_DATA_LOW: begin
                    ir_test_signal <= 1'b0; // 560us mark
                    if (test_timer >= 20'd5600) begin
                        test_state <= T_DATA_HIGH;
                        test_timer <= 20'd0;
                    end else test_timer <= test_timer + 1'b1;
                end
                T_DATA_HIGH: begin
                    ir_test_signal <= 1'b1; // 560us/1690us space
                    if ((test_data[test_bit_cnt] && test_timer >= 20'd16900) ||
                        (!test_data[test_bit_cnt] && test_timer >= 20'd5600)) begin
                        if (test_bit_cnt == 6'd31) test_state <= T_STOP;
                        else begin
                            test_bit_cnt <= test_bit_cnt + 1'b1;
                            test_state   <= T_DATA_LOW;
                        end
                        test_timer <= 20'd0;
                    end else test_timer <= test_timer + 1'b1;
                end
                T_STOP: begin
                    ir_test_signal <= 1'b0; // final 560us mark
                    if (test_timer >= 20'd5600) begin
                        test_state     <= T_IDLE;
                        ir_test_signal <= 1'b1;
                    end else test_timer <= test_timer + 1'b1;
                end
                default: test_state <= T_IDLE;
            endcase
        end
    end

    // In no-sensor debug mode, drive decoder directly from internal generator.
    assign ir_in = ir_test_signal;
`else
    assign ir_in = ir_in_PAD;
`endif

    assign uart_tx_PAD   = uart_tx_out;

    // Derived parameter for UART (Standard 10MHz / 9600)
    localparam int CLOCKS_PER_BIT = 1042;

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
        .rst_n        (rst_n_decode),
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
        .rst_n        (rst_n_decode),
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
        .rst_n        (rst_n_decode),
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
        .CLOCKS_PER_BIT(CLOCKS_PER_BIT)
    ) u_uart_tx (
        .clk          (clk),
        .rst_n        (rst_n_decode),
        .data_in      (uart_data),
        .send_req     (uart_tx_req),
        .tx_out       (uart_tx_out),
        .ready        (uart_ready)
    );

    // ========================================================
    // ========================================================
    // LED Outputs & Heartbeat
    // ========================================================
    assign led_valid = data_valid;
    assign led_error = decode_error;

    // Heartbeat 1 (100MHz domain): Blinks LED 7 every ~0.67s (2^26 cycles)
    // PROOF OF LIFE: If this blinks, FPGA is programmed and clk_PAD works.
    logic [26:0] hb_cnt_100;
    always_ff @(posedge clk_PAD) begin
        hb_cnt_100 <= hb_cnt_100 + 1;
    end
    // LED 7 (LD7) = 100MHz heartbeat (board alive + input clock alive).
    assign led_heartbeat_PAD = hb_cnt_100[26];

    // DEBUG: stretch detected IR edges so activity is visible on LED6.
    logic [18:0] ir_activity_stretch;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_activity_stretch <= 19'd0;
        end else if (edge_rise || edge_fall) begin
            ir_activity_stretch <= 19'd500000; // ~50ms at 10MHz
        end else if (ir_activity_stretch != 19'd0) begin
            ir_activity_stretch <= ir_activity_stretch - 1'b1;
        end
    end

    // DEBUG: stretch low level on synchronized IR input so short NEC marks are visible.
    logic [18:0] ir_low_stretch;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_low_stretch <= 19'd0;
        end else if (!ir_in_sync) begin
            ir_low_stretch <= 19'd500000; // ~50ms at 10MHz
        end else if (ir_low_stretch != 19'd0) begin
            ir_low_stretch <= ir_low_stretch - 1'b1;
        end
    end

    // Stretch decode result pulses so they are visible on LEDs in hardware.
    logic [18:0] valid_stretch;
    logic [18:0] error_stretch;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_stretch <= 19'd0;
            error_stretch <= 19'd0;
        end else begin
            if (data_valid) begin
                valid_stretch <= 19'd500000; // ~50ms at 10MHz
            end else if (valid_stretch != 19'd0) begin
                valid_stretch <= valid_stretch - 1'b1;
            end

            if (decode_error) begin
                error_stretch <= 19'd500000; // ~50ms at 10MHz
            end else if (error_stretch != 19'd0) begin
                error_stretch <= error_stretch - 1'b1;
            end
        end
    end

`ifdef DEBUG_INPUT_ONLY
    assign led_valid_PAD  = (ir_low_stretch != 19'd0);           // low level activity (stretched)
    assign led_error_PAD  = (ir_activity_stretch != 19'd0) | ~rst_n; // any edge activity + reset indicator
    assign led_active_PAD = ~ir_in_sync;                          // direct pin echo (active-low IR input)
`elsif DEBUG_IR_INPUT
    assign led_valid_PAD  = (ir_low_stretch != 19'd0);   // raw IR low activity
    assign led_error_PAD  = decode_error | ~rst_n;        // reset indicator on LED5
    assign led_active_PAD = ~ir_in_sync;                  // direct pin echo (active-low IR input)
`else
    assign led_active_PAD = receiving;
    assign led_error_PAD  = (error_stretch != 19'd0) | ~rst_n; // stretched decode error + reset indicator
    assign led_valid_PAD  = (valid_stretch != 19'd0);          // stretched data valid
`endif
    
endmodule
