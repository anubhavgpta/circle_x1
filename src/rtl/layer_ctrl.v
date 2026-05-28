`timescale 1ns/1ps

module layer_ctrl #(
  parameter NUM_LAYERS = 4,
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16,
  parameter PE_ROWS    = 8,
  parameter PE_COLS    = 8
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            start,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  vec_in,
  output reg                             attn_start,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  attn_vec,
  input  wire                            attn_done,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  attn_out,
  input  wire                            b_wr_en,
  input  wire [1:0]                      b_wr_sel,
  input  wire [6:0]                      b_wr_col,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  b_wr_data,
  input  wire [31:0]                     gamma_word [0:31],
  output reg                             valid_out,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  vec_out
);

  localparam [3:0] L_IDLE=4'd0,L_NORM1=4'd1,L_ATTN=4'd2,L_RESADD1=4'd3,L_NORM2=4'd4,
                   L_FFN=4'd5,L_RESADD2=4'd6,L_NEXT=4'd7,L_DONE=4'd8;

  reg [DATA_WIDTH*HEAD_DIM-1:0] cur_vec,norm1_out,post_attn,norm2_out,ffn_out;
  reg [3:0] layer_cnt;
  reg [1:0] norm_wait_cnt;
  reg [3:0] state;

  reg norm1_valid_in,norm2_valid_in,ffn_start;
  reg attn_issued,ffn_issued;

  wire [DATA_WIDTH*HEAD_DIM-1:0] gamma_vec;
  genvar gw;
  generate
    for (gw=0; gw<32; gw=gw+1) begin : gen_gamma_vec
      assign gamma_vec[(gw*32) +: 32] = gamma_word[gw];
    end
  endgenerate

  wire [DATA_WIDTH*HEAD_DIM-1:0] norm1_vec_out,norm2_vec_out;
  wire norm1_valid_out,norm2_valid_out;
  wire resadd1_valid_out,resadd2_valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0] resadd1_vec_out,resadd2_vec_out;
  wire ffn_valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0] ffn_vec_out;

  rmsnorm_engine #(.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH)) u_norm1 (
    .clk(clk),.rst_n(rst_n),.vec_in(cur_vec),.scale_in(gamma_vec),.valid_in(norm1_valid_in),
    .vec_out(norm1_vec_out),.valid_out(norm1_valid_out)
  );

  rmsnorm_engine #(.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH)) u_norm2 (
    .clk(clk),.rst_n(rst_n),.vec_in(post_attn),.scale_in(gamma_vec),.valid_in(norm2_valid_in),
    .vec_out(norm2_vec_out),.valid_out(norm2_valid_out)
  );

  residual_adder #(.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH)) u_resadd1 (
    .valid_in(1'b1),.vec_a(attn_out),.vec_b(cur_vec),.valid_out(resadd1_valid_out),.vec_out(resadd1_vec_out)
  );

  residual_adder #(.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH)) u_resadd2 (
    .valid_in(1'b1),.vec_a(ffn_out),.vec_b(post_attn),.valid_out(resadd2_valid_out),.vec_out(resadd2_vec_out)
  );

  ffn_engine #(.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH),.PE_ROWS(PE_ROWS),.PE_COLS(PE_COLS)) u_ffn (
    .clk(clk),.rst_n(rst_n),.start(ffn_start),.vec_in(norm2_out),.b_wr_en(b_wr_en),
    .b_wr_sel(b_wr_sel),.b_wr_col(b_wr_col),.b_wr_data(b_wr_data),.valid_out(ffn_valid_out),.vec_out(ffn_vec_out)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=L_IDLE; layer_cnt<=4'd0; norm_wait_cnt<=2'd0; cur_vec<={(DATA_WIDTH*HEAD_DIM){1'b0}};
      norm1_out<={(DATA_WIDTH*HEAD_DIM){1'b0}}; post_attn<={(DATA_WIDTH*HEAD_DIM){1'b0}};
      norm2_out<={(DATA_WIDTH*HEAD_DIM){1'b0}}; ffn_out<={(DATA_WIDTH*HEAD_DIM){1'b0}};
      norm1_valid_in<=1'b0; norm2_valid_in<=1'b0; ffn_start<=1'b0; attn_start<=1'b0;
      attn_issued<=1'b0; ffn_issued<=1'b0; attn_vec<={(DATA_WIDTH*HEAD_DIM){1'b0}};
      valid_out<=1'b0; vec_out<={(DATA_WIDTH*HEAD_DIM){1'b0}};
    end else begin
      norm1_valid_in<=1'b0; norm2_valid_in<=1'b0; ffn_start<=1'b0; attn_start<=1'b0; valid_out<=1'b0;
      case (state)
        L_IDLE: begin
          if (start) begin
            cur_vec<=vec_in; layer_cnt<=4'd0; norm_wait_cnt<=2'd0;
            attn_issued<=1'b0; ffn_issued<=1'b0; state<=L_NORM1;
          end
        end

        L_NORM1: begin
          if (norm_wait_cnt==2'd0)
            norm1_valid_in<=1'b1;
          if (norm1_valid_out) begin
            norm1_out<=norm1_vec_out; attn_vec<=norm1_vec_out; attn_issued<=1'b0; state<=L_ATTN;
          end else begin
            norm_wait_cnt<=norm_wait_cnt+2'd1;
          end
        end

        L_ATTN: begin
          if (!attn_issued) begin attn_start<=1'b1; attn_issued<=1'b1; end
          if (attn_done) state<=L_RESADD1;
        end

        L_RESADD1: begin
          post_attn<=resadd1_vec_out; norm_wait_cnt<=2'd0; state<=L_NORM2;
        end

        L_NORM2: begin
          if (norm_wait_cnt==2'd0)
            norm2_valid_in<=1'b1;
          if (norm2_valid_out) begin
            norm2_out<=norm2_vec_out; ffn_issued<=1'b0; state<=L_FFN;
          end else begin
            norm_wait_cnt<=norm_wait_cnt+2'd1;
          end
        end

        L_FFN: begin
          if (!ffn_issued) begin ffn_start<=1'b1; ffn_issued<=1'b1; end
          if (ffn_valid_out) begin ffn_out<=ffn_vec_out; state<=L_RESADD2; end
        end

        L_RESADD2: begin
          cur_vec<=resadd2_vec_out; state<=L_NEXT;
        end

        L_NEXT: begin
          if (layer_cnt < (NUM_LAYERS-1)) begin
            layer_cnt<=layer_cnt+4'd1; norm_wait_cnt<=2'd0; attn_issued<=1'b0; state<=L_NORM1;
          end else begin
            vec_out<=cur_vec; state<=L_DONE;
          end
        end

        L_DONE: begin
          valid_out<=1'b1; state<=L_IDLE;
        end

        default: state<=L_IDLE;
      endcase
    end
  end

endmodule
