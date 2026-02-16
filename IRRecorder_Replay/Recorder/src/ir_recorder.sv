//------------------------------------------------------------------------------
// File: ir_recorder.sv
// Purpose:
//   Accepts decoded NEC payloads and writes them into storage.
// Inputs:
//   clk, rst_n
//   record_req, target_slot
//   dec_valid, dec_payload
// MVP note:
//   REC button drives record_req, target_slot is typically fixed to 0.
// Outputs:
//   mem_wr_en, mem_wr_addr, mem_wr_data
//   busy, done, error
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module ir_recorder #(
  parameter int SLOT_COUNT = IR_SLOT_COUNT,
  parameter int WAIT_TIMEOUT_CYCLES = 256
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  record_req,
  input  ir_slot_t              target_slot,

  input  logic                  dec_valid,
  input  ir_payload_t           dec_payload,

  output logic                  mem_wr_en,
  output ir_slot_t              mem_wr_addr,
  output ir_word_t              mem_wr_data,

  output logic                  busy,
  output logic                  done,
  output logic                  error
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_WAIT_VALID,
    ST_WRITE,
    ST_DONE,
    ST_ERROR
  } recorder_state_t;

  localparam int WAIT_CNT_W = (WAIT_TIMEOUT_CYCLES > 1) ? $clog2(WAIT_TIMEOUT_CYCLES) : 1;

  recorder_state_t state_q;
  logic [WAIT_CNT_W-1:0] wait_cnt_q;
  ir_slot_t              slot_q;
  ir_word_t              word_q;

  // Recorder is considered busy while waiting for valid data or issuing a write.
  assign busy = (state_q == ST_WAIT_VALID) || (state_q == ST_WRITE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= ST_IDLE;
      wait_cnt_q   <= '0;
      slot_q       <= '0;
      word_q       <= '0;
      mem_wr_en    <= 1'b0;
      mem_wr_addr  <= '0;
      mem_wr_data  <= '0;
      done         <= 1'b0;
      error        <= 1'b0;
    end else begin
      // Pulse outputs are deasserted by default and asserted in dedicated states.
      mem_wr_en <= 1'b0;
      done      <= 1'b0;
      error     <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          wait_cnt_q <= '0;
          // Start a new recording transaction when requested.
          if (record_req) begin
            slot_q <= target_slot;
            if (dec_valid) begin
              word_q  <= ir_types_pkg::ir_pack_word(dec_payload);
              state_q <= ST_WRITE;
            end else begin
              state_q <= ST_WAIT_VALID;
            end
          end
        end

        ST_WAIT_VALID: begin
          // Wait for a valid decoded payload, otherwise count toward timeout.
          if (!record_req) begin
            wait_cnt_q <= '0;
            state_q    <= ST_IDLE;
          end else if (dec_valid) begin
            word_q  <= ir_types_pkg::ir_pack_word(dec_payload);
            state_q <= ST_WRITE;
          end else if (wait_cnt_q == WAIT_TIMEOUT_CYCLES - 1) begin
            state_q <= ST_ERROR;
          end else begin
            wait_cnt_q <= wait_cnt_q + 1'b1;
          end
        end

        ST_WRITE: begin
          // Drive one-cycle memory write command.
          mem_wr_en   <= 1'b1;
          mem_wr_addr <= slot_q;
          mem_wr_data <= word_q;
          state_q     <= ST_DONE;
        end

        ST_DONE: begin
          // Signal successful completion for one cycle.
          done    <= 1'b1;
          wait_cnt_q <= '0;
          // Accept immediate back-to-back requests without forcing an extra idle cycle.
          if (record_req) begin
            slot_q <= target_slot;
            if (dec_valid) begin
              word_q  <= ir_types_pkg::ir_pack_word(dec_payload);
              state_q <= ST_WRITE;
            end else begin
              state_q <= ST_WAIT_VALID;
            end
          end else begin
            state_q <= ST_IDLE;
          end
        end

        ST_ERROR: begin
          // Signal timeout/error for one cycle.
          error   <= 1'b1;
          wait_cnt_q <= '0;
          // Also allow immediate retry on a new request.
          if (record_req) begin
            slot_q <= target_slot;
            if (dec_valid) begin
              word_q  <= ir_types_pkg::ir_pack_word(dec_payload);
              state_q <= ST_WRITE;
            end else begin
              state_q <= ST_WAIT_VALID;
            end
          end else begin
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
