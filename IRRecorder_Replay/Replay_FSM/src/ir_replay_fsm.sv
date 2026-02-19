//------------------------------------------------------------------------------
// File: ir_replay_fsm.sv
// Zweck:
//   Liest einen Slot aus dem Speicher und startet die NEC-Sende-Kette.
// Rein:
//   clk, rst_n
//   replay_req, target_slot
//   mem_rd_data, mem_rd_valid
//   enc_ready, tx_ready
// Hinweis MVP:
//   PLAY-Button -> replay_req, target_slot = 0.
// Raus:
//   mem_rd_en, mem_rd_addr
//   enc_start, enc_payload
//   busy, done, error
//------------------------------------------------------------------------------

`timescale 1ns/1ps

import ir_types_pkg::*;

module ir_replay_fsm #(
  parameter int SLOT_COUNT = ir_types_pkg::IR_SLOT_COUNT
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  replay_req,
  input  logic [2:0]            target_slot,

  output logic                  mem_rd_en,
  output ir_slot_t              mem_rd_addr,
  input  ir_word_t               mem_rd_data,
  input  logic                  mem_rd_valid,

  output logic                  enc_start,
  output ir_payload_t            enc_payload,
  input  logic                  enc_ready,
  input  logic                  tx_ready,

  output logic                  busy,
  output logic                  done,
  output logic                  error
);

  localparam logic [2:0] ST_IDLE         = 3'd0;
  localparam logic [2:0] ST_READ_REQ     = 3'd1;
  localparam logic [2:0] ST_READ_WAIT    = 3'd2;
  localparam logic [2:0] ST_DECODE_WORD  = 3'd3;
  localparam logic [2:0] ST_WAIT_ENCODER = 3'd4;
  localparam logic [2:0] ST_START_ENCODE = 3'd5;
  localparam logic [2:0] ST_DONE         = 3'd6;
  localparam logic [2:0] ST_ERROR        = 3'd7;
  localparam logic [4:0] PROTO_SAMSUNG36 = 5'd9;

  logic [2:0] state_q, state_d;

  logic replay_req_q;
  logic replay_req_rise;

  logic [2:0]               slot_q, slot_d;
  ir_word_t                  word_q, word_d;
  ir_payload_t               payload_q, payload_d;

  // Samsung36 stores semantic fields in frame_data[47:12]; encoder expects
  // contiguous serial bits in frame_data[35:0] (LSB-first per field).
  function automatic logic [IR_FRAME_DATA_WIDTH-1:0] map_sam36_frame_data(
    input logic [IR_FRAME_DATA_WIDTH-1:0] raw_src,
    input logic [IR_FRAME_BITS_WIDTH-1:0] bits
  );
    logic [IR_FRAME_DATA_WIDTH-1:0] result;
    begin
      result = '0;
      if (bits >= 6'd36) begin
        for (int idx = 0; idx < 16; idx++) result[idx]      = raw_src[32 + idx];
        for (int idx = 0; idx < 4; idx++)  result[16 + idx] = raw_src[28 + idx];
        for (int idx = 0; idx < 8; idx++)  result[20 + idx] = raw_src[20 + idx];
        for (int idx = 0; idx < 8; idx++)  result[28 + idx] = raw_src[12 + idx];
      end
      return result;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= ST_IDLE;
      replay_req_q <= 1'b0;
      slot_q       <= '0;
      word_q       <= '0;
      payload_q    <= '0;
    end else begin
      state_q      <= state_d;
      replay_req_q <= replay_req;
      slot_q       <= slot_d;
      word_q       <= word_d;
      payload_q    <= payload_d;
    end
  end

  always_comb begin
    state_d   = state_q;
    slot_d    = slot_q;
    word_d    = word_q;
    payload_d = payload_q;

    replay_req_rise = replay_req && !replay_req_q;

    case (state_q)
      ST_IDLE: begin
        if (replay_req_rise) begin
          slot_d  = target_slot;
          state_d = ST_READ_REQ;
        end
      end

      ST_READ_REQ: begin
        state_d = ST_READ_WAIT;
      end

      ST_READ_WAIT: begin
        if (mem_rd_valid) begin
          word_d = mem_rd_data;
          payload_d = ir_types_pkg::ir_unpack_word(mem_rd_data);
          if (payload_d.protocol_id == PROTO_SAMSUNG36) begin
            payload_d.frame_data = map_sam36_frame_data(
              payload_d.frame_data,
              payload_d.frame_bits
            );
          end
          state_d = ST_DECODE_WORD;
        end
      end

      ST_DECODE_WORD: begin
        if (payload_q.flags[IR_FLAG_VALID_BIT]) begin
          state_d = ST_WAIT_ENCODER;
        end else begin
          state_d = ST_ERROR;
        end
      end

      ST_WAIT_ENCODER: begin
        if (enc_ready && tx_ready) begin
          state_d = ST_START_ENCODE;
        end
      end

      ST_START_ENCODE: begin
        state_d = ST_DONE;
      end

      ST_DONE: begin
        state_d = ST_IDLE;
      end

      ST_ERROR: begin
        state_d = ST_IDLE;
      end

      default: begin
        state_d = ST_IDLE;
      end
    endcase
  end

  always_comb begin
    mem_rd_en   = 1'b0;
    mem_rd_addr = slot_q;
    enc_start   = 1'b0;
    enc_payload = payload_q;
    busy        = 1'b0;
    done        = 1'b0;
    error       = 1'b0;

    case (state_q)
      ST_READ_REQ: begin
        mem_rd_en = 1'b1;
        busy      = 1'b1;
      end

      ST_READ_WAIT,
      ST_DECODE_WORD,
      ST_WAIT_ENCODER,
      ST_START_ENCODE: begin
        busy = 1'b1;
      end

      ST_DONE: begin
        busy = 1'b1;
        done = 1'b1;
      end

      ST_ERROR: begin
        busy  = 1'b1;
        error = 1'b1;
      end

      default: begin
        busy = 1'b0;
      end
    endcase

    if (state_q == ST_START_ENCODE) begin
      enc_start = 1'b1;
    end
  end

endmodule
