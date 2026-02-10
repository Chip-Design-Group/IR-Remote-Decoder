module bit_decoder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] pulse_width,
    input  logic        pulse_valid,
    
    output logic        is_logical_0,
    output logic        is_logical_1,
    output logic        is_start_burst,
    output logic        is_repeat_code,
    output logic        decode_error
);

    // TODO: Check pulse widths against NEC timing specs
    // 0: 1.125ms total (560us mark + 560us space)
    // 1: 2.25ms total (560us mark + 1.69ms space)
    // Header: 9ms mark + 4.5ms space

endmodule
