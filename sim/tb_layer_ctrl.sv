`timescale 1ns/1ps

module tb_layer_ctrl;

  localparam NUM_LAYERS = 4;
  localparam HEAD_DIM   = 64;
  localparam DATA_WIDTH = 16;
  localparam PE_ROWS    = 8;
  localparam PE_COLS    = 8;

  reg                             clk;
  reg                             rst_n;
  reg                             start;
  reg  [DATA_WIDTH*HEAD_DIM-1:0]  vec_in;

  wire                            attn_start;
  wire [DATA_WIDTH*HEAD_DIM-1:0]  attn_vec;
  reg                             attn_done;
  reg  [DATA_WIDTH*HEAD_DIM-1:0]  attn_out;

  reg                             b_wr_en;
  reg  [1:0]                      b_wr_sel;
  reg  [6:0]                      b_wr_col;
  reg  [DATA_WIDTH*HEAD_DIM-1:0]  b_wr_data;
  reg  [31:0]                     gamma_word [0:31];

  wire                            valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0]  vec_out;

  integer i;
  integer c;
  integer t;
  reg all_pass;
  reg timeout_hit;
  reg [15:0] elem0_now;
  reg [15:0] elem0_next;
  reg [DATA_WIDTH*HEAD_DIM-1:0] attn_buf;
  reg [2:0] attn_wait_cnt;
  reg attn_pending;

  layer_ctrl #(
    .NUM_LAYERS(NUM_LAYERS),
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .vec_in(vec_in),
    .attn_start(attn_start),
    .attn_vec(attn_vec),
    .attn_done(attn_done),
    .attn_out(attn_out),
    .b_wr_en(b_wr_en),
    .b_wr_sel(b_wr_sel),
    .b_wr_col(b_wr_col),
    .b_wr_data(b_wr_data),
    .gamma_word(gamma_word),
    .valid_out(valid_out),
    .vec_out(vec_out)
  );

  always #5 clk = ~clk;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      attn_done <= 1'b0;
      attn_out <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      attn_buf <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      attn_wait_cnt <= 3'd0;
      attn_pending <= 1'b0;
    end else begin
      attn_done <= 1'b0;
      if (attn_start && !attn_pending) begin
        attn_pending <= 1'b1;
        attn_wait_cnt <= 3'd5;
        attn_buf <= attn_vec;
      end else if (attn_pending) begin
        if (attn_wait_cnt != 3'd0) begin
          attn_wait_cnt <= attn_wait_cnt - 3'd1;
        end else begin
          attn_done <= 1'b1;
          attn_out <= attn_buf;
          attn_pending <= 1'b0;
        end
      end
    end
  end

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
      b_wr_en   <= 1'b0;
      b_wr_sel  <= 2'd0;
      b_wr_col  <= 7'd0;
      b_wr_data <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
    end
  endtask

  task automatic start_and_wait_valid;
    begin
      timeout_hit <= 1'b0;
      start <= 1'b1;
      @(posedge clk);
      start <= 1'b0;
      for (t = 0; t < 2000; t = t + 1) begin
        @(posedge clk);
        if (valid_out)
          disable start_and_wait_valid;
      end
      timeout_hit <= 1'b1;
      $display("[LC %0t] TIMEOUT, force FAIL", $time);
      all_pass <= 1'b0;
    end
  endtask

  initial begin
    clk       = 1'b0;
    rst_n     = 1'b0;
    start     = 1'b0;
    vec_in    = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    attn_done = 1'b0;
    attn_out  = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    b_wr_en   = 1'b0;
    b_wr_sel  = 2'd0;
    b_wr_col  = 7'd0;
    b_wr_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    all_pass  = 1'b1;
    timeout_hit = 1'b0;
    for (i = 0; i < 32; i = i + 1)
      gamma_word[i] = 32'h01000100;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    load_weights(2'd0, 16'h0100);
    load_weights(2'd1, 16'h0100);
    load_weights(2'd2, 16'h0100);

    // Test 1
    for (i = 0; i < HEAD_DIM; i = i + 1)
      vec_in[i*DATA_WIDTH +: DATA_WIDTH] = 16'h0080;
    start_and_wait_valid();
    if (!timeout_hit) begin
      elem0_now = vec_out[0 +: DATA_WIDTH];
      @(posedge clk);
      elem0_next = vec_out[0 +: DATA_WIDTH];
      if ((elem0_now != 16'h0000) && (elem0_now == elem0_next))
        $display("[LC %0t] CHECK PASS Test1 elem0=%h", $time, elem0_now);
      else begin
        $display("[LC %0t] CHECK FAIL Test1 elem0_now=%h elem0_next=%h", $time, elem0_now, elem0_next);
        all_pass = 1'b0;
      end
    end

    // Test 2
    for (i = 0; i < HEAD_DIM; i = i + 1)
      vec_in[i*DATA_WIDTH +: DATA_WIDTH] = 16'h0000;
    start_and_wait_valid();
    if (!timeout_hit) begin
      elem0_now = vec_out[0 +: DATA_WIDTH];
      if (elem0_now == 16'h0000)
        $display("[LC %0t] CHECK PASS Test2 elem0=%h", $time, elem0_now);
      else begin
        $display("[LC %0t] CHECK FAIL Test2 elem0=%h", $time, elem0_now);
        all_pass = 1'b0;
      end
    end

    if (all_pass)
      $display("LAYER_CTRL SIM: PASS");
    else
      $display("LAYER_CTRL SIM: FAIL");

    $finish;
  end

endmodule
