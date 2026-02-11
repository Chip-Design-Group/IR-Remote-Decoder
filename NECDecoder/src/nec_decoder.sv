`timescale 1ns/1ps

// ============================================================
// NEC Protocol Decoder
// ============================================================
//
// Decodes NEC IR remote control frames received via pulse
// measurements from ir_pulse_timer.
//
// NEC Frame:   AGC(9ms) + Space(4.5ms) + 32 Data Bits + Stop
// Repeat Code: AGC(9ms) + Space(2.25ms) + Stop
// Data bits: Address(8) + ~Address(8) + Command(8) + ~Command(8)
// Bit encoding: burst(560µs) + space(560µs=0, 1690µs=1)
//
// FSM States: IDLE → LEADER → SPACE/REPEAT → DATA → VALIDATE → IDLE
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
    output logic        receiving
);

    // ========================================================
    // Timing Constants (clock cycles @ 10 MHz, ±20% tolerance)
    // 1 cycle = 100ns = 0.1µs
    // ========================================================

    // AGC Burst: 9ms = 90000 cycles
    localparam AGC_MIN = 18'd72000;   // 7.2 ms
    localparam AGC_MAX = 18'd108000;  // 10.8 ms

    // AGC Space: 4.5ms = 45000 cycles
    localparam SPACE_MIN = 18'd36000; // 3.6 ms
    localparam SPACE_MAX = 18'd54000; // 5.4 ms

    // Repeat Space: 2.25ms = 22500 cycles
    localparam REPEAT_MIN = 18'd18000; // 1.8 ms
    localparam REPEAT_MAX = 18'd27000; // 2.7 ms

    // Bit Burst: 560µs = 5600 cycles
    localparam BURST_MIN = 18'd4480;  // 448 µs
    localparam BURST_MAX = 18'd6720;  // 672 µs

    // Logical 0 Space: 560µs = 5600 cycles
    localparam BIT0_MIN = 18'd4480;   // 448 µs
    localparam BIT0_MAX = 18'd6720;   // 672 µs

    // Logical 1 Space: 1690µs = 16900 cycles
    localparam BIT1_MIN = 18'd13520;  // 1352 µs
    localparam BIT1_MAX = 18'd20280;  // 2028 µs

    // ========================================================
    // FSM State Definition
    // ========================================================
    typedef enum logic [2:0] {
        IDLE,       // Waiting for AGC burst
        LEADER,     // AGC burst detected, waiting for space
        SPACE,      // Space detected, waiting for first bit burst
        DATA,       // Receiving 32 data bits
        VALIDATE,   // Checking checksum
        REPEAT      // Repeat code detected
    } state_t;

    state_t current_state, next_state;

    // ========================================================
    // Internal Signals
    // ========================================================
    logic [31:0] shift_reg;       // 32-bit shift register
    logic [5:0]  bit_counter;     // Counts received bits (0-31)
    logic        wait_for_space;  // 1=waiting for space, 0=waiting for burst
    logic        has_valid_frame; // 1=at least one valid frame was decoded

    // Checksum validation
    logic [7:0] addr, addr_inv, cmd, cmd_inv;
    logic       checksum_ok;

    // Pulse classification
    logic is_agc_burst, is_agc_space, is_repeat_space, is_bit_burst;
    logic is_bit0_space, is_bit1_space;

    // ========================================================
    // Pulse Classification (combinational)
    // ========================================================
    always_comb begin
        is_agc_burst    = (pulse_width >= AGC_MIN)    && (pulse_width <= AGC_MAX);
        is_agc_space    = (pulse_width >= SPACE_MIN)   && (pulse_width <= SPACE_MAX);
        is_repeat_space = (pulse_width >= REPEAT_MIN)  && (pulse_width <= REPEAT_MAX);
        is_bit_burst    = (pulse_width >= BURST_MIN)   && (pulse_width <= BURST_MAX);
        is_bit0_space   = (pulse_width >= BIT0_MIN)    && (pulse_width <= BIT0_MAX);
        is_bit1_space   = (pulse_width >= BIT1_MIN)    && (pulse_width <= BIT1_MAX);
    end

    // ========================================================
    // Checksum Extraction & Validation
    // ========================================================
    assign addr     = shift_reg[7:0];
    assign addr_inv = shift_reg[15:8];
    assign cmd      = shift_reg[23:16];
    assign cmd_inv  = shift_reg[31:24];
    assign checksum_ok = ((addr ^ addr_inv) == 8'hFF) &&
                         ((cmd  ^ cmd_inv)  == 8'hFF);

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
                if (pulse_done && pulse_level == 1'b0 && is_agc_burst)
                    next_state = LEADER;
            end

            LEADER: begin
                if (timeout)
                    next_state = IDLE;
                else if (pulse_done) begin
                    if (pulse_level == 1'b1 && is_agc_space)
                        next_state = SPACE;
                    else if (pulse_level == 1'b1 && is_repeat_space)
                        next_state = REPEAT;
                    else
                        next_state = IDLE; // Invalid pulse → reset
                end
            end

            SPACE: begin
                if (timeout)
                    next_state = IDLE;
                else if (pulse_done) begin
                    if (pulse_level == 1'b0 && is_bit_burst)
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
                        if (pulse_level == 1'b1 && (is_bit0_space || is_bit1_space)) begin
                            if (bit_counter == 6'd31)
                                next_state = VALIDATE;
                            // else stay in DATA
                        end else begin
                            next_state = IDLE; // Invalid space
                        end
                    end else begin
                        // Received burst
                        if (pulse_level == 1'b0 && is_bit_burst) begin
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

            REPEAT: begin
                next_state = IDLE; // Always return to IDLE
            end

            default: next_state = IDLE;
        endcase
    end

    // ========================================================
    // Datapath: Shift Register, Bit Counter, Wait Flag
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg       <= 32'h0;
            bit_counter     <= 6'd0;
            wait_for_space  <= 1'b0;
            has_valid_frame <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    shift_reg      <= 32'h0;
                    bit_counter    <= 6'd0;
                    wait_for_space <= 1'b0;
                end

                SPACE: begin
                    // First bit burst detected → enter DATA on next cycle
                    if (pulse_done && pulse_level == 1'b0 && is_bit_burst)
                        wait_for_space <= 1'b1;
                end

                DATA: begin
                    if (pulse_done) begin
                        if (wait_for_space) begin
                            // Space received → shift in the bit
                            if (pulse_level == 1'b1 && is_bit1_space) begin
                                shift_reg <= {1'b1, shift_reg[31:1]}; // LSB first
                                bit_counter <= bit_counter + 1;
                                wait_for_space <= 1'b0;
                            end else if (pulse_level == 1'b1 && is_bit0_space) begin
                                shift_reg <= {1'b0, shift_reg[31:1]}; // LSB first
                                bit_counter <= bit_counter + 1;
                                wait_for_space <= 1'b0;
                            end
                        end else begin
                            // Burst received → wait for space
                            if (pulse_level == 1'b0 && is_bit_burst)
                                wait_for_space <= 1'b1;
                        end
                    end
                end

                VALIDATE: begin
                    // Mark that a valid frame has been decoded
                    if (checksum_ok)
                        has_valid_frame <= 1'b1;
                end

                default: ; // LEADER, REPEAT: no action needed
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
        end else begin
            // Default: pulses clear after 1 clock cycle
            data_valid   <= 1'b0;
            decode_error <= 1'b0;

            if (current_state == VALIDATE) begin
                if (checksum_ok) begin
                    data_valid <= 1'b1;
                    address    <= addr;
                    command    <= cmd;
                end else begin
                    decode_error <= 1'b1;
                end
            end

            // Repeat code: re-assert data_valid with last address/command
            if (current_state == REPEAT && has_valid_frame) begin
                data_valid <= 1'b1;
                // address and command are already holding the last valid values
            end
        end
    end

    // ========================================================
    // Receiving Signal (LED)
    // ========================================================
    assign receiving = (current_state != IDLE) &&
                       (current_state != VALIDATE) &&
                       (current_state != REPEAT);

endmodule
