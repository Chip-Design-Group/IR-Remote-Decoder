`timescale 1ns/1ps

module pulse_timer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ir_in_sync,
    input  logic        edge_rise,
    input  logic        edge_fall,

    output logic        pulse_done,
    output logic [17:0] pulse_width,
    output logic        pulse_level,
    output logic        timeout
);

    localparam int COUNTER_WIDTH = 18;
    localparam int TIMEOUT_TICKS = 100_000; // 10 ms @ 10 MHz

    logic [COUNTER_WIDTH-1:0] counter;
    logic running;

    wire edge_any = edge_rise | edge_fall;
    wire edge_level = edge_fall; // 1 for falling edge (high pulse ended), 0 for rising edge

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // Reset all state
            counter     <= '0;
            running     <= 1'b0;
            pulse_done  <= 1'b0;
            pulse_width <= 18'd0;
            pulse_level <= 1'b0;
            timeout     <= 1'b0;
        end else begin // Normal operation
            pulse_done <= 1'b0;
            timeout    <= 1'b0;

            if (running) begin
                counter <= counter + 1'b1;

                if (counter >= TIMEOUT_TICKS - 1) begin // Timeout condition
                    pulse_done  <= 1'b1;
                    timeout     <= 1'b1;
                    pulse_width <= 18'h3FFFF;
                    pulse_level <= ir_in_sync; // Pulse level at timeout
                    running     <= 1'b0;
                    counter     <= '0;
                end else if (edge_any) begin // Edge detected while running
                    pulse_done  <= 1'b1;
                    if (counter == 0) begin // Edge occurred immediately after starting timer
                        pulse_width <= 18'd0;
                    end else begin
                        pulse_width <= counter[17:0] - 1'b1; // Capture pulse width (counter value at edge)
                    end
                    pulse_level <= edge_level;
                    counter     <= '0;
                    running     <= 1'b1;
                end
            end else if (edge_any) begin // Start timing on first edge
                running <= 1'b1;
                counter <= '0;
            end
        end
    end

endmodule
