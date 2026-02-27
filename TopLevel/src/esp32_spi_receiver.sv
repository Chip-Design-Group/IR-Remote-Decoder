`timescale 1ns/1ps

// ============================================================
// esp32_spi_receiver.sv
// ============================================================
//
// Receives 8-bit Software-SPI frames from an ESP32-C3.
//
// Protocol (from ESP32 wifi_button firmware):
//   MSB first, CLK idle LOW, DATA idle LOW.
//   FPGA samples DATA on rising edge of CLK.
//
// Frame format (12 bits, MSB first):
//   Bit [11:6] = slot[5:0]   ([5:4]=remote_id 0..3, [3:0]=slot_num 0..9)
//   Bit [5:3]  = cmd[2:0]    (001=PLAY, 010=REC)
//   Bit [2:0]  = magic       (always 3'b101 = 3'd5)
//
// Outputs a 1-cycle pulse on replay_req or record_req
// together with the decoded slot_addr[5:0].
//
// SPI timing:
//   CLK half-period: 1ms → CLK ~500 Baud
//   Core clock: 10MHz → plenty of margin
// ============================================================

module esp32_spi_receiver (
    input  logic       clk,
    input  logic       rst_n,

    // Asynchronous SPI inputs from ESP32
    input  logic       spi_clk_in,
    input  logic       spi_data_in,

    // Decoded outputs (1-cycle pulses)
    output logic       replay_req,
    output logic       record_req,
    output logic [5:0] slot_addr   // [5:4]=remote_id (0..3), [3:0]=slot_num (0..9)
);

    localparam logic [2:0] FRAME_MAGIC = 3'b101;
    localparam logic [2:0] CMD_PLAY    = 3'b001;
    localparam logic [2:0] CMD_REC     = 3'b010;

    // --------------------------------------------------------
    // 2-FF Synchronizer for CLK and DATA
    // --------------------------------------------------------
    logic clk_sync_0, clk_sync_1;
    logic dat_sync_0, dat_sync_1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync_0 <= 1'b0;
            clk_sync_1 <= 1'b0;
            dat_sync_0 <= 1'b0;
            dat_sync_1 <= 1'b0;
        end else begin
            clk_sync_0 <= spi_clk_in;
            clk_sync_1 <= clk_sync_0;
            dat_sync_0 <= spi_data_in;
            dat_sync_1 <= dat_sync_0;
        end
    end

    // --------------------------------------------------------
    // Rising-edge detector on synchronized CLK
    // --------------------------------------------------------
    logic clk_prev;
    logic clk_rise;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_prev <= 1'b0;
        else
            clk_prev <= clk_sync_1;
    end

    assign clk_rise = clk_sync_1 & ~clk_prev;

    // --------------------------------------------------------
    // CLK-idle timeout: reset bit_cnt when CLK stays LOW
    // longer than one inter-bit gap (~3ms = 30,000 cycles @10MHz).
    // This re-synchronises the receiver after startup noise or
    // a partial/corrupted frame.
    // --------------------------------------------------------
    localparam int IDLE_TIMEOUT = 30_000; // 3 ms at 10 MHz
    logic [$clog2(IDLE_TIMEOUT+1)-1:0] idle_cnt;
    logic idle_timeout;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_cnt    <= '0;
            idle_timeout <= 1'b0;
        end else begin
            idle_timeout <= 1'b0;
            if (clk_sync_1) begin
                // CLK is high → reset idle counter
                idle_cnt <= '0;
            end else begin
                if (idle_cnt == IDLE_TIMEOUT) begin
                    idle_timeout <= 1'b1;
                    idle_cnt     <= '0;
                end else begin
                    idle_cnt <= idle_cnt + 1'b1;
                end
            end
        end
    end

    // --------------------------------------------------------
    // 12-bit shift register (MSB first)
    // --------------------------------------------------------
    logic [11:0] shift_reg;
    logic [3:0] bit_cnt;       // counts 0..11
    logic        frame_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 12'h000;
            bit_cnt    <= 4'd0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0; // default: no frame ready

            if (idle_timeout) begin
                // Re-sync: reset bit counter on long CLK-idle gap
                bit_cnt <= 4'd0;
            end else if (clk_rise) begin
                // Shift in MSB first
                shift_reg <= {shift_reg[10:0], dat_sync_1};

                if (bit_cnt == 4'd11) begin
                    bit_cnt    <= 4'd0;
                    frame_done <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Frame decode and output
    // --------------------------------------------------------
    // shift_reg after 12 bits:
    //   [11:6] = slot[5:0]  ([5:4]=remote_id, [3:0]=slot_num)
    //   [5:3]  = cmd[2:0]
    //   [2:0]  = magic
    // Note: frame_done fires 1 cycle after the last bit was shifted in,
    // so shift_reg already contains the complete frame.

    logic [11:0] frame_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            replay_req <= 1'b0;
            record_req <= 1'b0;
            slot_addr  <= 6'd0;
            frame_reg  <= 12'h000;
        end else begin
            replay_req <= 1'b0;
            record_req <= 1'b0;

            if (frame_done) begin
                frame_reg <= shift_reg;

                if (shift_reg[2:0] == FRAME_MAGIC) begin
                    slot_addr <= shift_reg[11:6];

                    case (shift_reg[5:3])
                        CMD_PLAY: replay_req <= 1'b1;
                        CMD_REC:  record_req <= 1'b1;
                        default:  ;
                    endcase
                end
                // else: invalid magic → discard frame silently
            end
        end
    end

endmodule
