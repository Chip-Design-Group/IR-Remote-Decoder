module pulse_timer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,      // active while measuring
    input  logic        pulse_start, // e.g. edge detected
    input  logic        pulse_end,   // e.g. edge detected
    
    output logic [15:0] duration,    // duration in ticks (0.1us)
    output logic        valid,       // pulse measurement complete & valid
    output logic        timeout      // pulse too long (>10ms)
);

    // TODO: Implement 16-bit counter
    // TODO: Implement timeout logic

endmodule
