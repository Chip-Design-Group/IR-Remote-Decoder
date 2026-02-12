`timescale 1ns/1ps

module edge_pulse_wrapper (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ir_in_async,

    output logic        pulse_done,
    output logic [17:0] pulse_width,
    output logic        pulse_level,
    output logic        timeout
);

    logic ir_in_sync;
    logic edge_rise;
    logic edge_fall;

    edge_detector u_edge_detector (
        .clk(clk),
        .rst_n(rst_n),
        .ir_in_async(ir_in_async),
        .ir_in_sync(ir_in_sync),
        .edge_rise(edge_rise),
        .edge_fall(edge_fall)
    );

    pulse_timer u_pulse_timer (
        .clk(clk),
        .rst_n(rst_n),
        .ir_in_sync(ir_in_sync),
        .edge_rise(edge_rise),
        .edge_fall(edge_fall),
        .pulse_done(pulse_done),
        .pulse_width(pulse_width),
        .pulse_level(pulse_level),
        .timeout(timeout)
    );

endmodule
