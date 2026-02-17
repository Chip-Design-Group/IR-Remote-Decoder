`timescale 1ns/1ps

// Mock Xilinx primitive for Icarus simulation.
module BUFG (
    input  logic I,
    output logic O
);
    assign O = I;
endmodule
