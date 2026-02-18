`timescale 1ns/1ps

// Output Formatter Module
//
// Takes decoded protocol/address/command and formats them into a UART string.
//
// Standard output format (21 bytes):
//   "P:XXXXXXXX A:aa C:cc\n"
//   where XXXXXXXX is an 8-char protocol label, aa=8-bit addr, cc=8-bit cmd
//
// Sam32 output format (25 bytes):
//   "P:SAM32   A:aaaa C:cccc\n"
//   where aaaa is the 16-bit address and cccc the 16-bit command (addr/cmd + their inverted byte)
// Samsung36 output format (28 bytes):
//   "P:SAM36    A:aaaa ID:x C:cc\n"
//   where aaaa is the full 16-bit address from frame_data[47:32]
//   and x is the 4-bit device ID stored in frame_data[31:28]
//

module output_formatter (
    input  logic       clk,
    input  logic       rst_n,

    // input decoder
    input  logic [7:0]  address,
    input  logic [7:0]  command,
    input  logic [4:0]  protocol_id,
    input  logic        valid_in,
    input  logic        decode_error,

    // Extended frame data for Samsung48 (16-bit command)
    input  logic [47:0] frame_data,
    input  logic [5:0]  frame_bits,

    // input UART
    input  logic       uart_ready,

    // output UART
    output logic [7:0] uart_data,
    output logic       uart_tx_req
);
    // FSM States: IDLE, SEND, WAIT_UART, WAIT_ACK
    typedef enum logic [1:0] {IDLE, SEND, WAIT_UART, WAIT_ACK} state_t;
    state_t state, next_state;

    // Standard frame: "P:XXXXXXXX A:aa C:cc\n"  = 21 bytes
    // Sam32 frame: "P:SAM32   A:aaaa C:cccc\n" = 25 bytes
    // Samsung36 frame: "P:SAM36    A:aaaa ID:x C:cc\n" = 28 bytes
    localparam int FRAME_LEN_STD  = 21;
    localparam int FRAME_LEN_S32  = 25;
    localparam int FRAME_LEN_S36  = 28;
    localparam int FRAME_LEN_MAX  = 28;

    localparam logic [4:0] PROTO_SAMSUNG = 5'd8;
    localparam logic [4:0] PROTO_SAMSUNG36 = 5'd9;

    // Buffered inputs
    logic [7:0]  address_reg, command_reg;
    logic [4:0]  protocol_id_reg;
    logic [47:0] frame_data_reg;
    logic        is_sam36_reg;
    logic        is_sam32_reg;

    // ==============================
    // Buffer inputs on valid_in in IDLE state
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            address_reg     <= 8'h00;
            command_reg     <= 8'h00;
            protocol_id_reg <= 5'd0;
            frame_data_reg  <= 48'h0;
            is_sam36_reg    <= 1'b0;
            is_sam32_reg    <= 1'b0;
        end else if (valid_in && state == IDLE) begin
            address_reg     <= address;
            command_reg     <= command;
            protocol_id_reg <= protocol_id;
            frame_data_reg  <= frame_data;
            is_sam36_reg    <= (protocol_id == PROTO_SAMSUNG36);
            is_sam32_reg    <= (protocol_id == PROTO_SAMSUNG);
        end
    end

    // ==============================
    // Hex converter to ASCII
    // ==============================
    function automatic logic [7:0] hex_to_ascii(input logic [3:0] n);
        return (n < 10) ? ("0" + n) : ("A" + n - 10);
    endfunction

    function automatic logic [7:0] protocol_char(
        input logic [4:0] id,
        input logic [2:0] idx
    );
        case (id)
            5'd1: begin // NEC
                case (idx)
                    3'd0: protocol_char = "N";
                    3'd1: protocol_char = "E";
                    3'd2: protocol_char = "C";
                    default: protocol_char = " ";
                endcase
            end
            5'd8: begin // Sam32
                case (idx)
                    3'd0: protocol_char = "S";
                    3'd1: protocol_char = "A";
                    3'd2: protocol_char = "M";
                    3'd3: protocol_char = "3";
                    3'd4: protocol_char = "2";
                    default: protocol_char = " ";
                endcase
            end
            5'd9: begin // Samsung36
                case (idx)
                    3'd0: protocol_char = "S";
                    3'd1: protocol_char = "A";
                    3'd2: protocol_char = "M";
                    3'd3: protocol_char = "3";
                    3'd4: protocol_char = "6";
                    default: protocol_char = " ";
                endcase
            end
            default: begin
                case (idx)
                    3'd0: protocol_char = "U";
                    3'd1: protocol_char = "N";
                    3'd2: protocol_char = "K";
                    default: protocol_char = " ";
                endcase
            end
        endcase
    endfunction

    // Frame byte array for UART output (max 28 bytes)
    logic [7:0] frame_bytes [0:FRAME_LEN_MAX-1];

    // 16-bit values for addresses/commands
    logic [15:0] sam36_addr16;
    logic [3:0]  sam36_id;
    logic [15:0] sam32_addr16;
    logic [15:0] sam32_cmd16;
    assign sam36_addr16 = frame_data_reg[47:32];
    assign sam36_id = frame_data_reg[31:28];
    assign sam32_addr16 = {frame_data_reg[15:8], frame_data_reg[7:0]};
    assign sam32_cmd16  = {frame_data_reg[31:24], frame_data_reg[23:16]};

    always_comb begin
        // Default: fill all with spaces (safe for unused slots)
        for (int i = 0; i < FRAME_LEN_MAX; i++) frame_bytes[i] = " ";

        if (is_sam36_reg) begin
            // "P:SAM36    A:aaaa ID:x C:cc\n" = 28 bytes
            // P : S A M 3 6 _ _ _ _ A : a a a a   I D : x   C : c c \n
            // 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7
            frame_bytes[0]  = "P";
            frame_bytes[1]  = ":";
            frame_bytes[2]  = protocol_char(protocol_id_reg, 3'd0); // S
            frame_bytes[3]  = protocol_char(protocol_id_reg, 3'd1); // A
            frame_bytes[4]  = protocol_char(protocol_id_reg, 3'd2); // M
            frame_bytes[5]  = protocol_char(protocol_id_reg, 3'd3); // 3
            frame_bytes[6]  = protocol_char(protocol_id_reg, 3'd4); // 6
            frame_bytes[7]  = " ";  // 4 spaces → "SAM36    " = 9 chars total
            frame_bytes[8]  = " ";
            frame_bytes[9]  = " ";
            frame_bytes[10] = " ";
            frame_bytes[11] = "A";
            frame_bytes[12] = ":";
            frame_bytes[13] = hex_to_ascii(sam36_addr16[15:12]);
            frame_bytes[14] = hex_to_ascii(sam36_addr16[11:8]);
            frame_bytes[15] = hex_to_ascii(sam36_addr16[7:4]);
            frame_bytes[16] = hex_to_ascii(sam36_addr16[3:0]);
            frame_bytes[17] = " ";
            frame_bytes[18] = "I";
            frame_bytes[19] = "D";
            frame_bytes[20] = ":";
            frame_bytes[21] = hex_to_ascii(sam36_id);
            frame_bytes[22] = " ";
            frame_bytes[23] = "C";
            frame_bytes[24] = ":";
            frame_bytes[25] = hex_to_ascii(command_reg[7:4]);
            frame_bytes[26] = hex_to_ascii(command_reg[3:0]);
            frame_bytes[27] = 8'h0A; // newline
        end else if (is_sam32_reg) begin
            // "P:SAM32   A:aaaa C:cccc\n" = 25 bytes
            frame_bytes[0]  = "P";
            frame_bytes[1]  = ":";
            frame_bytes[2]  = protocol_char(protocol_id_reg, 3'd0);
            frame_bytes[3]  = protocol_char(protocol_id_reg, 3'd1);
            frame_bytes[4]  = protocol_char(protocol_id_reg, 3'd2);
            frame_bytes[5]  = protocol_char(protocol_id_reg, 3'd3);
            frame_bytes[6]  = protocol_char(protocol_id_reg, 3'd4);
            frame_bytes[7]  = protocol_char(protocol_id_reg, 3'd5);
            frame_bytes[8]  = protocol_char(protocol_id_reg, 3'd6);
            frame_bytes[9]  = " ";
            frame_bytes[10] = " ";
            frame_bytes[11] = "A";
            frame_bytes[12] = ":";
            frame_bytes[13] = hex_to_ascii(sam32_addr16[15:12]);
            frame_bytes[14] = hex_to_ascii(sam32_addr16[11:8]);
            frame_bytes[15] = hex_to_ascii(sam32_addr16[7:4]);
            frame_bytes[16] = hex_to_ascii(sam32_addr16[3:0]);
            frame_bytes[17] = " ";
            frame_bytes[18] = "C";
            frame_bytes[19] = ":";
            frame_bytes[20] = hex_to_ascii(sam32_cmd16[15:12]);
            frame_bytes[21] = hex_to_ascii(sam32_cmd16[11:8]);
            frame_bytes[22] = hex_to_ascii(sam32_cmd16[7:4]);
            frame_bytes[23] = hex_to_ascii(sam32_cmd16[3:0]);
            frame_bytes[24] = 8'h0A; // newline
        end else begin
            frame_bytes[0]  = "P";
            frame_bytes[1]  = ":";
            frame_bytes[2]  = protocol_char(protocol_id_reg, 3'd0);
            frame_bytes[3]  = protocol_char(protocol_id_reg, 3'd1);
            frame_bytes[4]  = protocol_char(protocol_id_reg, 3'd2);
            frame_bytes[5]  = protocol_char(protocol_id_reg, 3'd3);
            frame_bytes[6]  = protocol_char(protocol_id_reg, 3'd4);
            frame_bytes[7]  = protocol_char(protocol_id_reg, 3'd5);
            frame_bytes[8]  = protocol_char(protocol_id_reg, 3'd6);
            frame_bytes[9]  = protocol_char(protocol_id_reg, 3'd7);
            frame_bytes[10] = " ";
            frame_bytes[11] = "A";
            frame_bytes[12] = ":";
            frame_bytes[13] = hex_to_ascii(address_reg[7:4]);
            frame_bytes[14] = hex_to_ascii(address_reg[3:0]);
            frame_bytes[15] = " ";
            frame_bytes[16] = "C";
            frame_bytes[17] = ":";
            frame_bytes[18] = hex_to_ascii(command_reg[7:4]);
            frame_bytes[19] = hex_to_ascii(command_reg[3:0]);
            frame_bytes[20] = 8'h0A; // newline
        end
    end

    // Dynamic frame length
    logic [4:0] frame_len_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_len_reg <= FRAME_LEN_STD;
        else if (valid_in && state == IDLE) begin
            if (protocol_id == PROTO_SAMSUNG36)
                frame_len_reg <= FRAME_LEN_S36;
            else if (protocol_id == PROTO_SAMSUNG)
                frame_len_reg <= FRAME_LEN_S32;
            else
                frame_len_reg <= FRAME_LEN_STD;
        end
    end

    // Byte index for UART transmission
    logic [4:0] byte_idx;

    // ==============================
    // State register
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ==============================
    // Next-state logic for FSM
    // ==============================
    always_comb begin
        next_state = state;

        case (state)
            IDLE: if (valid_in) next_state = SEND;

            SEND: if (uart_ready) next_state = WAIT_ACK;

            WAIT_UART:
                if (uart_ready)
                    if (byte_idx == frame_len_reg - 1)
                        next_state = IDLE;
                    else
                        next_state = SEND;

            WAIT_ACK: if (uart_ready) next_state = WAIT_UART;

            default: next_state = IDLE;
        endcase
    end

    // ==============================
    // Byte index counter
    // ==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            byte_idx <= 0;
        else if (state == WAIT_UART && uart_ready) begin
            if (byte_idx < frame_len_reg - 1)
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
            uart_data   <= 8'h00;
            uart_tx_req <= 0;
        end else begin
            uart_tx_req <= 0; // default

            if (state == SEND && uart_ready) begin
                uart_data   <= frame_bytes[byte_idx];
                uart_tx_req <= 1;
            end
        end
    end


endmodule
