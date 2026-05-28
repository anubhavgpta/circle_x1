`timescale 1ns/1ps

module tb_lm_head;
  localparam VOCAB_SIZE = 128;
  localparam HEAD_DIM   = 64;
  localparam DATA_WIDTH = 16;
  localparam PE_ROWS    = 8;
  localparam PE_COLS    = 8;
  localparam NUM_TILES  = VOCAB_SIZE / HEAD_DIM;

  reg clk;
  reg rst_n;
  reg wr_en;
  reg [14:0] wr_col;
  reg [DATA_WIDTH*HEAD_DIM-1:0] wr_data;
  reg start;
  reg [DATA_WIDTH*HEAD_DIM-1:0] hidden_vec;
  wire logit_valid;
  wire logit_last;
  wire [DATA_WIDTH*HEAD_DIM-1:0] logit_data;

  integer i, k;
  integer valid_count;
  integer last_tile_idx;
  integer cycle_count;
  integer pass_count;
  reg first_tile_nonzero;
  reg timed_out;
  reg done_collect;

  lm_head #(
    .VOCAB_SIZE(VOCAB_SIZE),
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .wr_col(wr_col),
    .wr_data(wr_data),
    .start(start),
    .hidden_vec(hidden_vec),
    .logit_valid(logit_valid),
    .logit_last(logit_last),
    .logit_data(logit_data)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    wr_en = 1'b0;
    wr_col = 15'd0;
    wr_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    start = 1'b0;
    hidden_vec = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    valid_count = 0;
    last_tile_idx = -1;
    cycle_count = 0;
    pass_count = 0;
    first_tile_nonzero = 1'b0;
    timed_out = 1'b0;
    done_collect = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    for (i = 0; i < VOCAB_SIZE; i = i + 1) begin
      wr_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
      wr_data[(i % HEAD_DIM)*DATA_WIDTH +: DATA_WIDTH] = 16'h0100;
      wr_col = i[14:0];
      wr_en = 1'b1;
      @(posedge clk);
    end
    wr_en = 1'b0;

    for (k = 0; k < HEAD_DIM; k = k + 1)
      hidden_vec[k*DATA_WIDTH +: DATA_WIDTH] = 16'h0080;

    @(posedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    while (!done_collect && !timed_out) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count > 5000) begin
        timed_out = 1'b1;
      end
      if (logit_valid) begin
        if (valid_count == 0) begin
          first_tile_nonzero = (logit_data[15:0] !== 16'h0000);
        end
        if (logit_last) begin
          last_tile_idx = valid_count;
          done_collect = 1'b1;
        end
        valid_count = valid_count + 1;
      end
    end

    if (valid_count == NUM_TILES) begin
      $display("[LM %0t] CHECK PASS: logit_valid count == NUM_TILES (%0d)", $time, NUM_TILES);
      pass_count = pass_count + 1;
    end else begin
      $display("[LM %0t] CHECK FAIL: logit_valid count=%0d expected=%0d", $time, valid_count, NUM_TILES);
    end

    if (first_tile_nonzero) begin
      $display("[LM %0t] CHECK PASS: first tile logit_data[15:0] is non-zero", $time);
      pass_count = pass_count + 1;
    end else begin
      $display("[LM %0t] CHECK FAIL: first tile logit_data[15:0] is zero", $time);
    end

    if (last_tile_idx == (NUM_TILES-1)) begin
      $display("[LM %0t] CHECK PASS: logit_last on final tile index %0d", $time, NUM_TILES-1);
      pass_count = pass_count + 1;
    end else begin
      $display("[LM %0t] CHECK FAIL: logit_last at tile index %0d expected %0d", $time, last_tile_idx, NUM_TILES-1);
    end

    if (timed_out) begin
      $display("[LM %0t] CHECK FAIL: timeout after %0d cycles", $time, cycle_count);
    end else begin
      $display("[LM %0t] CHECK PASS: completed before timeout (%0d cycles)", $time, cycle_count);
      pass_count = pass_count + 1;
    end

    if (pass_count == 4)
      $display("LM_HEAD SIM: PASS");
    else
      $display("LM_HEAD SIM: FAIL");

    #20;
    $finish;
  end

endmodule
