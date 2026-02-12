`timescale 1ns/1ps

module edge_detector (
    input  logic clk,
    input  logic rst_n,
    input  logic ir_in_async,
    
    output logic ir_in_sync,
    output logic edge_rise,
    output logic edge_fall
);

    logic ir_sync_ff1; // Flip Flop 1
    logic ir_sync_ff2; // Flip Flop 2
    logic ir_sync_prev; //previous signal

    // 2-stage synchronizer to reduce metastability risk
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_sync_ff1 <= 1'b0;
            ir_sync_ff2 <= 1'b0;
        end else begin
            ir_sync_ff1 <= ir_in_async;
            ir_sync_ff2 <= ir_sync_ff1;
        end
    end

    // Edge detect on the synchronized signal
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_sync_prev <= 1'b0;
            edge_rise <= 1'b0;
            edge_fall <= 1'b0;
        end else begin
            edge_rise <=  ir_sync_ff2 & ~ir_sync_prev;
            edge_fall <= ~ir_sync_ff2 &  ir_sync_prev;
            ir_sync_prev <= ir_sync_ff2;
        end
    end

    assign ir_in_sync = ir_sync_ff2;

endmodule
