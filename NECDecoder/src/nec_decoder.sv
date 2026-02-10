module nec_decoder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] pulse_width,
    input  logic        pulse_valid,
    
    output logic [7:0]  rx_address,
    output logic [7:0]  rx_command,
    output logic        data_valid,
    output logic        error_flag
);

    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        LEADER,
        SPACE,
        DATA,
        VALIDATE
    } state_t;

    state_t current_state, next_state;

    // TODO: Instantiate bit_decoder
    // TODO: Implement FSM to collect 32 bits
    // TODO: Verify checksum (Addr + ~Addr, Cmd + ~Cmd)

endmodule
