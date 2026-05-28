`timescale 1ns/1ps

module tb_dma_engine;

  localparam DATA_W = 16;
  localparam H_DIM  = 64;
  localparam BUS_W  = DATA_W * H_DIM;  // 1024

  reg               clk, rst_n;
  reg  [31:0]       src_addr;
  reg  [1:0]        dst_sel;
  reg  [14:0]       dst_addr;
  reg  [9:0]        length;
  reg               start;
  wire              done;
  reg               dram_valid;
  reg  [BUS_W-1:0]  dram_data;
  wire              dram_ready;
  wire              emb_wr_en;
  wire [14:0]       emb_wr_addr;
  wire [BUS_W-1:0]  emb_wr_data;
  wire              lm_wr_en;
  wire [14:0]       lm_wr_col;
  wire [BUS_W-1:0]  lm_wr_data;
  wire              ffn_wr_en;
  wire [1:0]        ffn_b_wr_sel;
  wire [6:0]        ffn_b_wr_col;
  wire [BUS_W-1:0]  ffn_wr_data;
  wire              gam_wr_en;
  wire [4:0]        gam_wr_addr;
  wire [31:0]       gam_wr_data;

  dma_engine #(.DATA_WIDTH(DATA_W), .HEAD_DIM(H_DIM)) dut (
    .clk(clk), .rst_n(rst_n),
    .src_addr(src_addr), .dst_sel(dst_sel), .dst_addr(dst_addr),
    .length(length), .start(start), .done(done),
    .dram_valid(dram_valid), .dram_data(dram_data), .dram_ready(dram_ready),
    .emb_wr_en(emb_wr_en), .emb_wr_addr(emb_wr_addr), .emb_wr_data(emb_wr_data),
    .lm_wr_en(lm_wr_en), .lm_wr_col(lm_wr_col), .lm_wr_data(lm_wr_data),
    .ffn_wr_en(ffn_wr_en), .ffn_b_wr_sel(ffn_b_wr_sel), .ffn_b_wr_col(ffn_b_wr_col),
    .ffn_wr_data(ffn_wr_data),
    .gam_wr_en(gam_wr_en), .gam_wr_addr(gam_wr_addr), .gam_wr_data(gam_wr_data)
  );

  always #5 clk = ~clk;

  // Shared temporaries
  integer      pass_cnt, fail_cnt;
  integer      i;
  reg [BUS_W-1:0] wd;
  reg [31:0]      ed;
  reg [14:0]      ea;

  task chk;
    input [31:0]  cond;
    input [255:0] lbl;
    begin
      if (|cond) begin
        $display("[DMA %0t] CHECK %0s -> PASS", $time, lbl);
        pass_cnt = pass_cnt + 1;
      end else begin
        $display("[DMA %0t] CHECK %0s -> FAIL", $time, lbl);
        fail_cnt = fail_cnt + 1;
      end
    end
  endtask

  // Pulse start and wait until DUT is in D_ACTIVE (dram_ready high).
  // Descriptor must be set before calling.
  task arm_transfer;
    begin
      dram_valid = 1'b0;
      @(posedge clk); #1;
      start = 1'b1;
      @(posedge clk); #1;
      start = 1'b0;
      // dram_ready is now 1 (latched at end of above posedge)
    end
  endtask

  initial begin
    clk        = 1'b0;
    rst_n      = 1'b0;
    start      = 1'b0;
    dram_valid = 1'b0;
    dram_data  = {BUS_W{1'b0}};
    src_addr   = 32'd0;
    dst_sel    = 2'd0;
    dst_addr   = 15'd0;
    length     = 10'd1;
    pass_cnt   = 0;
    fail_cnt   = 0;

    repeat (4) @(posedge clk);
    #1; rst_n = 1'b1;
    repeat (2) @(posedge clk); #1;

    // ================================================================
    // Test 1 — embedding transfer (dst_sel=0), 4 words, base_addr=10
    // ================================================================
    begin : test1
      integer ok_en, ok_addr, ok_data;
      ok_en   = 1;
      ok_addr = 1;
      ok_data = 1;

      dst_sel  = 2'd0;
      dst_addr = 15'd10;
      length   = 10'd4;
      arm_transfer;

      for (i = 0; i < 4; i = i + 1) begin
        ed       = 32'h00AA0000 | (i << 16);
        ea       = 15'd10 + i[14:0];
        wd       = {BUS_W{1'b0}};
        wd[31:0] = ed;
        dram_data  = wd;
        dram_valid = 1'b1;
        @(posedge clk); #1;
        if (!emb_wr_en)               ok_en   = 0;
        if (emb_wr_addr !== ea)       ok_addr = 0;
        if (emb_wr_data[31:0] !== ed) ok_data = 0;
      end
      dram_valid = 1'b0;
      @(posedge clk); #1;

      chk(ok_en,        "Test1 emb_wr_en");
      chk(ok_addr,      "Test1 emb_wr_addr 10->13");
      chk(ok_data,      "Test1 emb_wr_data");
      chk(done,         "Test1 done");
    end

    repeat (2) @(posedge clk); #1;

    // ================================================================
    // Test 2 — lm_head transfer (dst_sel=1), 3 words, base_addr=0
    // ================================================================
    begin : test2
      integer ok_en, ok_col;
      ok_en  = 1;
      ok_col = 1;

      dst_sel  = 2'd1;
      dst_addr = 15'd0;
      length   = 10'd3;
      arm_transfer;

      for (i = 0; i < 3; i = i + 1) begin
        ed       = 32'h00BB0000 | (i << 16);
        ea       = 15'd0 + i[14:0];
        wd       = {BUS_W{1'b0}};
        wd[31:0] = ed;
        dram_data  = wd;
        dram_valid = 1'b1;
        @(posedge clk); #1;
        if (!lm_wr_en)          ok_en  = 0;
        if (lm_wr_col !== ea)   ok_col = 0;
      end
      dram_valid = 1'b0;
      @(posedge clk); #1;

      chk(ok_en,  "Test2 lm_wr_en");
      chk(ok_col, "Test2 lm_wr_col");
      chk(done,   "Test2 done");
    end

    repeat (2) @(posedge clk); #1;

    // ================================================================
    // Test 3 — gamma transfer (dst_sel=3), 4 words, base_addr=0
    // ================================================================
    begin : test3
      integer ok_en, ok_d0;
      ok_en = 1;
      ok_d0 = 1;

      dst_sel  = 2'd3;
      dst_addr = 15'd0;
      length   = 10'd4;
      arm_transfer;

      for (i = 0; i < 4; i = i + 1) begin
        ed       = 32'h01000100 | (i << 16);
        wd       = {BUS_W{1'b0}};
        wd[31:0] = ed;
        dram_data  = wd;
        dram_valid = 1'b1;
        @(posedge clk); #1;
        if (!gam_wr_en)                              ok_en = 0;
        if (i == 0 && gam_wr_data !== 32'h01000100) ok_d0 = 0;
      end
      dram_valid = 1'b0;
      @(posedge clk); #1;

      chk(ok_en, "Test3 gam_wr_en");
      chk(ok_d0, "Test3 gam_wr_data word0");
      chk(done,  "Test3 done");
    end

    repeat (2) @(posedge clk); #1;

    // ================================================================
    // Test 4 — back-to-back transfers, both dst_sel=0
    // ================================================================
    begin : test4
      integer done1, done2, ok_a1, ok_a2;
      done1 = 0;
      done2 = 0;
      ok_a1 = 1;
      ok_a2 = 1;

      // Transfer A: base=0, length=3
      dst_sel  = 2'd0;
      dst_addr = 15'd0;
      length   = 10'd3;
      arm_transfer;

      for (i = 0; i < 3; i = i + 1) begin
        wd       = {BUS_W{1'b0}};
        wd[31:0] = 32'hCCCC0000 | (i << 16);
        dram_data  = wd;
        dram_valid = 1'b1;
        @(posedge clk); #1;
        if (emb_wr_addr !== i[14:0]) ok_a1 = 0;
      end
      dram_valid = 1'b0;
      @(posedge clk); #1;
      if (done) done1 = 1;

      // Transfer B: base=20, length=2 (start immediately)
      dst_sel  = 2'd0;
      dst_addr = 15'd20;
      length   = 10'd2;
      arm_transfer;

      for (i = 0; i < 2; i = i + 1) begin
        wd       = {BUS_W{1'b0}};
        wd[31:0] = 32'hDDDD0000 | (i << 16);
        dram_data  = wd;
        dram_valid = 1'b1;
        @(posedge clk); #1;
        if (emb_wr_addr !== (15'd20 + i[14:0])) ok_a2 = 0;
      end
      dram_valid = 1'b0;
      @(posedge clk); #1;
      if (done) done2 = 1;

      chk(done1, "Test4 done1 seen");
      chk(done2, "Test4 done2 seen");
      chk(ok_a1, "Test4 xfer1 addr 0->2");
      chk(ok_a2, "Test4 xfer2 addr 20->21");
    end

    repeat (2) @(posedge clk); #1;

    if (fail_cnt == 0)
      $display("DMA SIM: PASS");
    else
      $display("DMA SIM: FAIL (%0d checks, %0d failed)", pass_cnt + fail_cnt, fail_cnt);

    $finish;
  end

endmodule
