module ir_decoder_top (
    input  logic clk_PAD,
    input  logic rst_n_PAD,
    input  logic ir_in_PAD,
    
    output logic uart_tx_PAD,
    output logic led_valid_PAD,
    output logic led_error_PAD,
    output logic led_active_PAD
);

    // Internal signals
    logic clk, rst_n, ir_in;
    logic uart_tx;
    logic led_valid, led_error, led_active;

    // TODO: Instantiate IO Pads (sg13g2_IOPadIn / Out)
    
    // TODO: Instantiate and connect modules:
    // edge_detector -> pulse_timer -> nec_decoder -> output_formatter -> uart_tx

endmodule
