//------------------------------------------------------------------------------
// File: nec_encoder.sv
// Zweck:
//   Wandelt address/command in NEC-Bitstream-Ereignisse um.
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

  localparam int LEADER_MARK_US   = 9000;
  localparam int LEADER_SPACE_US  = 4500;
  localparam int REPEAT_SPACE_US  = 2250;
  localparam int BIT_MARK_US      = 560;
  localparam int BIT0_SPACE_US    = 560;
  localparam int BIT1_SPACE_US    = 1690;
  localparam int STOP_MARK_US     = 560;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_LEADER_MARK,
    ST_LEADER_SPACE,
    ST_BIT_MARK,
    ST_BIT_SPACE,
    ST_STOP_MARK,
    ST_DONE
  } state_t;

  localparam int MAX_US = LEADER_MARK_US;
  localparam int US_CNT_W = (MAX_US > 1) ? $clog2(MAX_US) : 1;

  state_t                 state_q;
  logic [US_CNT_W-1:0]    us_cnt_q;
  logic [5:0]             bit_idx_q;
  ir_payload_t            payload_q;
  logic                   repeat_q;
  logic [31:0]            frame_word;
  logic                   frame_bit;

  assign frame_word = {
    ~payload_q.command,
    payload_q.command,
    payload_q.address[15:8],
    payload_q.address[7:0]
  };
  assign frame_bit = frame_word[bit_idx_q];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= ST_IDLE;
      us_cnt_q      <= '0;
      bit_idx_q     <= '0;
      payload_q     <= '0;
      repeat_q      <= 1'b0;
      mark_active   <= 1'b0;
      frame_active  <= 1'b0;
      frame_done    <= 1'b0;
      busy          <= 1'b0;
      error         <= 1'b0;
    end else begin
      frame_done <= 1'b0;
      error      <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          mark_active  <= 1'b0;
          frame_active <= 1'b0;
          busy         <= 1'b0;
          us_cnt_q     <= '0;
          bit_idx_q    <= '0;

          if (start) begin
            payload_q    <= payload;
            repeat_q     <= payload.flags[IR_FLAG_REPEAT_BIT];
            state_q      <= ST_LEADER_MARK;
            frame_active <= 1'b1;
            busy         <= 1'b1;
          end
        end

        ST_LEADER_MARK: begin
          mark_active  <= 1'b1;
          frame_active <= 1'b1;
          busy         <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == LEADER_MARK_US - 1) begin
              us_cnt_q <= '0;
              state_q  <= ST_LEADER_SPACE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_LEADER_SPACE: begin
          mark_active  <= 1'b0;
          frame_active <= 1'b1;
          busy         <= 1'b1;
          if (tick_us) begin
            if (repeat_q) begin
              if (us_cnt_q == REPEAT_SPACE_US - 1) begin
                us_cnt_q <= '0;
                state_q  <= ST_STOP_MARK;
              end else begin
                us_cnt_q <= us_cnt_q + 1'b1;
              end
            end else begin
              if (us_cnt_q == LEADER_SPACE_US - 1) begin
                us_cnt_q  <= '0;
                bit_idx_q <= '0;
                state_q   <= ST_BIT_MARK;
              end else begin
                us_cnt_q <= us_cnt_q + 1'b1;
              end
            end
          end
        end

        ST_BIT_MARK: begin
          mark_active  <= 1'b1;
          frame_active <= 1'b1;
          busy         <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == BIT_MARK_US - 1) begin
              us_cnt_q <= '0;
              state_q  <= ST_BIT_SPACE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_BIT_SPACE: begin
          mark_active  <= 1'b0;
          frame_active <= 1'b1;
          busy         <= 1'b1;
          if (tick_us) begin
            if ((frame_bit && (us_cnt_q == BIT1_SPACE_US - 1)) ||
                (!frame_bit && (us_cnt_q == BIT0_SPACE_US - 1))) begin
              us_cnt_q <= '0;
              if (bit_idx_q == 6'd31) begin
                state_q <= ST_STOP_MARK;
              end else begin
                bit_idx_q <= bit_idx_q + 1'b1;
                state_q   <= ST_BIT_MARK;
              end
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_STOP_MARK: begin
          mark_active  <= 1'b1;
          frame_active <= 1'b1;
          busy         <= 1'b1;
          if (tick_us) begin
            if (us_cnt_q == STOP_MARK_US - 1) begin
              us_cnt_q <= '0;
              state_q  <= ST_DONE;
            end else begin
              us_cnt_q <= us_cnt_q + 1'b1;
            end
          end
        end

        ST_DONE: begin
          mark_active  <= 1'b0;
          frame_active <= 1'b0;
          frame_done   <= 1'b1;
          busy         <= 1'b0;
          state_q      <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
