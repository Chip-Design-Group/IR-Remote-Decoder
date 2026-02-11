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

    // states
    parameter logic [1:0] idle_state  = 2'b00;
    parameter logic [1:0] start_state = 2'b01;
    parameter logic [1:0] data_state  = 2'b10;
    parameter logic [1:0] stop_state  = 2'b11;

    // internal registers
    logic [1:0] state, next_state;
    logic [7:0] data_reg;
    logic [2:0] index; // 0..7
    logic [31:0] baud_cnt;

    // state and datapath update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= idle_state;
            data_reg <= 8'd0;
            index    <= 3'd0;
            baud_cnt <= 32'd0;
            tx_out   <= 1'b1; // idle high
        end else begin
            state <= next_state;

            case (state)
                idle_state: begin
                    tx_out <= 1'b1;
                    baud_cnt <= 32'd0;
                    index <= 3'd0;
                    if (send_req) begin
                        data_reg <= data_in;
                        // start bit driven immediately; remain in start state until baud interval
                        tx_out <= 1'b0;
                    end
                end

                start_state: begin
                    // hold start bit low for CLOCKS_PER_BIT clocks
                    if (baud_cnt == CLOCKS_PER_BIT - 1) begin
                        baud_cnt <= 32'd0;
                    end else begin
                        baud_cnt <= baud_cnt + 32'd1;
                    end
                end

                data_state: begin
                    // drive LSB
                    tx_out <= data_reg[0];
                    if (baud_cnt == CLOCKS_PER_BIT - 1) begin
                        baud_cnt <= 32'd0;
                        data_reg <= (data_reg >> 1);
                        if (index == 3'd7)
                            index <= 3'd0;
                        else
                            index <= index + 3'd1;
                    end else begin
                        baud_cnt <= baud_cnt + 32'd1;
                    end
                end

                stop_state: begin
                    tx_out <= 1'b1;
                    if (baud_cnt == CLOCKS_PER_BIT - 1) begin
                        baud_cnt <= 32'd0;
                    end else begin
                        baud_cnt <= baud_cnt + 32'd1;
                    end
                end

                default: begin end
            endcase
        end
    end

    // next state logic
    always_comb begin
        next_state = state;
        case (state)
            idle_state: if (send_req) next_state = start_state;

            start_state: if (baud_cnt == CLOCKS_PER_BIT - 1) next_state = data_state;

            data_state: if (baud_cnt == CLOCKS_PER_BIT - 1 && index == 3'd7) next_state = stop_state;

            stop_state: if (baud_cnt == CLOCKS_PER_BIT - 1) next_state = idle_state;

            default: next_state = idle_state;
        endcase
    end

    // ready is high only in IDLE
    assign ready = (state == idle_state);

endmodule
