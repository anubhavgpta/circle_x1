`timescale 1ns/1ps

module tb_ffn;

  localparam HEAD_DIM   = 64;
  localparam DATA_WIDTH = 16;
  localparam PE_ROWS    = 8;
  localparam PE_COLS    = 8;

  reg                             clk;
  reg                             rst_n;
  reg                             start;
  reg  [DATA_WIDTH*HEAD_DIM-1:0]  vec_in;
  reg                             b_wr_en;
  reg  [1:0]                      b_wr_sel;
  reg  [6:0]                      b_wr_col;
  reg  [DATA_WIDTH*HEAD_DIM-1:0]  b_wr_data;
  wire                            valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0]  vec_out;

  integer i;
  integer c;
  reg all_pass;
  reg timeout_hit;
  reg [15:0] elem0;
  reg [15:0] elem63;

  ffn_engine #(
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .vec_in(vec_in),
    .b_wr_en(b_wr_en),
    .b_wr_sel(b_wr_sel),
    .b_wr_col(b_wr_col),
    .b_wr_data(b_wr_data),
    .valid_out(valid_out),
    .vec_out(vec_out)
  );

  always #5 clk = ~clk;

  function automatic bit in_range16(
    input [15:0] val,
    input [15:0] lo,
    input [15:0] hi
  );
    begin
      in_range16 = (val >= lo) && (val <= hi);
    end
  endfunction

  task automatic load_weights(
    input [1:0] sel,
    input [15:0] scale
  );
    begin
      @(posedge clk);
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        b_wr_en  <= 1'b1;
        b_wr_sel <= sel;
        b_wr_col <= c[6:0];
        for (i = 0; i < HEAD_DIM; i = i + 1) begin
          if (i == c)
            b_wr_data[i*DATA_WIDTH +: DATA_WIDTH] <= scale;
          else
            b_wr_data[i*DATA_WIDTH +: DATA_WIDTH] <= 16'h0000;
        end
        @(posedge clk);
      end
      b_wr_en  <= 1'b0;
      b_wr_sel <= 2'd0;
      b_wr_col <= 7'd0;
      b_wr_data <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
    end
  endtask

  task automatic start_and_wait_valid;
    integer t;
    begin
      timeout_hit <= 1'b0;
      start <= 1'b1;
      @(posedge clk);
      start <= 1'b0;
      for (t = 0; t < 300; t = t + 1) begin
        @(posedge clk);
        if (valid_out)
          disable start_and_wait_valid;
      end
      timeout_hit <= 1'b1;
      $display("[FFN %0t] TIMEOUT", $time);
      all_pass <= 1'b0;
    end
  endtask

  initial begin
    clk       = 1'b0;
    rst_n     = 1'b0;
    start     = 1'b0;
    vec_in    = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    b_wr_en   = 1'b0;
    b_wr_sel  = 2'd0;
    b_wr_col  = 7'd0;
    b_wr_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    all_pass  = 1'b1;
    timeout_hit = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Test 1: identity weights, unit input
    load_weights(2'd0, 16'h0100);
    load_weights(2'd1, 16'h0100);
    load_weights(2'd2, 16'h0100);
    for (i = 0; i < HEAD_DIM; i = i + 1)
      vec_in[i*DATA_WIDTH +: DATA_WIDTH] = 16'h0080;
    start_and_wait_valid();
    if (!timeout_hit) begin
      elem0  = vec_out[0 +: DATA_WIDTH];
      elem63 = vec_out[63*DATA_WIDTH +: DATA_WIDTH];
      if (in_range16(elem0, 16'h0020, 16'h0035) &&
          in_range16(elem63, 16'h0020, 16'h0035))
        $display("[FFN %0t] CHECK PASS Test1 elem0=%h elem63=%h", $time, elem0, elem63);
      else begin
        $display("[FFN %0t] CHECK FAIL Test1 elem0=%h elem63=%h", $time, elem0, elem63);
        all_pass = 1'b0;
      end
    end

    // Test 2: zero input
    load_weights(2'd0, 16'h0100);
    load_weights(2'd1, 16'h0100);
    load_weights(2'd2, 16'h0100);
    for (i = 0; i < HEAD_DIM; i = i + 1)
      vec_in[i*DATA_WIDTH +: DATA_WIDTH] = 16'h0000;
    start_and_wait_valid();
    if (!timeout_hit) begin
      elem0 = vec_out[0 +: DATA_WIDTH];
      if (elem0 == 16'h0000)
        $display("[FFN %0t] CHECK PASS Test2 elem0=%h", $time, elem0);
      else begin
        $display("[FFN %0t] CHECK FAIL Test2 elem0=%h", $time, elem0);
        all_pass = 1'b0;
      end
    end

    // Test 3: negative input
    load_weights(2'd0, 16'h0100);
    load_weights(2'd1, 16'h0100);
    load_weights(2'd2, 16'h0100);
    for (i = 0; i < HEAD_DIM; i = i + 1)
      vec_in[i*DATA_WIDTH +: DATA_WIDTH] = 16'hFF80;
    start_and_wait_valid();
    if (!timeout_hit) begin
      elem0 = vec_out[0 +: DATA_WIDTH];
      if (in_range16(elem0, 16'h000C, 16'h0025))
        $display("[FFN %0t] CHECK PASS Test3 elem0=%h", $time, elem0);
      else begin
        $display("[FFN %0t] CHECK FAIL Test3 elem0=%h", $time, elem0);
        all_pass = 1'b0;
      end
    end

    if (all_pass)
      $display("FFN SIM: PASS");
    else
      $display("FFN SIM: FAIL");

    $finish;
  end

endmodule
