`timescale 1ns/1ps

module output_formatter (
    input  logic       clk,
    input  logic       rst_n,

    input  logic [7:0] address,
    input  logic [7:0] command,
    input  logic       valid_in,
    input  logic       decode_error,

    input  logic       uart_ready,

    output logic [7:0] uart_data,
    output logic       uart_tx_req
);

    typedef enum logic [3:0] {
        IDLE,
        SEND_A,
        SEND_COLON1,
        SEND_ADDR_HIGH,
        SEND_ADDR_LOW,
        SEND_SPACE,
        SEND_C,
        SEND_COLON2,
        SEND_CMD_HIGH,
        SEND_CMD_LOW,
        SEND_NEWLINE,
        WAIT_ACK,       // 1-cycle delay for UART to deassert ready
        WAIT_UART       // Wait for UART to finish (ready goes high again)
    } state_t;

    state_t state, next_state;
    state_t return_state, return_state_next;

    logic [7:0] address_reg;
    logic [7:0] command_reg;

    function logic [7:0] hex_to_ascii(input logic [3:0] nibble);
        if (nibble < 10)
            hex_to_ascii = "0" + nibble;
        else
            hex_to_ascii = "A" + (nibble - 10);
    endfunction

    // Buffer inputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            address_reg <= 8'h00;
            command_reg <= 8'h00;
        end else if (valid_in && state == IDLE) begin
            address_reg <= address;
            command_reg <= command;
        end
    end

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            return_state <= IDLE;
        end else begin
            state        <= next_state;
            return_state <= return_state_next;
        end
    end

    // Next-state logic
    always_comb begin
        next_state        = state;
        return_state_next = return_state;

        case (state)
            IDLE: if (valid_in) next_state = SEND_A;

            SEND_A: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_COLON1;
            end

            SEND_COLON1: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_ADDR_HIGH;
            end

            SEND_ADDR_HIGH: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_ADDR_LOW;
            end

            SEND_ADDR_LOW: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_SPACE;
            end

            SEND_SPACE: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_C;
            end

            SEND_C: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_COLON2;
            end

            SEND_COLON2: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_CMD_HIGH;
            end

            SEND_CMD_HIGH: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_CMD_LOW;
            end

            SEND_CMD_LOW: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = SEND_NEWLINE;
            end

            SEND_NEWLINE: if (uart_ready) begin
                next_state = WAIT_ACK;
                return_state_next = IDLE;
            end

            // 1-cycle delay: let UART latch send_req and deassert ready
            WAIT_ACK: next_state = WAIT_UART;

            // Wait for UART to finish transmitting (ready goes high again)
            WAIT_UART: if (uart_ready) begin
                next_state = return_state;
            end
        endcase
    end

    // REGISTERED UART OUTPUTS
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_req <= 0;
            uart_data   <= 8'h00;
        end else begin
            uart_tx_req <= 0;

            if (uart_ready) begin
                case (state)
                    SEND_A:         begin uart_data <= "A"; uart_tx_req <= 1; end
                    SEND_COLON1:    begin uart_data <= ":"; uart_tx_req <= 1; end
                    SEND_ADDR_HIGH: begin uart_data <= hex_to_ascii(address_reg[7:4]); uart_tx_req <= 1; end
                    SEND_ADDR_LOW:  begin uart_data <= hex_to_ascii(address_reg[3:0]); uart_tx_req <= 1; end
                    SEND_SPACE:     begin uart_data <= " "; uart_tx_req <= 1; end
                    SEND_C:         begin uart_data <= "C"; uart_tx_req <= 1; end
                    SEND_COLON2:    begin uart_data <= ":"; uart_tx_req <= 1; end
                    SEND_CMD_HIGH:  begin uart_data <= hex_to_ascii(command_reg[7:4]); uart_tx_req <= 1; end
                    SEND_CMD_LOW:   begin uart_data <= hex_to_ascii(command_reg[3:0]); uart_tx_req <= 1; end
                    SEND_NEWLINE:   begin uart_data <= 8'h0A; uart_tx_req <= 1; end
                    default: ;
                endcase
            end
        end
    end

endmodule
