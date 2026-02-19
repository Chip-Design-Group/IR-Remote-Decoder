`timescale 1ns/1ps

// ============================================================
// NEC/Samsung Protocol Decoder
// ============================================================
//
// Decodes NEC IR remote control frames received via pulse
// measurements from ir_pulse_timer.
//
// NEC Frame:      AGC(9ms) + Space(4.5ms) + 32 Data Bits + Stop
// Samsung Frame:  AGC(4.5ms) + Space(4.5ms) + 16 Addr Bits + Sync + 4 ID + 8 Cmd + 8 ~Cmd + Stop
// Samsung36:      16 Addr-Bits, then Sync-Bit (550µs burst + 4500µs space), then 20 bits (4 ID + 8 Cmd + 8 ~Cmd)
// Repeat:      AGC(9ms) + Space(2.25ms) + Burst(560us)
// Data bits: burst(560µs) + space(560µs=0, 1690µs=1)
//
// FSM States: IDLE → LEADER → SPACE/DATA/REPEAT_WAIT_STOP → VALIDATE/REPEAT_EMIT → IDLE
//
// pulse_width unit: 1 count = 1 clock cycle @ 10 MHz (100ns)
// ============================================================

module nec_decoder (
    // Clock & Reset
    input  wire        clk,
    input  wire        rst_n,

    // Inputs from ir_pulse_timer
    input  wire        pulse_done,
    input  wire [17:0] pulse_width,
    input  wire        pulse_level,
    input  wire        timeout,

    // Outputs to output_formatter & LEDs
    output logic        data_valid,
    output logic        decode_error,
    output logic [7:0]  address,
    output logic [7:0]  command,
    output logic [4:0]  protocol_id,
    output logic [47:0] frame_data,
    output logic [5:0]  frame_bits,
    output logic        receiving
);

    // ========================================================
    // Timing Constants (clock cycles @ 10 MHz, wider tolerance for real receivers)
    // 1 cycle = 100ns = 0.1µs
    // ========================================================

    // NEC AGC Burst: 9ms = 90000 cycles
    localparam NEC_AGC_MIN = 18'd65000;   // 6.5 ms
    localparam NEC_AGC_MAX = 18'd120000;  // 12.0 ms

    // Samsung AGC Burst: 4.5ms = 45000 cycles
    localparam SAMSUNG_AGC_MIN = 18'd30000; // 3.0 ms
    localparam SAMSUNG_AGC_MAX = 18'd65000; // 6.5 ms

    // AGC Space: 4.5ms = 45000 cycles
    localparam SPACE_MIN = 18'd30000; // 3.0 ms
    localparam SPACE_MAX = 18'd65000; // 6.5 ms

    // Repeat Space: 2.25ms = 22500 cycles (±20%, like other NEC windows)
    localparam REPEAT_MIN = 18'd16000; // 1.6 ms
    localparam REPEAT_MAX = 18'd30000; // 3.0 ms

    // Bit Burst: 560µs = 5600 cycles
    localparam BURST_MIN = 18'd3500;  // 350 µs
    localparam BURST_MAX = 18'd8000;  // 800 µs

    // Logical 0 Space: 560µs = 5600 cycles
    localparam BIT0_MIN = 18'd3500;   // 350 µs
    localparam BIT0_MAX = 18'd9000;   // 900 µs

    // Logical 1 Space: 1690µs = 16900 cycles
    // Keep this above the N8X2 one-window to avoid overlap.
    localparam BIT1_MIN = 18'd14000;  // 1400 µs
    localparam BIT1_MAX = 18'd24000;  // 2400 µs
    // NEC-like custom variant: logical 1 around 1.03ms
    localparam BIT1X2_MIN = 18'd9000;  // 900 µs
    localparam BIT1X2_MAX = 18'd14000; // 1400 µs

    // ========================================================
    // FSM State Definition
    // ========================================================
    typedef enum logic [2:0] {
        IDLE,       // Waiting for AGC burst
        LEADER,     // AGC burst detected, waiting for space
        SPACE,      // Space detected, waiting for first bit burst
        DATA,       // Receiving 32 data bits
        VALIDATE,   // Checking checksum
        REPEAT_WAIT_STOP, // Repeat space seen, waiting for final 560us burst
        REPEAT_EMIT // Re-emit last valid frame
    } state_t;

    state_t current_state, next_state;

    // ========================================================
    // Internal Signals
    // ========================================================
    logic [47:0] shift_reg;       // Up to 48-bit shift register (Samsung48)
    logic [5:0]  bit_counter;     // Counts received bits
    logic        wait_for_space;  // 1=waiting for space, 0=waiting for burst
    logic        has_valid_frame; // At least one full valid frame was decoded
    logic [21:0] since_valid_cnt; // Cycles since last full/accepted frame

    // Checksum validation
    logic [31:0] payload32;
    logic [7:0] addr, addr_inv, cmd, cmd_inv;
    logic       checksum_ok;
    logic       checksum_nec_style;
    logic       checksum_nec_extended_style;
    logic       checksum_samsung_style;
    logic       checksum_samsung_lenient;
    logic       repeat_armed;

    // Arduino-IRremote style: repeat is primarily gap-based.
    // NEC repeat period is ~110ms, so keep a short acceptance window.
    localparam logic [21:0] REPEAT_WINDOW_MAX = 22'd1_200_000; // 120ms @10MHz

    // Protocol IDs for downstream formatting/routing.
    localparam logic [4:0] PROTO_UNKNOWN              = 5'd0;
    localparam logic [4:0] PROTO_NEC                  = 5'd1;
    localparam logic [4:0] PROTO_SAMSUNG              = 5'd8;
    localparam logic [4:0] PROTO_SAMSUNG36            = 5'd9;
    localparam logic [4:0] PROTO_NEC8X2               = 5'd10;

    // Pulse classification
    logic is_nec_agc_burst, is_samsung_agc_burst, is_agc_space, is_repeat_space, is_bit_burst;
    logic is_bit_burst_x2;
    logic is_bit0_space, is_bit1_space, is_bit1x2_space;
    logic is_samsung_split_space;
    logic [4:0] leader_protocol;
    logic [4:0] last_protocol;
    logic [4:0] classified_protocol;
    logic       mark_level;      // Detected active burst level (supports both polarities)
    logic       space_level;
    logic       samsung_split_seen;
    logic       samsung_36bit_complete;
    logic       nec8x2_one_seen;
    logic       nec8x2_complete;
    logic       checksum_nec8x2;

    // ========================================================
    // Pulse Classification (combinational)
    // ========================================================
    always_comb begin
        is_nec_agc_burst    = (pulse_width >= NEC_AGC_MIN)        && (pulse_width <= NEC_AGC_MAX);
        is_samsung_agc_burst = (pulse_width >= SAMSUNG_AGC_MIN)    && (pulse_width <= SAMSUNG_AGC_MAX);
        is_agc_space    = (pulse_width >= SPACE_MIN)   && (pulse_width <= SPACE_MAX);
        is_repeat_space = (pulse_width >= REPEAT_MIN)  && (pulse_width <= REPEAT_MAX);
        is_bit_burst    = (pulse_width >= BURST_MIN)   && (pulse_width <= BURST_MAX);
        // Some NEC-like remotes use ~1.03ms mark for logical '1'.
        is_bit_burst_x2 = (pulse_width >= BIT1X2_MIN)  && (pulse_width <= BIT1X2_MAX);
        is_bit0_space   = (pulse_width >= BIT0_MIN)    && (pulse_width <= BIT0_MAX);
        is_bit1_space   = (pulse_width >= BIT1_MIN)    && (pulse_width <= BIT1_MAX);
        is_bit1x2_space = (pulse_width >= BIT1X2_MIN)  && (pulse_width <= BIT1X2_MAX);
        // Samsung36: Sync-Bit = 550µs burst + 4500µs space, appears after 16 addr bits.
        // At this point bit_counter=16, wait_for_space=1 (sync-burst was seen).
        is_samsung_split_space = (leader_protocol == PROTO_SAMSUNG) &&
                                 (bit_counter >= 6'd16) &&
                                 (bit_counter <= 6'd18) &&
                                 (pulse_width >= SPACE_MIN) &&
                                 (pulse_width <= SPACE_MAX);
    end

    // ========================================================
    // Checksum Extraction & Validation
    // ========================================================
    // Samsung36: 16 addr bits + sync + 20 data bits = 36 total data bits.
    // After sync, shift_reg[47:32] = addr[15:0] (first 16 bits shifted to top).
    // After 20 more bits: shift_reg[19:0] = {~cmd[7:0], cmd[7:0], id[3:0]}
    // Full layout after 36 bits:
    //   shift_reg[47:32] = addr[15:0]   (bits 0-15, LSB-first)
    //   shift_reg[31:28] = id[3:0]      (bits 16-19)
    //   shift_reg[27:20] = cmd[7:0]     (bits 20-27)
    //   shift_reg[19:12] = ~cmd[7:0]    (bits 28-35)
    assign samsung_36bit_complete = samsung_split_seen && (bit_counter >= 6'd36);
    assign nec8x2_complete = nec8x2_one_seen && (bit_counter >= 6'd8);
    assign payload32 = samsung_36bit_complete
                       ? {shift_reg[31:28], shift_reg[27:20], shift_reg[19:12], 8'h00}
                       : shift_reg[47:16];
    assign addr     = payload32[7:0];   // unused for SAM36 (addr is 16-bit)
    assign addr_inv = payload32[15:8];  // unused for SAM36
    assign cmd      = samsung_36bit_complete ? shift_reg[27:20] : payload32[23:16];
    assign cmd_inv  = samsung_36bit_complete ? shift_reg[19:12] : payload32[31:24];
    assign checksum_nec_style = ((addr ^ addr_inv) == 8'hFF) &&
                                ((cmd  ^ cmd_inv)  == 8'hFF);
    // NEC extended style: 16-bit address payload (no inverted address byte),
    // command byte still uses inversion.
    assign checksum_nec_extended_style = (leader_protocol == PROTO_NEC) &&
                                         ((cmd ^ cmd_inv) == 8'hFF);
    // Samsung remotes often send 16-bit address bytes (addr_hi/addr_lo),
    // i.e. no inverted address byte, but command byte remains inverted.
    assign checksum_samsung_style = (leader_protocol == PROTO_SAMSUNG) &&
                                    ((cmd ^ cmd_inv) == 8'hFF);
    // Samsung36: lenient accept (addr is 16-bit, no inversion check on addr)
    assign checksum_samsung_lenient = (leader_protocol == PROTO_SAMSUNG);
    assign checksum_nec8x2 = (leader_protocol == PROTO_NEC) && nec8x2_complete;
    assign checksum_ok = checksum_nec_style ||
                         checksum_nec_extended_style ||
                         checksum_samsung_style ||
                         checksum_samsung_lenient ||
                         checksum_nec8x2;
    assign repeat_armed = has_valid_frame && (since_valid_cnt < REPEAT_WINDOW_MAX);
    assign space_level = ~mark_level;

    always_comb begin
        classified_protocol = PROTO_UNKNOWN;
        if (leader_protocol == PROTO_SAMSUNG) begin
            classified_protocol = samsung_split_seen ? PROTO_SAMSUNG36 : PROTO_SAMSUNG;
        end else if (leader_protocol == PROTO_NEC) begin
            if (checksum_nec_style || checksum_nec_extended_style) begin
                classified_protocol = PROTO_NEC;
            end else if (checksum_nec8x2) begin
                classified_protocol = PROTO_NEC8X2;
            end
        end
    end

    // ========================================================
    // FSM: State Register (sequential)
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // ========================================================
    // FSM: Next State Logic (combinational)
    // ========================================================
    always_comb begin
        next_state = current_state; // Default: stay

        case (current_state)
            IDLE: begin
                if (pulse_done && (is_nec_agc_burst || is_samsung_agc_burst))
                    next_state = LEADER;
            end

            LEADER: begin
                if (timeout)
                    next_state = IDLE;
                else if (pulse_done) begin
                    if (pulse_level == space_level && is_agc_space)
                        next_state = SPACE;
                    else if (pulse_level == space_level && is_repeat_space && repeat_armed)
                        next_state = REPEAT_WAIT_STOP;
                    else
                        next_state = IDLE; // Invalid pulse → reset
                end
            end

            SPACE: begin
                if (timeout)
                    next_state = IDLE;
                else if (pulse_done) begin
                    if (pulse_level == mark_level &&
                        (is_bit_burst || ((leader_protocol == PROTO_NEC) && is_bit_burst_x2)))
                        next_state = DATA;
                    else
                        next_state = IDLE;
                end
            end

            DATA: begin
                if (timeout)
                    next_state = IDLE;
                else if (pulse_done) begin
                    if (wait_for_space) begin
                        // Received space → classify bit
                        if (pulse_level == space_level &&
                            (is_bit0_space || is_bit1_space || is_bit1x2_space)) begin
                            if ((leader_protocol == PROTO_SAMSUNG) && samsung_split_seen) begin
                                if (bit_counter == 6'd35)
                                    next_state = VALIDATE;
                            end else if ((leader_protocol == PROTO_NEC) &&
                                         (nec8x2_one_seen || is_bit1x2_space)) begin
                                if (bit_counter == 6'd7)
                                    next_state = VALIDATE;
                            end else if (bit_counter == 6'd31) begin
                                next_state = VALIDATE;
                            end
                            // else stay in DATA
                        end else if (pulse_level == space_level && is_samsung_split_space) begin
                            // Samsung36 sync delimiter inside frame, keep decoding.
                        end else begin
                            next_state = IDLE; // Invalid space
                        end
                    end else begin
                        // Received burst
                        if (pulse_level == mark_level &&
                            (is_bit_burst || ((leader_protocol == PROTO_NEC) && is_bit_burst_x2))) begin
                            // Valid burst, stay in DATA
                        end else begin
                            next_state = IDLE; // Invalid burst
                        end
                    end
                end
            end

            VALIDATE: begin
                next_state = IDLE; // Always return to IDLE
            end

            REPEAT_WAIT_STOP: begin
                if (timeout)
                    next_state = IDLE;
                else if (pulse_done) begin
                    if (pulse_level == mark_level && is_bit_burst)
                        next_state = REPEAT_EMIT;
                    else
                        next_state = IDLE;
                end
            end

            REPEAT_EMIT: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // ========================================================
    // Datapath: Shift Register, Bit Counter, Wait Flag
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg       <= 48'h0;
            bit_counter     <= 6'd0;
            wait_for_space  <= 1'b0;
            has_valid_frame <= 1'b0;
            since_valid_cnt <= REPEAT_WINDOW_MAX;
            leader_protocol <= PROTO_UNKNOWN;
            last_protocol   <= PROTO_UNKNOWN;
            mark_level      <= 1'b0;
            samsung_split_seen <= 1'b0;
            nec8x2_one_seen <= 1'b0;
        end else begin
            if (has_valid_frame && since_valid_cnt < REPEAT_WINDOW_MAX)
                since_valid_cnt <= since_valid_cnt + 1'b1;

            case (current_state)
                IDLE: begin
                    shift_reg      <= 48'h0;
                    bit_counter    <= 6'd0;
                    wait_for_space <= 1'b0;
                    samsung_split_seen <= 1'b0;
                    nec8x2_one_seen <= 1'b0;
                    if (pulse_done) begin
                        mark_level <= pulse_level;
                        if (is_nec_agc_burst)
                            leader_protocol <= PROTO_NEC;
                        else if (is_samsung_agc_burst)
                            leader_protocol <= PROTO_SAMSUNG;
                        else
                            leader_protocol <= PROTO_UNKNOWN;
                    end
                end

                SPACE: begin
                    // First bit burst detected → enter DATA on next cycle
                    if (pulse_done && pulse_level == mark_level &&
                        (is_bit_burst || ((leader_protocol == PROTO_NEC) && is_bit_burst_x2)))
                        wait_for_space <= 1'b1;
                end

                DATA: begin
                    if (pulse_done) begin
                        if (wait_for_space) begin
                            // Space received → shift in the bit
                            if (pulse_level == space_level && is_bit1_space) begin
                                shift_reg <= {1'b1, shift_reg[47:1]}; // LSB first
                                bit_counter <= bit_counter + 1;
                                wait_for_space <= 1'b0;
                            end else if (pulse_level == space_level && is_bit1x2_space) begin
                                shift_reg <= {1'b1, shift_reg[47:1]}; // custom 1-space (1.03ms)
                                bit_counter <= bit_counter + 1;
                                wait_for_space <= 1'b0;
                                nec8x2_one_seen <= 1'b1;
                            end else if (pulse_level == space_level && is_bit0_space) begin
                                shift_reg <= {1'b0, shift_reg[47:1]}; // LSB first
                                bit_counter <= bit_counter + 1;
                                wait_for_space <= 1'b0;
                            end else if (pulse_level == space_level && is_samsung_split_space) begin
                                // Consume Samsung48 split delimiter and continue with next burst.
                                samsung_split_seen <= 1'b1;
                                wait_for_space <= 1'b0;
                            end
                        end else begin
                            // Burst received → wait for space
                            if (pulse_level == mark_level &&
                                (is_bit_burst || ((leader_protocol == PROTO_NEC) && is_bit_burst_x2)))
                                wait_for_space <= 1'b1;
                        end
                    end
                end

                VALIDATE: begin
                    if (checksum_ok) begin
                        has_valid_frame <= 1'b1;
                        since_valid_cnt <= 22'd0;
                        last_protocol   <= classified_protocol;
                    end
                end

                REPEAT_EMIT: begin
                    since_valid_cnt <= 22'd0;
                end

                default: ; // LEADER, REPEAT_WAIT_STOP: no action needed
            endcase
        end
    end

    // ========================================================
    // Output Logic
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
            address      <= 8'h0;
            command      <= 8'h0;
            protocol_id  <= PROTO_UNKNOWN;
            frame_data   <= 48'h0;
            frame_bits   <= 6'd0;
        end else begin
            // Default: pulses clear after 1 clock cycle
            data_valid   <= 1'b0;
            decode_error <= 1'b0;

            if (current_state == VALIDATE) begin
                if (checksum_ok) begin
                    data_valid  <= 1'b1;
                    protocol_id <= classified_protocol;
                    if (samsung_36bit_complete) begin
                        // Samsung36: addr is 16-bit, cmd is 8-bit
                        address    <= shift_reg[39:32]; // addr_lo (lower 8 of 16-bit addr)
                        command    <= shift_reg[27:20]; // cmd[7:0]
                        frame_data <= shift_reg;
                        frame_bits <= 6'd36;
                    end else if (nec8x2_complete) begin
                        // NEC-like 8-bit frame (LSB-first, no checksum bytes)
                        address    <= 8'h00;
                        command    <= shift_reg[47:40];
                        frame_data <= {40'h0000000000, shift_reg[47:40]};
                        frame_bits <= 6'd8;
                    end else begin
                        address    <= addr;
                        command    <= cmd;
                        frame_data <= {16'h0000, payload32};
                        frame_bits <= 6'd32;
                    end
                end else begin
                    decode_error <= 1'b1;
                end
            end

            if (current_state == REPEAT_EMIT && has_valid_frame) begin
                data_valid <= 1'b1; // Re-emit last valid address/command
                protocol_id <= last_protocol;
            end

        end
    end

    // ========================================================
    // Receiving Signal (LED)
    // ========================================================
    assign receiving = (current_state != IDLE) &&
                       (current_state != VALIDATE) &&
                       (current_state != REPEAT_EMIT);

endmodule
