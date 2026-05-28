`timescale 1ns/1ps

module tb_multihead_ctrl;

  localparam NUM_HEADS  = 8;
  localparam HEAD_DIM   = 64;
  localparam DATA_WIDTH = 16;
  localparam VEC_W      = DATA_WIDTH*HEAD_DIM*NUM_HEADS;
  localparam HEAD_W     = DATA_WIDTH*HEAD_DIM;

  reg clk;
  reg rst_n;
  reg start;
  reg [VEC_W-1:0] vec_in;
  wire attn_start;
  wire [HEAD_W-1:0] attn_q;
  reg attn_done;
  reg [HEAD_W-1:0] attn_out;
  wire valid_out;
  wire [VEC_W-1:0] vec_out;

  reg [VEC_W-1:0] expected_vec;
  reg all_pass;
  integer i;
  integer j;
  integer timeout_ctr;
  reg [15:0] exp_h0_e0;
  reg [15:0] exp_h7_e0;
  reg [15:0] got_h0_e0;
  reg [15:0] got_h7_e0;
  reg [15:0] exp_zero;

  reg [2:0] attn_delay;
  reg       attn_pending;
  reg [HEAD_W-1:0] attn_q_lat;

  multihead_ctrl #(
    .NUM_HEADS(NUM_HEADS),
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .vec_in(vec_in),
    .attn_start(attn_start),
    .attn_q(attn_q),
    .attn_done(attn_done),
    .attn_out(attn_out),
    .valid_out(valid_out),
    .vec_out(vec_out)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      attn_done    <= 1'b0;
      attn_out     <= {HEAD_W{1'b0}};
      attn_delay   <= 3'd0;
      attn_pending <= 1'b0;
      attn_q_lat   <= {HEAD_W{1'b0}};
    end else begin
      attn_done <= 1'b0;

      if (attn_start) begin
        attn_pending <= 1'b1;
        attn_delay   <= 3'd3;
        attn_q_lat   <= attn_q;
      end else if (attn_pending) begin
        if (attn_delay != 3'd0) begin
          attn_delay <= attn_delay - 1'b1;
        end

        if (attn_delay == 3'd1) begin
          attn_done    <= 1'b1;
          attn_out     <= attn_q_lat;
          attn_pending <= 1'b0;
        end
      end
    end
  end

  task automatic wait_valid_or_timeout;
    begin
      timeout_ctr = 0;
      while ((valid_out !== 1'b1) && (timeout_ctr < 500)) begin
        @(posedge clk);
        timeout_ctr = timeout_ctr + 1;
      end
      if (valid_out !== 1'b1) begin
        $display("[MH %0t] TIMEOUT, force FAIL", $time);
        all_pass = 1'b0;
      end
    end
  endtask

  initial begin
    rst_n       = 1'b0;
    start       = 1'b0;
    vec_in      = {VEC_W{1'b0}};
    expected_vec= {VEC_W{1'b0}};
    all_pass    = 1'b1;
    exp_h0_e0   = 16'h0000;
    exp_h7_e0   = 16'h0000;
    got_h0_e0   = 16'h0000;
    got_h7_e0   = 16'h0000;
    exp_zero    = 16'h0000;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    // Test 1
    expected_vec = {VEC_W{1'b0}};
    for (i = 0; i < NUM_HEADS; i = i + 1) begin
      for (j = 0; j < HEAD_DIM; j = j + 1) begin
        expected_vec[(i*HEAD_DIM + j)*DATA_WIDTH +: DATA_WIDTH] = 16'h0100 * (i + 1);
      end
    end
    vec_in = expected_vec;

    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    wait_valid_or_timeout();
    @(posedge clk);

    if (valid_out === 1'b1) begin
      if (vec_out === expected_vec) begin
        $display("[MH %0t] CHECK PASS Test1 vec_out identity", $time);
      end else begin
        $display("[MH %0t] CHECK FAIL Test1 vec_out identity actual=%h expected=%h", $time, vec_out, expected_vec);
        all_pass = 1'b0;
      end

      exp_h0_e0 = 16'h0100;
      exp_h7_e0 = 16'h0800;
      got_h0_e0 = vec_out[0 +: 16];
      got_h7_e0 = vec_out[((7*HEAD_DIM)*DATA_WIDTH) +: 16];

      if ((got_h0_e0 == exp_h0_e0) && (got_h7_e0 == exp_h7_e0)) begin
        $display("[MH %0t] CHECK PASS Test1 head elem checks actual_h0=%h expected_h0=%h actual_h7=%h expected_h7=%h",
                 $time, got_h0_e0, exp_h0_e0, got_h7_e0, exp_h7_e0);
      end else begin
        $display("[MH %0t] CHECK FAIL Test1 head elem checks actual_h0=%h expected_h0=%h actual_h7=%h expected_h7=%h",
                 $time, got_h0_e0, exp_h0_e0, got_h7_e0, exp_h7_e0);
        all_pass = 1'b0;
      end
    end

    // Test 2
    expected_vec = {VEC_W{1'b0}};
    vec_in       = {VEC_W{1'b0}};

    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    wait_valid_or_timeout();
    @(posedge clk);

    if (valid_out === 1'b1) begin
      if (vec_out === expected_vec) begin
        $display("[MH %0t] CHECK PASS Test2 vec_out zeros", $time);
      end else begin
        $display("[MH %0t] CHECK FAIL Test2 vec_out zeros actual=%h expected=%h", $time, vec_out, expected_vec);
        all_pass = 1'b0;
      end

      exp_zero  = 16'h0000;
      got_h0_e0 = vec_out[0 +: 16];
      if (got_h0_e0 == exp_zero) begin
        $display("[MH %0t] CHECK PASS Test2 head0 elem0 actual=%h expected=%h", $time, got_h0_e0, exp_zero);
      end else begin
        $display("[MH %0t] CHECK FAIL Test2 head0 elem0 actual=%h expected=%h", $time, got_h0_e0, exp_zero);
        all_pass = 1'b0;
      end
    end

    if (all_pass) begin
      $display("MULTIHEAD SIM: PASS");
    end else begin
      $display("MULTIHEAD SIM: FAIL");
    end

    #20;
    $finish;
  end

endmodule
