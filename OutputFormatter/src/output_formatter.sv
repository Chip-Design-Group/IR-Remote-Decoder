`timescale 1ns/1ps
"""
Output Formatter Module which takes decoded NEC address and command,
formats them into a string, and sends it out via UART. 
The output format is "A:xx C:yy\n" where xx and yy are the hexadecimal 
representations of the address and command.
"""

module output_formatter (
    input  logic       clk,
    input  logic       rst_n,

    // input nec
    input  logic [7:0] address,
    input  logic [7:0] command,
    input  logic       valid_in,
    input  logic       decode_error,

    // input UART
    input  logic       uart_ready,

    // output UART
    output logic [7:0] uart_data,
    output logic       uart_tx_req
);
    // FSM States: IDLE, SEND, WAIT_UART
    typedef enum logic [1:0] {IDLE, SEND, WAIT_UART, WAIT_ACK} state_t;
    state_t state, next_state;

    // Buffered inputs
    logic [7:0] address_reg, command_reg;

    // ==============================
    // buffer address and command on valid_in in IDLE state
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        // Reset Data
        if (!rst_n) begin
            address_reg <= '0;
            command_reg <= '0;
        end else if (valid_in && state == IDLE) begin
            address_reg <= address;
            command_reg <= command;
        end
    end

    // ==============================
    // Hex converter to ASCII
    // ==============================
    function automatic logic [7:0] hex_to_ascii(input logic [3:0] n);
        return (n < 10) ? ("0" + n) : ("A" + n - 10);
    endfunction

    // Frame byte array for UART output
    logic [7:0] frame_bytes [0:9]; // 10 bytes: "A:xx C:yy\n"

    always_comb begin
        frame_bytes[0] = "A";
        frame_bytes[1] = ":";
        frame_bytes[2] = hex_to_ascii(address_reg[7:4]);
        frame_bytes[3] = hex_to_ascii(address_reg[3:0]);
        frame_bytes[4] = " ";
        frame_bytes[5] = "C";
        frame_bytes[6] = ":";
        frame_bytes[7] = hex_to_ascii(command_reg[7:4]);
        frame_bytes[8] = hex_to_ascii(command_reg[3:0]);
        frame_bytes[9] = 8'h0A; // newline character
    end

    // Byte index for UART transmission
    logic [3:0] byte_idx;
    
    // ==============================
    // State register
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            byte_idx <= 0;
        end else begin
            state <= next_state;
        end
    end

    // ==============================
    // Next-state logic for FSM
    // logic of the FSM to send, if the UART is ready to recieve bytes
    // ==============================
    always_comb begin
        next_state = state;

        case (state)
            IDLE: if (valid_in) next_state = SEND; // Switch to SEND state if input is valid

            SEND: if (uart_ready) next_state = WAIT_ACK; // after Send wait for UART to be ready

            WAIT_UART:
                if (uart_ready) 
                    if (byte_idx == 9) // last byte done, switch to idle
                        next_state = IDLE;
                    else
                        next_state = SEND;
            WAIT_ACK: if (uart_ready) next_state = WAIT_UART; // wait one cycle for ACK

            default: next_state = IDLE;
        endcase
    end

    // ==============================
    // buffer byte index for UART transmission
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            byte_idx <= 0;
        else if (state == WAIT_UART && uart_ready) begin
            if (byte_idx < 9)
                byte_idx <= byte_idx + 1;
            else
                byte_idx <= 0;
        end else if (state == IDLE)
            byte_idx <= 0;
    end

    // ==============================
    // UART output
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_data   <= 0;
            uart_tx_req <= 0;
        end else begin
            uart_tx_req <= 0; // default

            if (state == SEND && uart_ready) begin
                uart_data   <= frame_bytes[byte_idx];
                uart_tx_req <= (state == SEND) && uart_ready; // Signal to send byte
            end
        end
    end
    

endmodule
