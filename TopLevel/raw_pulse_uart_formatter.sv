`timescale 1ns/1ps

//------------------------------------------------------------------------------
// raw_pulse_uart_formatter
// Emits raw pulse measurements over UART for IR protocol debugging.
// Frame format (19 bytes): "R L:x M:xx.xxx T:x\n"
//   x      = '0' or '1'
//   xx.xxx = pulse width in milliseconds (10MHz clock => 0.0001 ms per tick)
//------------------------------------------------------------------------------
module raw_pulse_uart_formatter (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        pulse_done,
    input  logic [17:0] pulse_width,
    input  logic        pulse_level,
    input  logic        pulse_timeout,

    input  logic        uart_ready,
    output logic [7:0]  uart_data,
    output logic        uart_tx_req
);
    typedef enum logic [1:0] {IDLE, SEND, WAIT_UART, WAIT_ACK} state_t;
    state_t state, next_state;

    localparam int FRAME_LEN = 19;
    localparam int LAST_IDX  = FRAME_LEN - 1;
    localparam logic [17:0] MIN_PULSE_WIDTH = 18'd1000; // filter sub-100us glitches

    logic [17:0] width_reg;
    logic        level_reg;
    logic        timeout_reg;

    logic [7:0] frame_bytes [0:LAST_IDX];
    logic [4:0] byte_idx;
    logic [17:0] ms_int;
    logic [9:0]  ms_frac3;

    function automatic logic [7:0] bit_to_ascii(input logic b);
        bit_to_ascii = b ? "1" : "0";
    endfunction

    function automatic logic [7:0] dec_to_ascii(input logic [3:0] n);
        dec_to_ascii = "0" + n;
    endfunction

    wire raw_valid = pulse_done && ((pulse_width >= MIN_PULSE_WIDTH) || pulse_timeout);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            width_reg   <= 18'd0;
            level_reg   <= 1'b0;
            timeout_reg <= 1'b0;
        end else if (raw_valid && state == IDLE) begin
            width_reg   <= pulse_width;
            level_reg   <= pulse_level;
            timeout_reg <= pulse_timeout;
        end
    end

    always_comb begin
        frame_bytes[0]  = "R";
        frame_bytes[1]  = " ";
        frame_bytes[2]  = "L";
        frame_bytes[3]  = ":";
        frame_bytes[4]  = bit_to_ascii(level_reg);
        frame_bytes[5]  = " ";
        frame_bytes[6]  = "M";
        frame_bytes[7]  = ":";
        frame_bytes[8]  = dec_to_ascii(ms_int / 10);
        frame_bytes[9]  = dec_to_ascii(ms_int % 10);
        frame_bytes[10] = ".";
        frame_bytes[11] = dec_to_ascii(ms_frac3 / 100);
        frame_bytes[12] = dec_to_ascii((ms_frac3 % 100) / 10);
        frame_bytes[13] = dec_to_ascii(ms_frac3 % 10);
        frame_bytes[14] = " ";
        frame_bytes[15] = "T";
        frame_bytes[16] = ":";
        frame_bytes[17] = bit_to_ascii(timeout_reg);
        frame_bytes[18] = 8'h0A;
    end

    always_comb begin
        ms_int  = width_reg / 18'd10000;
        ms_frac3 = (width_reg % 18'd10000) / 18'd10;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (raw_valid) next_state = SEND;
            SEND: if (uart_ready) next_state = WAIT_ACK;
            WAIT_ACK: if (uart_ready) next_state = WAIT_UART;
            WAIT_UART:
                if (uart_ready)
                    if (byte_idx == LAST_IDX) next_state = IDLE;
                    else next_state = SEND;
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            byte_idx <= 0;
        else if (state == WAIT_UART && uart_ready) begin
            if (byte_idx < LAST_IDX) byte_idx <= byte_idx + 1'b1;
            else byte_idx <= 0;
        end else if (state == IDLE)
            byte_idx <= 0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_data   <= 8'h00;
            uart_tx_req <= 1'b0;
        end else begin
            uart_tx_req <= 1'b0;
            if (state == SEND && uart_ready) begin
                uart_data   <= frame_bytes[byte_idx];
                uart_tx_req <= 1'b1;
            end
        end
    end
endmodule
