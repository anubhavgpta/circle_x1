`timescale 1ns/1ps
module residual_adder #(
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16
)(
  input  wire                           valid_in,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0] vec_a,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0] vec_b,
  output wire                           valid_out,
  output wire [DATA_WIDTH*HEAD_DIM-1:0] vec_out
);

  assign valid_out = valid_in;

  genvar i;
  generate
    for (i = 0; i < HEAD_DIM; i = i + 1) begin : gen_add
      wire signed [16:0] sum;
      wire signed [15:0] a_elem = vec_a[DATA_WIDTH*i +: DATA_WIDTH];
      wire signed [15:0] b_elem = vec_b[DATA_WIDTH*i +: DATA_WIDTH];

      assign sum = {a_elem[15], a_elem} + {b_elem[15], b_elem};

      assign vec_out[DATA_WIDTH*i +: DATA_WIDTH] =
        (sum[16:15] == 2'b01) ? 16'h7FFF :
        (sum[16:15] == 2'b10) ? 16'h8000 :
        sum[15:0];
    end
  endgenerate

endmodule
