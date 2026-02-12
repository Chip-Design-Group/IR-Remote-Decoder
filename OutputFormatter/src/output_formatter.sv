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
        SEND_NEWLINE
    } state_t;

    state_t state, next_state;

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
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always_comb begin
        next_state = state;

        case (state)
            IDLE: if (valid_in) next_state = SEND_A;
            SEND_A:        if (uart_ready) next_state = SEND_COLON1;
            SEND_COLON1:   if (uart_ready) next_state = SEND_ADDR_HIGH;
            SEND_ADDR_HIGH:if (uart_ready) next_state = SEND_ADDR_LOW;
            SEND_ADDR_LOW: if (uart_ready) next_state = SEND_SPACE;
            SEND_SPACE:    if (uart_ready) next_state = SEND_C;
            SEND_C:        if (uart_ready) next_state = SEND_COLON2;
            SEND_COLON2:   if (uart_ready) next_state = SEND_CMD_HIGH;
            SEND_CMD_HIGH: if (uart_ready) next_state = SEND_CMD_LOW;
            SEND_CMD_LOW:  if (uart_ready) next_state = SEND_NEWLINE;
            SEND_NEWLINE:  if (uart_ready) next_state = IDLE;
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
                endcase
            end
        end
    end

endmodule
