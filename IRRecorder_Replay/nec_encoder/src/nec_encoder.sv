//------------------------------------------------------------------------------
// File: nec_encoder.sv
// Zweck:
//   Wandelt address/command in NEC/Samsung-Bitstream-Ereignisse um.
// Rein:
//   clk, rst_n
//   start, payload
//   tick_us (Timing-Basis in us)
// Raus:
//   mark_active (1=IR Burst aktiv, 0=Space)
//   frame_active, frame_done, busy, error
//------------------------------------------------------------------------------

import ir_types_pkg::*;

module nec_encoder (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        start,
  input  ir_payload_t payload,
  input  logic        tick_us,

  output logic        mark_active,
  output logic        frame_active,
  output logic        frame_done,
  output logic        busy,
  output logic        error
);

  localparam int LEADER_MARK_US        = 9_000;
  localparam int NEC_LEADER_SPACE_US   = 4_500;
  localparam int SAMSUNG_LEADER_MARK_US = 4_500;
  localparam int SAMSUNG_LEADER_SPACE_US = 4_500;
  localparam int SAMSUNG36_SYNC_MARK_US  = 550;
  localparam int SAMSUNG36_SYNC_SPACE_US = 4_500;
  localparam int REPEAT_SPACE_US       = 2_250;
  localparam int BIT_MARK_US           = 560;
  localparam int BIT0_SPACE_US         = 560;
  localparam int BIT1_SPACE_US         = 1_690;
  localparam int STOP_MARK_US          = 560;

  localparam logic [4:0] PROTO_NEC     = 5'd1;
  localparam logic [4:0] PROTO_SAMSUNG = 5'd8;
  localparam logic [4:0] PROTO_SAMSUNG36 = 5'd9;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_LEADER_MARK,
    ST_LEADER_SPACE,
    ST_BIT_MARK,
    ST_BIT_SPACE,
    ST_SYNC_MARK,
    ST_SYNC_SPACE,
    ST_STOP_MARK,
    ST_DONE
  } state_t;

  localparam int MAX_US = LEADER_MARK_US;
  localparam int US_CNT_W = (MAX_US > 1) ? $clog2(MAX_US) : 1;

  state_t                 state_q;
  logic [US_CNT_W-1:0]    us_cnt_q;
  logic [IR_FRAME_BITS_WIDTH-1:0] bit_idx_q;
  ir_payload_t            payload_q;
  logic                   repeat_q;
  logic                   sync_inserted_q;
  logic [IR_FRAME_BITS_WIDTH-1:0] next_bit_idx;
  logic [15:0]                    space_limit;

  logic [15:0]            leader_mark_limit;
  logic [15:0]            leader_space_limit;

  wire [IR_FLAG_WIDTH-1:0]      payload_flags = payload_q.flags;
  wire [IR_PROTOCOL_ID_WIDTH-1:0] protocol_q = payload_q.protocol_id;
  wire [IR_FRAME_BITS_WIDTH-1:0] frame_bits_q = payload_q.frame_bits;
  wire [IR_FRAME_DATA_WIDTH-1:0] frame_data_q = payload_q.frame_data;
  wire                           use_samsung_leader = (protocol_q == PROTO_SAMSUNG) ||
                                                       (protocol_q == PROTO_SAMSUNG36);
  wire                           frame_bit = frame_data_q[bit_idx_q];

  always_comb begin
    if (repeat_q) begin
      leader_mark_limit  = LEADER_MARK_US;
      leader_space_limit = REPEAT_SPACE_US;
    end else if (use_samsung_leader) begin
      leader_mark_limit  = SAMSUNG_LEADER_MARK_US;
      leader_space_limit = SAMSUNG_LEADER_SPACE_US;
    end else begin
      leader_mark_limit  = LEADER_MARK_US;
      leader_space_limit = NEC_LEADER_SPACE_US;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q        <= ST_IDLE;
      us_cnt_q       <= '0;
      bit_idx_q      <= '0;
      payload_q      <= '0;
      repeat_q       <= 1'b0;
      sync_inserted_q <= 1'b0;
      mark_active    <= 1'b0;
      frame_active   <= 1'b0;
      frame_done     <= 1'b0;
      busy           <= 1'b0;
      error          <= 1'b0;
    end else begin
      frame_done <= 1'b0;
      error      <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          mark_active <= 1'b0;
          frame_active <= 1'b0;
          busy <= 1'b0;
          us_cnt_q <= '0;
          bit_idx_q <= '0;
          sync_inserted_q <= 1'b0;

          if (start) begin
            payload_q <= payload;
            repeat_q <= payload.flags[IR_FLAG_REPEAT_BIT];
            state_q <= ST_LEADER_MARK;
            frame_active <= 1'b1;
            busy <= 1'b1;
          end
        end

        ST_LEADER_MARK: begin
          mark_active <= 1'b1;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == leader_mark_limit - 1) begin
              us_cnt_q <= '0;
              state_q <= ST_LEADER_SPACE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_LEADER_SPACE: begin
          mark_active <= 1'b0;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == leader_space_limit - 1) begin
              us_cnt_q <= '0;
              if (repeat_q) begin
                state_q <= ST_STOP_MARK;
              end else if (frame_bits_q == 0) begin
                state_q <= ST_STOP_MARK;
              end else begin
                bit_idx_q <= '0;
                state_q <= ST_BIT_MARK;
              end
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_BIT_MARK: begin
          mark_active <= 1'b1;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == BIT_MARK_US - 1) begin
              us_cnt_q <= '0;
              state_q <= ST_BIT_SPACE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_BIT_SPACE: begin
          mark_active <= 1'b0;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            space_limit = frame_bit ? BIT1_SPACE_US : BIT0_SPACE_US;
            if (us_cnt_q == space_limit - 1) begin
              us_cnt_q <= '0;
              next_bit_idx = bit_idx_q + 1'b1;
              bit_idx_q <= next_bit_idx;
              if (next_bit_idx == frame_bits_q) begin
                state_q <= ST_STOP_MARK;
              end else if ((protocol_q == PROTO_SAMSUNG36) &&
                           (next_bit_idx == 6'd16) &&
                           !sync_inserted_q) begin
                sync_inserted_q <= 1'b1;
                state_q <= ST_SYNC_MARK;
              end else begin
                state_q <= ST_BIT_MARK;
              end
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_SYNC_MARK: begin
          mark_active <= 1'b1;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == SAMSUNG36_SYNC_MARK_US - 1) begin
              us_cnt_q <= '0;
              state_q <= ST_SYNC_SPACE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_SYNC_SPACE: begin
          mark_active <= 1'b0;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == SAMSUNG36_SYNC_SPACE_US - 1) begin
              us_cnt_q <= '0;
              state_q <= ST_BIT_MARK;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_STOP_MARK: begin
          mark_active <= 1'b1;
          frame_active <= 1'b1;
          busy <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == STOP_MARK_US - 1) begin
              us_cnt_q <= '0;
              state_q <= ST_DONE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_DONE: begin
          mark_active <= 1'b0;
          frame_active <= 1'b0;
          frame_done <= 1'b1;
          busy <= 1'b0;
          state_q <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
