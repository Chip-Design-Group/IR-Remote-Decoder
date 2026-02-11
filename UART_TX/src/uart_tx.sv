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

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t state;

    logic [7:0] shift_reg;
    logic [2:0] bit_idx;
    logic [$clog2(CLOCKS_PER_BIT):0] baud_cnt;

    assign ready = (state == IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx_out    <= 1'b1;
            shift_reg <= 8'd0;
            bit_idx   <= 3'd0;
            baud_cnt  <= '0;
        end else begin
            case (state)
                IDLE: begin
                    tx_out   <= 1'b1;
                    baud_cnt <= 0;
                    bit_idx  <= 0;
                    if (send_req) begin
                        shift_reg <= data_in;   // 🔒 latch ONCE
                        tx_out    <= 1'b0;       // start bit
                        state     <= START;
                    end
                end

                START: begin
                    if (baud_cnt == CLOCKS_PER_BIT-1) begin
                        baud_cnt <= 0;
                        tx_out   <= shift_reg[0];
                        state    <= DATA;
                    end else
                        baud_cnt <= baud_cnt + 1;
                end

                DATA: begin
                    if (baud_cnt == CLOCKS_PER_BIT-1) begin
                        baud_cnt  <= 0;
                        shift_reg <= shift_reg >> 1;
                        bit_idx   <= bit_idx + 1;

                        if (bit_idx == 3'd7) begin
                            tx_out <= 1'b1; // stop bit
                            state  <= STOP;
                        end else begin
                            tx_out <= shift_reg[1];
                        end
                    end else
                        baud_cnt <= baud_cnt + 1;
                end

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