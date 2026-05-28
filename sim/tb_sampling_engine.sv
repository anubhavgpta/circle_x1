`timescale 1ns/1ps

module tb_sampling_engine;
  localparam VOCAB_SIZE = 128;
  localparam HEAD_DIM   = 64;
  localparam DATA_WIDTH = 16;
  localparam TOP_K      = 8;
  localparam NUM_TILES  = VOCAB_SIZE / HEAD_DIM;

  reg clk;
  reg rst_n;
  reg start;
  reg logit_valid;
  reg logit_last;
  reg [DATA_WIDTH*HEAD_DIM-1:0] logit_data;
  reg [2:0] temp_shift;
  reg [15:0] p_threshold;
  wire valid_out;
  wire [14:0] token_id;

  integer j;
  integer pass_count;
  integer wait_cycles;
  reg timed_out;

  sampling_engine #(
    .VOCAB_SIZE(VOCAB_SIZE),
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .TOP_K(TOP_K)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .logit_valid(logit_valid),
    .logit_last(logit_last),
    .logit_data(logit_data),
    .temp_shift(temp_shift),
    .p_threshold(p_threshold),
    .valid_out(valid_out),
    .token_id(token_id)
  );

  always #5 clk = ~clk;

  task automatic drive_tile(input integer tile_idx, input [15:0] scale);
    integer jj;
    logit_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    for (jj = 0; jj < HEAD_DIM; jj = jj + 1)
      logit_data[jj*DATA_WIDTH +: DATA_WIDTH] = (jj + 1) * scale;
  endtask

  task automatic run_test(input [2:0] tshift, input integer test_num);
    begin
      temp_shift = tshift;
      p_threshold = 16'h7FFF;
      start = 1'b1;
      logit_valid = 1'b0;
      logit_last = 1'b0;
      logit_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
      @(posedge clk);
      start = 1'b0;

      drive_tile(0, 16'h0010);
      logit_valid = 1'b1;
      logit_last = 1'b0;
      @(posedge clk);

      drive_tile(1, 16'h0008);
      logit_valid = 1'b1;
      logit_last = 1'b1;
      @(posedge clk);

      logit_valid = 1'b0;
      logit_last = 1'b0;

      timed_out = 1'b0;
      wait_cycles = 0;
      while (!valid_out && wait_cycles < 500) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles >= 500) timed_out = 1'b1;

      if (timed_out) begin
        $display("[SAMP %0t] CHECK FAIL test %0d timeout", $time, test_num);
      end else if (token_id == 15'd63) begin
        $display("[SAMP %0t] CHECK PASS test %0d token_id=%0d", $time, test_num, token_id);
        pass_count = pass_count + 1;
      end else begin
        $display("[SAMP %0t] CHECK FAIL test %0d token_id=%0d expected 63", $time, test_num, token_id);
      end

      repeat (5) @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    logit_valid = 1'b0;
    logit_last = 1'b0;
    logit_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    temp_shift = 3'd0;
    p_threshold = 16'h7FFF;
    pass_count = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    run_test(3'd0, 1);
    run_test(3'd1, 2);

    if (pass_count == 2)
      $display("SAMPLING SIM: PASS");
    else
      $display("SAMPLING SIM: FAIL");
    $finish;
  end

endmodule
