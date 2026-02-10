module uart_tx #(
    parameter CLOCKS_PER_BIT = 1042 // 10MHz / 9600 baud
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data_in,
    input  logic       send_req,
    
    output logic       tx_out,
    output logic       ready
);

    // TODO: Implement UART serialization
    // Start bit (0), 8 data bits (LSB first), Stop bit (1)

endmodule
