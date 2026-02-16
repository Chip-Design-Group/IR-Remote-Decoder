module uart_tx #(
    parameter CLOCKS_PER_BIT = 1042 // 10MHz / 9600 baud
)(
    input  logic       clk,
    input  logic       rst_n,
    // from output formatter
    input  logic [7:0] data_in,
    input  logic       send_req,
    
    // to top-level
    output logic       tx_out,
    // to output formatter
    output logic       ready
);

    // Implement UART serialization
    // Start bit (0), 8 data bits (LSB first), Stop bit (1)

    // Finite State Machine states for UART transmission
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t state;

    logic [7:0] shift_reg; // Shift register holding the transmit data
    logic [2:0] bit_idx; // Index of the current data bit (0–7)
    logic [$clog2(CLOCKS_PER_BIT):0] baud_cnt; // Baud rate counter: counts clock cycles per bit

    // Transmitter is ready only when in IDLE state
    assign ready = (state == IDLE);

    // ------------------------------------------------------------
    // Main UART transmit state machine
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx_out    <= 1'b1;
            shift_reg <= 8'd0;
            bit_idx   <= 3'd0;
            baud_cnt  <= '0;
        end else begin
            case (state)
                // IDLE: Wait for a send request
                IDLE: begin
                    tx_out   <= 1'b1; // Keep TX line high while idle
                    baud_cnt <= 0; // Reset baud counter
                    bit_idx  <= 0; // Reset bit index
                    // Latch data and start transmission when requested
                    if (send_req) begin
                        shift_reg <= data_in; // Capture data exactly once
                        tx_out    <= 1'b0;    // Drive start bit
                        state     <= START;
                    end
                end
                // START: Hold start bit for exactly one bit period
                START: begin
                    if (baud_cnt == CLOCKS_PER_BIT-1) begin
                        baud_cnt <= 0;
                        tx_out   <= shift_reg[0]; // Output first data bit (LSB)
                        state    <= DATA; // Transition to DATA state
                    end else
                        baud_cnt <= baud_cnt + 1;
                end
                // DATA: Transmit 8 data bits, LSB first
                DATA: begin
                    if (baud_cnt == CLOCKS_PER_BIT-1) begin
                        baud_cnt  <= 0;
                        shift_reg <= shift_reg >> 1; // Shift to next bit
                        bit_idx   <= bit_idx + 1; // Increment bit counter

                        // After the last data bit, send stop bit
                        if (bit_idx == 3'd7) begin
                            tx_out <= 1'b1; // stop bit
                            state  <= STOP;
                        end else begin
                            tx_out <= shift_reg[1]; // Output next data bit
                        end
                    end else
                        baud_cnt <= baud_cnt + 1;
                end
                // STOP: Hold stop bit for exactly one bit period
                STOP: begin
                    if (baud_cnt == CLOCKS_PER_BIT-1) begin
                        baud_cnt <= 0;
                        state    <= IDLE;
                    end else
                        baud_cnt <= baud_cnt + 1;
                end
            endcase
        end
    end
endmodule