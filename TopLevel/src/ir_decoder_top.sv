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

    // ========================================================
    // Clock Divider: 100 MHz -> 10 MHz
    // ========================================================
    logic clk_10mhz;
    logic [3:0] clk_div_cnt;

`ifndef SIMULATION
    // Divide by 10: Toggle every 5 cycles
    always_ff @(posedge clk_PAD) begin
        if (rst_n_PAD) begin // Reset is now Active-High (Arty A7 BTN0)
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
    logic clk, rst_n, ir_in;
    logic uart_tx_out;
    logic led_valid, led_error, led_active;

`ifdef SIMULATION
    assign clk = clk_10mhz;
`else
    // Use global buffer for the derived clock to improve timing routing
    BUFG clk_bufg_i (.I(clk_10mhz), .O(clk));
`endif
    
    // Internal rst_n is active-low for submodules
    // Internal rst_n is active-low (BTN0 is active high, BTN0 pressed -> Reset)
    // Wait... if BTN0 is HIGH (Reset), then rst_n (Active Low) should be LOW.
    // So current logic `assign rst_n = ~rst_n_PAD` IS correct for BTN0 (D9).
    // If I switch to C2 (CK_RST, Active Low), then `assign rst_n = rst_n_PAD`.
    // I am switching to C2.
    // assign rst_n = rst_n_PAD; // CK_RST (C2) is already Active Low.
    
    // Debug mode: force core out of reset to isolate IO/UART behavior.
    assign rst_n = 1'b1;


    // ========================================================
    // Internal Test Pattern Generator
    // ========================================================
`ifndef SIMULATION
    logic ir_test_signal;
    logic [31:0] test_data = 32'hBA45FF00; // Cmd: 0x45 (~0xBA), Addr: 0x00 (~0xFF)
    logic [19:0] test_timer;
    logic [5:0]  test_bit_cnt;
    enum logic [2:0] {
        T_IDLE, T_LEADER_LOW, T_LEADER_HIGH, T_DATA_LOW, T_DATA_HIGH, T_STOP
    } test_state;

    // Simple pattern generator triggered by BTN1 (active-high)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_state <= T_IDLE;
            ir_test_signal <= 1'b1;
            test_timer <= 0;
            test_bit_cnt <= 0;
        end else begin
            case (test_state)
                T_IDLE: begin
                    ir_test_signal <= 1'b1;
                    if (1'b0) begin // Trigger disabled for debug (btn_test_PAD used for formatter)
                        test_state <= T_LEADER_LOW;
                        test_timer <= 0;
                    end
                end
                T_LEADER_LOW: begin // 9ms LOW
                    ir_test_signal <= 1'b0;
                    if (test_timer >= 90000) begin
                        test_state <= T_LEADER_HIGH;
                        test_timer <= 0;
                    end else test_timer <= test_timer + 1;
                end
                T_LEADER_HIGH: begin // 4.5ms HIGH
                    ir_test_signal <= 1'b1;
                    if (test_timer >= 45000) begin
                        test_state <= T_DATA_LOW;
                        test_timer <= 0;
                        test_bit_cnt <= 0;
                    end else test_timer <= test_timer + 1;
                end
                T_DATA_LOW: begin // 560us LOW
                    ir_test_signal <= 1'b0;
                    if (test_timer >= 5600) begin
                        test_state <= T_DATA_HIGH;
                        test_timer <= 0;
                    end else test_timer <= test_timer + 1;
                end
                T_DATA_HIGH: begin // 560us (0) or 1.69ms (1) HIGH
                    ir_test_signal <= 1'b1;
                    if ((test_data[test_bit_cnt] && test_timer >= 16900) || 
                        (!test_data[test_bit_cnt] && test_timer >= 5600)) begin
                        if (test_bit_cnt == 31) test_state <= T_STOP;
                        else begin
                            test_bit_cnt <= test_bit_cnt + 1;
                            test_state <= T_DATA_LOW;
                        end
                        test_timer <= 0;
                    end else test_timer <= test_timer + 1;
                end
                T_STOP: begin // Final 560us burst
                    ir_test_signal <= 1'b0;
                    if (test_timer >= 5600) begin
                        test_state <= T_IDLE;
                        ir_test_signal <= 1'b1;
                    end else test_timer <= test_timer + 1;
                end
            endcase
        end
    end

    // Combine external IR and test generator (OR since idle is HIGH)
    assign ir_in = ir_in_PAD & ir_test_signal;
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
    logic        btn_ff1, btn_ff2, btn_prev;
    logic        btn_pulse;

    // Synchronize BTN1 into clk domain and create one-cycle trigger pulse.
    always_ff @(posedge clk) begin
        btn_ff1  <= btn_test_PAD;
        btn_ff2  <= btn_ff1;
        btn_prev <= btn_ff2;
    end
    assign btn_pulse = btn_ff2 & ~btn_prev;

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
    // --- Output Formatter ---
    // DEBUG MODE: Triggered by Button 1, Fixed Data
    output_formatter u_output_formatter (
        .clk          (clk),
        .rst_n        (rst_n),
        .address      (8'hAA),
        .command      (8'hBB),
        .valid_in     (btn_pulse), // one-shot trigger
        .decode_error (1'b0),
        .uart_ready   (uart_ready),
        .uart_data    (uart_data),
        .uart_tx_req  (uart_tx_req)
    );

    // --- UART Transmitter ---
    uart_tx #(
        .CLOCKS_PER_BIT(CLOCKS_PER_BIT)
    ) u_uart_tx (
        .clk          (clk),
        .rst_n        (rst_n),
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
    // assign led_valid_PAD = hb_cnt_100[24]; // Blink LED 4 (Removed for UART Ready mapping)
    // assign led_error_PAD = led_error; // DISABLED: Mapped to UART TX for debug

    // Heartbeat 1 (100MHz domain): Blinks LED 7 every ~0.67s (2^26 cycles)
    // PROOF OF LIFE: If this blinks, FPGA is programmed and clk_PAD works.
    logic [26:0] hb_cnt_100;
    always_ff @(posedge clk_PAD) begin
        hb_cnt_100 <= hb_cnt_100 + 1;
    end
    // Old LED assignments removed to prevent multi-driver errors.
    // assign led_heartbeat_PAD = hb_cnt_100[26];
    // assign led_active_PAD = receiving ? 1'b1 : hb_cnt_10[23];

    // Heartbeat 2 (10MHz domain): Blinks LED 6 (Active) when idle
    // PROOF OF DIVIDER: If this blinks, clock divider works.
    logic [23:0] hb_cnt_10;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb_cnt_10 <= 0;
        else hb_cnt_10 <= hb_cnt_10 + 1;
    end
    
    // DEEP DIAGNOSTIC MAPPINGS:
    
    // LED 7 (LD7) = 100MHz heartbeat (board alive + input clock alive).
    assign led_heartbeat_PAD = hb_cnt_100[26];

    // LED 6 (LD6) = 10MHz Heartbeat (Blinking).
    // If OFF/Solid, 10MHz Clock is dead/stuck.
    assign led_active_PAD = hb_cnt_10[23];

    // LED 5 (LD5) = FSM Trigger Attempt (uart_tx_req).
    // If this flashes when you press BTN1, FSM is working!
    // If this stays OFF, FSM is DEAD/IDLE.
    assign led_error_PAD = uart_tx_req;

    // LED 4 (LD4) = UART Ready (ON = Ready, OFF = Busy).
    // Should be ON normally. Flickers OFF when sending.
    assign led_valid_PAD = uart_ready;
    
endmodule
