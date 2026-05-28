`timescale 1ns/1ps

module multihead_ctrl #(
  parameter NUM_HEADS  = 8,
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16
)(
  input  wire                                     clk,
  input  wire                                     rst_n,
  input  wire                                     start,
  input  wire [DATA_WIDTH*HEAD_DIM*NUM_HEADS-1:0] vec_in,
  output reg                                      attn_start,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]          attn_q,
  input  wire                                     attn_done,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]          attn_out,
  output reg                                      valid_out,
  output reg  [DATA_WIDTH*HEAD_DIM*NUM_HEADS-1:0] vec_out
);

  localparam MH_IDLE  = 3'd0;
  localparam MH_LOAD  = 3'd1;
  localparam MH_WAIT  = 3'd2;
  localparam MH_STORE = 3'd3;
  localparam MH_NEXT  = 3'd4;
  localparam MH_DONE  = 3'd5;

  reg [3:0] head_cnt;
  reg [2:0] state;
  reg [DATA_WIDTH*HEAD_DIM-1:0] result_buf [0:NUM_HEADS-1];

  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_cnt    <= 4'd0;
      state       <= MH_IDLE;
      attn_start  <= 1'b0;
      attn_q      <= {DATA_WIDTH*HEAD_DIM{1'b0}};
      valid_out   <= 1'b0;
      vec_out     <= {(DATA_WIDTH*HEAD_DIM*NUM_HEADS){1'b0}};
      for (i = 0; i < NUM_HEADS; i = i + 1) begin
        result_buf[i] <= {DATA_WIDTH*HEAD_DIM{1'b0}};
      end
    end else begin
      attn_start <= 1'b0;
      valid_out  <= 1'b0;

      case (state)
        MH_IDLE: begin
          if (start) begin
            head_cnt <= 4'd0;
            state    <= MH_LOAD;
          end
        end

        MH_LOAD: begin
          attn_q     <= vec_in[head_cnt*HEAD_DIM*DATA_WIDTH +: HEAD_DIM*DATA_WIDTH];
          attn_start <= 1'b1;
          state      <= MH_WAIT;
        end

        MH_WAIT: begin
          if (attn_done) begin
            state <= MH_STORE;
          end
        end

        MH_STORE: begin
          result_buf[head_cnt] <= attn_out;
          state                <= MH_NEXT;
        end

        MH_NEXT: begin
          if (head_cnt < NUM_HEADS-1) begin
            head_cnt <= head_cnt + 1'b1;
            state    <= MH_LOAD;
          end else begin
            state <= MH_DONE;
          end
        end

        MH_DONE: begin
          for (i = 0; i < NUM_HEADS; i = i + 1) begin
            vec_out[i*HEAD_DIM*DATA_WIDTH +: HEAD_DIM*DATA_WIDTH] <= result_buf[i];
          end
          valid_out <= 1'b1;
          state     <= MH_IDLE;
        end

        default: begin
          state <= MH_IDLE;
        end
      endcase
    end
  end

endmodule
