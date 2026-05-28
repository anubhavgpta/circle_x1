`timescale 1ns/1ps

module sampling_engine #(
  parameter VOCAB_SIZE = 32000,
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16,
  parameter TOP_K      = 8
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            start,
  input  wire                            logit_valid,
  input  wire                            logit_last,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  logit_data,
  input  wire [2:0]                      temp_shift,
  input  wire [15:0]                     p_threshold,
  output reg                             valid_out,
  output reg  [14:0]                     token_id
);

  localparam [2:0] S_IDLE=3'd0,S_CONSUME=3'd1,S_SOFTMAX=3'd2,S_NUCLEUS=3'd3,S_SAMPLE=3'd4,S_DONE=3'd5;
  reg [2:0] state;
  reg [DATA_WIDTH-1:0] tk_score [0:TOP_K-1], tk_exp [0:TOP_K-1];
  reg [14:0] tk_token [0:TOP_K-1], tile_base;
  reg tk_mask [0:TOP_K-1];
  reg [15:0] exp_lut [0:255];
  reg [3:0] sm_cnt;
  reg [31:0] prob_sum, cum_sum, nucleus_threshold;

  integer i,j,min_idx,argmax_idx;
  reg signed [DATA_WIDTH-1:0] scaled,best_score;
  reg [31:0] total_next,cum_next;

  initial begin
    $readmemh("exp_lut.mem", exp_lut);
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; valid_out <= 1'b0; token_id <= 15'd0; tile_base <= 15'd0;
      sm_cnt <= 4'd0; prob_sum <= 32'd0; cum_sum <= 32'd0; nucleus_threshold <= 32'd0;
      for (i=0;i<TOP_K;i=i+1) begin tk_score[i]<=16'h8000; tk_token[i]<=15'd0; tk_mask[i]<=1'b0; tk_exp[i]<=16'd0; end
    end else begin
      valid_out <= 1'b0;
      case (state)
        S_IDLE: begin
          if (start) begin
            tile_base <= 15'd0; sm_cnt <= 4'd0; prob_sum <= 32'd0; cum_sum <= 32'd0; nucleus_threshold <= 32'd0;
            for (i=0;i<TOP_K;i=i+1) begin tk_score[i]<=16'h8000; tk_token[i]<=15'd0; tk_mask[i]<=1'b1; tk_exp[i]<=16'd0; end
            state <= S_CONSUME;
          end
        end

        S_CONSUME: begin
          if (logit_valid) begin
            for (j=0;j<HEAD_DIM;j=j+1) begin
              scaled = $signed(logit_data[j*DATA_WIDTH +: DATA_WIDTH]) >>> temp_shift;
              min_idx = 0;
              for (i=1;i<TOP_K;i=i+1) if ($signed(tk_score[i]) < $signed(tk_score[min_idx])) min_idx = i;
              if (scaled > $signed(tk_score[min_idx])) begin
                tk_score[min_idx] <= scaled[DATA_WIDTH-1:0];
                tk_token[min_idx] <= tile_base + j[14:0];
                tk_mask[min_idx] <= 1'b1;
              end
            end
            tile_base <= tile_base + HEAD_DIM[14:0];
            if (logit_last) begin sm_cnt <= 4'd0; state <= S_SOFTMAX; end
          end
        end

        S_SOFTMAX: begin
          tk_exp[sm_cnt] <= exp_lut[tk_score[sm_cnt][11:4]];
          if (sm_cnt == TOP_K-1) begin
            total_next = 32'd0;
            for (i=0;i<TOP_K;i=i+1) total_next = total_next + ((i==sm_cnt)?exp_lut[tk_score[i][11:4]]:tk_exp[i]);
            prob_sum <= total_next;
            nucleus_threshold <= (p_threshold * total_next) >> 15;
            cum_sum <= 32'd0; sm_cnt <= 4'd0; state <= S_NUCLEUS;
          end else begin
            sm_cnt <= sm_cnt + 4'd1;
          end
        end

        S_NUCLEUS: begin
          cum_next = cum_sum + tk_exp[sm_cnt];
          cum_sum <= cum_next;
          tk_mask[sm_cnt] <= (cum_next <= nucleus_threshold);
          if (sm_cnt == TOP_K-1) begin
            state <= S_SAMPLE;
          end else begin
            sm_cnt <= sm_cnt + 4'd1;
          end
        end

        S_SAMPLE: begin
          argmax_idx = 0; best_score = 16'sh8000;
          for (i=0;i<TOP_K;i=i+1) begin
            if (tk_mask[i] && ($signed(tk_score[i]) > best_score)) begin
              best_score = $signed(tk_score[i]); argmax_idx = i;
            end
          end
          token_id <= tk_token[argmax_idx];
          state <= S_DONE;
        end

        S_DONE: begin
          valid_out <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
