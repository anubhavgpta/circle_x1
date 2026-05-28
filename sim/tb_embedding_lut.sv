`timescale 1ns/1ps

module tb_embedding_lut;
  localparam integer VOCAB_SIZE = 32000;
  localparam integer HEAD_DIM   = 64;
  localparam integer DATA_WIDTH = 16;

  reg clk;
  reg rst_n;
  reg wr_en;
  reg [14:0] wr_addr;
  reg [DATA_WIDTH*HEAD_DIM-1:0] wr_data;
  reg rd_en;
  reg [14:0] rd_addr;
  wire valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0] emb_out;

  integer i;
  integer pass_count;
  integer fail_count;
  reg [DATA_WIDTH*HEAD_DIM-1:0] row_data;
  reg [DATA_WIDTH-1:0] elem0;
  reg [DATA_WIDTH-1:0] elem1;
  reg [DATA_WIDTH-1:0] elem63;

  embedding_lut #(
    .VOCAB_SIZE(VOCAB_SIZE),
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .valid_out(valid_out),
    .emb_out(emb_out)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task preload_token;
    input [14:0] token;
    input [DATA_WIDTH*HEAD_DIM-1:0] data_in;
    begin
      @(negedge clk);
      wr_en   <= 1'b1;
      wr_addr <= token;
      wr_data <= data_in;
      rd_en   <= 1'b0;
      rd_addr <= 15'd0;
      @(posedge clk);
    end
  endtask

  task issue_lookup;
    input [14:0] token;
    begin
      @(negedge clk);
      rd_en   <= 1'b1;
      rd_addr <= token;
      wr_en   <= 1'b0;
      wr_addr <= 15'd0;
      wr_data <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      @(posedge clk);
      @(negedge clk);
      rd_en <= 1'b0;
    end
  endtask

  initial begin
    rst_n      = 1'b0;
    wr_en      = 1'b0;
    wr_addr    = 15'd0;
    wr_data    = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    rd_en      = 1'b0;
    rd_addr    = 15'd0;
    pass_count = 0;
    fail_count = 0;
    row_data   = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    elem0      = {DATA_WIDTH{1'b0}};
    elem1      = {DATA_WIDTH{1'b0}};
    elem63     = {DATA_WIDTH{1'b0}};

    repeat (2) @(posedge clk);
    rst_n <= 1'b1;

    // Preload token 0: all 0x0100
    row_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      row_data[(i*DATA_WIDTH) +: DATA_WIDTH] = 16'h0100;
    end
    preload_token(15'd0, row_data);

    // Preload token 1: all 0x0200
    row_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      row_data[(i*DATA_WIDTH) +: DATA_WIDTH] = 16'h0200;
    end
    preload_token(15'd1, row_data);

    // Preload token 2: all 0x0080
    row_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      row_data[(i*DATA_WIDTH) +: DATA_WIDTH] = 16'h0080;
    end
    preload_token(15'd2, row_data);

    // Preload token 3: ramp (i+1)*0x10
    row_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    for (i = 0; i < HEAD_DIM; i = i + 1) begin
      row_data[(i*DATA_WIDTH) +: DATA_WIDTH] = (i + 1) * 16'h0010;
    end
    preload_token(15'd3, row_data);

    @(negedge clk);
    wr_en   <= 1'b0;
    wr_addr <= 15'd0;
    wr_data <= {(DATA_WIDTH*HEAD_DIM){1'b0}};

    // Test 1: lookup token 0
    issue_lookup(15'd0);
    @(posedge clk);
    @(posedge clk);
    elem0  = emb_out[15:0];
    elem63 = emb_out[HEAD_DIM*DATA_WIDTH-1 -: DATA_WIDTH];
    if (valid_out && (elem0 == 16'h0100) && (elem63 == 16'h0100)) begin
      pass_count = pass_count + 1;
      $display("[EMB %0t] TEST1 CHECK PASS", $time);
    end else begin
      fail_count = fail_count + 1;
      $display("[EMB %0t] TEST1 CHECK FAIL", $time);
    end

    // Test 2: lookup token 2
    issue_lookup(15'd2);
    @(posedge clk);
    @(posedge clk);
    elem0 = emb_out[15:0];
    if (valid_out && (elem0 == 16'h0080)) begin
      pass_count = pass_count + 1;
      $display("[EMB %0t] TEST2 CHECK PASS", $time);
    end else begin
      fail_count = fail_count + 1;
      $display("[EMB %0t] TEST2 CHECK FAIL", $time);
    end

    // Test 3: ramp lookup token 3
    issue_lookup(15'd3);
    @(posedge clk);
    @(posedge clk);
    elem0  = emb_out[15:0];
    elem1  = emb_out[31:16];
    elem63 = emb_out[HEAD_DIM*DATA_WIDTH-1 -: DATA_WIDTH];
    if (valid_out && (elem0 == 16'h0010) && (elem1 == 16'h0020) && (elem63 == 16'h0400)) begin
      pass_count = pass_count + 1;
      $display("[EMB %0t] TEST3 CHECK PASS", $time);
    end else begin
      fail_count = fail_count + 1;
      $display("[EMB %0t] TEST3 CHECK FAIL", $time);
    end

    // Test 4: back-to-back lookup token 0 then token 1
    @(negedge clk);
    rd_en   <= 1'b1;
    rd_addr <= 15'd0;
    wr_en   <= 1'b0;
    @(posedge clk);
    @(negedge clk);
    rd_en   <= 1'b1;
    rd_addr <= 15'd1;
    @(posedge clk);
    @(negedge clk);
    rd_en   <= 1'b0;
    @(posedge clk);
    elem0 = emb_out[15:0];
    if (valid_out && (elem0 == 16'h0100)) begin
      pass_count = pass_count + 1;
      $display("[EMB %0t] TEST4A CHECK PASS", $time);
    end else begin
      fail_count = fail_count + 1;
      $display("[EMB %0t] TEST4A CHECK FAIL", $time);
    end

    @(posedge clk);
    elem0 = emb_out[15:0];
    if (valid_out && (elem0 == 16'h0200)) begin
      pass_count = pass_count + 1;
      $display("[EMB %0t] TEST4B CHECK PASS", $time);
    end else begin
      fail_count = fail_count + 1;
      $display("[EMB %0t] TEST4B CHECK FAIL", $time);
    end

    if (fail_count == 0) begin
      $display("EMBEDDING SIM: PASS");
    end else begin
      $display("EMBEDDING SIM: FAIL");
    end

    $finish;
  end

endmodule
