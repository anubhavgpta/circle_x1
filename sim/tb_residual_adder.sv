`timescale 1ns/1ps

module tb_residual_adder;

  localparam HEAD_DIM   = 64;
  localparam DATA_WIDTH = 16;

  reg                            valid_in;
  reg  [DATA_WIDTH*HEAD_DIM-1:0] vec_a;
  reg  [DATA_WIDTH*HEAD_DIM-1:0] vec_b;
  wire                           valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0] vec_out;

  residual_adder #(.HEAD_DIM(HEAD_DIM), .DATA_WIDTH(DATA_WIDTH)) dut (
    .valid_in  (valid_in),
    .vec_a     (vec_a),
    .vec_b     (vec_b),
    .valid_out (valid_out),
    .vec_out   (vec_out)
  );

  integer i;
  integer all_pass;

  // Returns 1 if check passes, prints result
  task automatic chk;
    input integer   tnum;
    input [15:0]    e0_act;
    input [15:0]    e0_exp;
    input [15:0]    e63_act;
    input [15:0]    e63_exp;
    input           vout;
    begin
      if (vout === 1'b1 && e0_act === e0_exp && e63_act === e63_exp) begin
        $display("[RADD %0t] CHECK PASS test%0d", $time, tnum);
      end else begin
        $display("[RADD %0t] CHECK FAIL test%0d: valid_out=%b elem0_act=%h elem0_exp=%h elem63_act=%h elem63_exp=%h",
                 $time, tnum, vout, e0_act, e0_exp, e63_act, e63_exp);
        all_pass = 0;
      end
    end
  endtask

  initial begin
    all_pass = 1;
    valid_in = 1;
    vec_a    = 0;
    vec_b    = 0;

    // Test 1: normal add 1.0+1.0=2.0 (Q8.8: 0080+0080=0100)
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      vec_a[DATA_WIDTH*i +: DATA_WIDTH] = 16'h0080;
      vec_b[DATA_WIDTH*i +: DATA_WIDTH] = 16'h0080;
    end
    #5;
    chk(1, vec_out[15:0], 16'h0100,
           vec_out[DATA_WIDTH*63 +: DATA_WIDTH], 16'h0100, valid_out);

    // Test 2: positive saturation (7F00+0200 -> 7FFF)
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      vec_a[DATA_WIDTH*i +: DATA_WIDTH] = 16'h7F00;
      vec_b[DATA_WIDTH*i +: DATA_WIDTH] = 16'h0200;
    end
    #5;
    chk(2, vec_out[15:0], 16'h7FFF,
           vec_out[DATA_WIDTH*63 +: DATA_WIDTH], 16'h7FFF, valid_out);

    // Test 3: negative saturation (8100+FE00 -> 8000)
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      vec_a[DATA_WIDTH*i +: DATA_WIDTH] = 16'h8100;
      vec_b[DATA_WIDTH*i +: DATA_WIDTH] = 16'hFE00;
    end
    #5;
    chk(3, vec_out[15:0], 16'h8000,
           vec_out[DATA_WIDTH*63 +: DATA_WIDTH], 16'h8000, valid_out);

    // Test 4: mixed - even elems 0040+0040=0080, odd elems FF80+FF80=FF00
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      if (i % 2 == 0) begin
        vec_a[DATA_WIDTH*i +: DATA_WIDTH] = 16'h0040;
        vec_b[DATA_WIDTH*i +: DATA_WIDTH] = 16'h0040;
      end else begin
        vec_a[DATA_WIDTH*i +: DATA_WIDTH] = 16'hFF80;
        vec_b[DATA_WIDTH*i +: DATA_WIDTH] = 16'hFF80;
      end
    end
    #5;
    // elem0 is even -> 0080, elem63 is odd -> FF00
    chk(4, vec_out[15:0], 16'h0080,
           vec_out[DATA_WIDTH*63 +: DATA_WIDTH], 16'hFF00, valid_out);

    if (all_pass)
      $display("RESIDUAL_ADDER SIM: PASS");
    else
      $display("RESIDUAL_ADDER SIM: FAIL");

    $finish;
  end

endmodule
