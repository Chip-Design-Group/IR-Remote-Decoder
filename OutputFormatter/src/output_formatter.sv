module output_formatter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] address,
    input  logic [7:0] command,
    input  logic       valid_in,
    
    output logic [7:0] uart_data,
    output logic       uart_tx_req,
    input  logic       uart_ready
);

    // TODO: State machine to send formatted string sequence
    // e.g. "A:00 C:45\n"
    // Needs to serialize bytes to UART one by one

endmodule
