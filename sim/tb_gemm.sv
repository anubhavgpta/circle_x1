`timescale 1ns/1ps

module tb_gemm;
  localparam integer HEAD_DIM   = 64;
  localparam integer DATA_WIDTH = 16;
  localparam integer PE_ROWS    = 8;
  localparam integer PE_COLS    = 8;
  localparam integer CLK_PERIOD = 10;

  reg clk;
  reg rst_n;
  reg start;
  reg [6:0] m_size;
  reg [6:0] n_size;
  reg a_valid;
  reg [DATA_WIDTH*PE_COLS-1:0] a_data;
  reg b_wr_en;
  reg [6:0] b_wr_col;
  reg [DATA_WIDTH*HEAD_DIM-1:0] b_wr_data;
  wire valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0] result_out;

  reg overall_pass;
  integer i;
  integer cycle_wait;
  reg [15:0] expected_val;
  reg [15:0] elem0;
  reg [15:0] elem63;

  gemm_engine #(
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .m_size(m_size),
    .n_size(n_size),
    .a_valid(a_valid),
    .a_data(a_data),
    .b_wr_en(b_wr_en),
    .b_wr_col(b_wr_col),
    .b_wr_data(b_wr_data),
    .valid_out(valid_out),
    .result_out(result_out)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  task automatic load_identity(input reg [15:0] scale);
    integer col;
    integer row;
    begin
      b_wr_en   = 1'b0;
      b_wr_col  = 7'd0;
      b_wr_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
      @(posedge clk);
      for (col = 0; col < HEAD_DIM; col = col + 1) begin
        for (row = 0; row < HEAD_DIM; row = row + 1) begin
          if (row == col) begin
            b_wr_data[row*DATA_WIDTH +: DATA_WIDTH] = scale;
          end else begin
            b_wr_data[row*DATA_WIDTH +: DATA_WIDTH] = 16'h0000;
          end
        end
        b_wr_col = col[6:0];
        b_wr_en  = 1'b1;
        @(posedge clk);
        b_wr_en = 1'b0;
        @(posedge clk);
      end
    end
  endtask

  task automatic run_gemm(input reg [15:0] a_val);
    begin
      m_size = 7'd1;
      n_size = 7'd64;

      start = 1'b1;
      @(posedge clk);
      start = 1'b0;

      a_valid = 1'b1;
      a_data  = {PE_COLS{a_val}};
      for (i = 0; i < 8; i = i + 1) begin
        @(posedge clk);
      end
      a_valid = 1'b0;
      a_data  = {(DATA_WIDTH*PE_COLS){1'b0}};

      cycle_wait = 0;
      while ((valid_out !== 1'b1) && (cycle_wait < 200)) begin
        @(posedge clk);
        cycle_wait = cycle_wait + 1;
      end

      if (valid_out !== 1'b1) begin
        $display("[GEMM %0t] TIMEOUT", $time);
        overall_pass = 1'b0;
      end
    end
  endtask

  task automatic check_with_tolerance(
    input [15:0] actual,
    input [15:0] expected,
    input [255:0] tag
  );
    reg pass_local;
    integer diff_abs;
    begin
      if (actual >= expected) begin
        diff_abs = actual - expected;
      end else begin
        diff_abs = expected - actual;
      end
      pass_local = (diff_abs <= 1);
      if (pass_local) begin
        $display("[GEMM %0t] CHECK PASS %0s actual=0x%04h expected=0x%04h", $time, tag, actual, expected);
      end else begin
        $display("[GEMM %0t] CHECK FAIL %0s actual=0x%04h expected=0x%04h", $time, tag, actual, expected);
        overall_pass = 1'b0;
      end
    end
  endtask

  initial begin
    rst_n       = 1'b0;
    start       = 1'b0;
    m_size      = 7'd0;
    n_size      = 7'd0;
    a_valid     = 1'b0;
    a_data      = {(DATA_WIDTH*PE_COLS){1'b0}};
    b_wr_en     = 1'b0;
    b_wr_col    = 7'd0;
    b_wr_data   = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    overall_pass = 1'b1;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Test 1: identity scale=1.0 and a_val=0.5 => output 0.5
    load_identity(16'h0100);
    run_gemm(16'h0080);
    expected_val = 16'h0080;
    elem0  = result_out[15:0];
    elem63 = result_out[1023:1008];
    check_with_tolerance(elem0, expected_val, "test1_elem0");
    check_with_tolerance(elem63, expected_val, "test1_elem63");

    // Clear DUT accumulators/state before second independent test.
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Test 2: identity scale=2.0 and a_val=0.25 => output 0.5
    load_identity(16'h0200);
    run_gemm(16'h0040);
    expected_val = 16'h0080;
    elem0  = result_out[15:0];
    elem63 = result_out[1023:1008];
    check_with_tolerance(elem0, expected_val, "test2_elem0");
    check_with_tolerance(elem63, expected_val, "test2_elem63");

    if (overall_pass) begin
      $display("GEMM SIM: PASS");
    end else begin
      $display("GEMM SIM: FAIL");
    end

    #20;
    $finish;
  end

endmodule
