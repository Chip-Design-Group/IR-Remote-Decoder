module output_formatter (
    input  logic       clk,
    input  logic       rst_n,

    // From nec_decoder
    input  logic [7:0] address,
    input  logic [7:0] command,
    input  logic       valid_in,
    input  logic       decode_error,

    // From UART
    input  logic       uart_ready,


    output logic [7:0] uart_data,
    output logic       uart_tx_req
);

    // FSM States
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

    // buffered data
    logic [7:0] address_reg;
    logic [7:0] command_reg;

    // Hex → ASCII function
    function logic [7:0] hex_to_ascii(input logic [3:0] nibble);
        if (nibble < 10)
            hex_to_ascii = "0" + nibble;
        else
            hex_to_ascii = "A" + (nibble - 10);
    endfunction

    // Buffer incoming data
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            address_reg <= 8'h00;
            command_reg <= 8'h00;
        end else if (valid_in && state == IDLE) begin
            address_reg <= address;
            command_reg <= command;
        end
    end

    // State-Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // FSM + UART-Ausgabe
    always_comb begin
        next_state  = state;
        uart_tx_req = 0;
        uart_data   = 8'h00;

        case (state)
            IDLE: begin
                if (valid_in)
                    next_state = SEND_A;
            end

            SEND_A: if (uart_ready) begin
                uart_data = "A";
                uart_tx_req = 1;
                next_state = SEND_COLON1;
            end

            SEND_COLON1: if (uart_ready) begin
                uart_data = ":";
                uart_tx_req = 1;
                next_state = SEND_ADDR_HIGH;
            end

            SEND_ADDR_HIGH: if (uart_ready) begin
                uart_data = hex_to_ascii(address_reg[7:4]);
                uart_tx_req = 1;
                next_state = SEND_ADDR_LOW;
            end

            SEND_ADDR_LOW: if (uart_ready) begin
                uart_data = hex_to_ascii(address_reg[3:0]);
                uart_tx_req = 1;
                next_state = SEND_SPACE;
            end

            SEND_SPACE: if (uart_ready) begin
                uart_data = " ";
                uart_tx_req = 1;
                next_state = SEND_C;
            end

            SEND_C: if (uart_ready) begin
                uart_data = "C";
                uart_tx_req = 1;
                next_state = SEND_COLON2;
            end

            SEND_COLON2: if (uart_ready) begin
                uart_data = ":";
                uart_tx_req = 1;
                next_state = SEND_CMD_HIGH;
            end

            SEND_CMD_HIGH: if (uart_ready) begin
                uart_data = hex_to_ascii(command_reg[7:4]);
                uart_tx_req = 1;
                next_state = SEND_CMD_LOW;
            end

            SEND_CMD_LOW: if (uart_ready) begin
                uart_data = hex_to_ascii(command_reg[3:0]);
                uart_tx_req = 1;
                next_state = SEND_NEWLINE;
            end

            SEND_NEWLINE: if (uart_ready) begin
                uart_data = 8'h0A; // '\n'
                uart_tx_req = 1;
                next_state = IDLE;
            end
        endcase
    end

endmodule
