`timescale 1ns/1ps
// e2e_tb.sv -- End-to-end: DMA-load embedding + lm_head, fire infer_start,
//              verify samp_valid asserts and samp_token is non-zero.

module e2e_tb;

    localparam HEAD_DIM  = 64;
    localparam DW        = 16;
    localparam VOCAB_SZ  = 32000;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    // AXI4-Lite
    logic        s_axil_awvalid = 0, s_axil_awready;
    logic [11:0] s_axil_awaddr  = 0;
    logic        s_axil_wvalid  = 0, s_axil_wready;
    logic [31:0] s_axil_wdata   = 0;
    logic  [3:0] s_axil_wstrb   = 4'hF;
    logic        s_axil_bvalid,  s_axil_bready = 1;
    logic  [1:0] s_axil_bresp;
    logic        s_axil_arvalid = 0, s_axil_arready;
    logic [11:0] s_axil_araddr  = 0;
    logic        s_axil_rvalid,  s_axil_rready = 1;
    logic [31:0] s_axil_rdata;
    logic  [1:0] s_axil_rresp;

    // Q / KV streams (unused in this test, tied off)
    logic [15:0] s_axis_q_tdata  = 0;
    logic  [5:0] s_axis_q_taddr  = 0;
    logic  [2:0] s_axis_q_tbatch = 0;
    logic        s_axis_q_tvalid = 0, s_axis_q_tready;
    logic [15:0] s_axis_kv_k_tdata = 0, s_axis_kv_v_tdata = 0;
    logic [15:0] s_axis_kv_token_idx = 0;
    logic        s_axis_kv_tvalid = 0, s_axis_kv_tready;

    // Token output stream
    logic [15:0] m_axis_token_tdata;
    logic        m_axis_token_tvalid, m_axis_token_tready = 1;

    // Interrupt / debug
    logic        intr;
    logic        dbg_rd_busy_seen;

    // DMA interface
    logic        dma_start    = 0;
    logic [31:0] dma_src_addr = 0;
    logic  [1:0] dma_dst_sel  = 0;
    logic [14:0] dma_dst_addr = 0;
    logic  [9:0] dma_length   = 0;
    logic        dram_valid   = 0;
    logic [DW*HEAD_DIM-1:0] dram_data = 0;
    logic        dram_ready, dma_done;

    // Sampling output
    logic  [2:0] temp_shift   = 3'd0;
    logic [15:0] p_threshold  = 16'hFFFF;
    logic        samp_valid;
    logic [14:0] samp_token;

    circle_x1 dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axil_awvalid      (s_axil_awvalid),
        .s_axil_awready      (s_axil_awready),
        .s_axil_awaddr       (s_axil_awaddr),
        .s_axil_wvalid       (s_axil_wvalid),
        .s_axil_wready       (s_axil_wready),
        .s_axil_wdata        (s_axil_wdata),
        .s_axil_wstrb        (s_axil_wstrb),
        .s_axil_bvalid       (s_axil_bvalid),
        .s_axil_bready       (s_axil_bready),
        .s_axil_bresp        (s_axil_bresp),
        .s_axil_arvalid      (s_axil_arvalid),
        .s_axil_arready      (s_axil_arready),
        .s_axil_araddr       (s_axil_araddr),
        .s_axil_rvalid       (s_axil_rvalid),
        .s_axil_rready       (s_axil_rready),
        .s_axil_rdata        (s_axil_rdata),
        .s_axil_rresp        (s_axil_rresp),
        .s_axis_q_tdata      (s_axis_q_tdata),
        .s_axis_q_taddr      (s_axis_q_taddr),
        .s_axis_q_tbatch     (s_axis_q_tbatch),
        .s_axis_q_tvalid     (s_axis_q_tvalid),
        .s_axis_q_tready     (s_axis_q_tready),
        .s_axis_kv_k_tdata   (s_axis_kv_k_tdata),
        .s_axis_kv_v_tdata   (s_axis_kv_v_tdata),
        .s_axis_kv_token_idx (s_axis_kv_token_idx),
        .s_axis_kv_tvalid    (s_axis_kv_tvalid),
        .s_axis_kv_tready    (s_axis_kv_tready),
        .m_axis_token_tdata  (m_axis_token_tdata),
        .m_axis_token_tvalid (m_axis_token_tvalid),
        .m_axis_token_tready (m_axis_token_tready),
        .intr                (intr),
        .dbg_rd_busy_seen    (dbg_rd_busy_seen),
        .dma_start           (dma_start),
        .dma_src_addr        (dma_src_addr),
        .dma_dst_sel         (dma_dst_sel),
        .dma_dst_addr        (dma_dst_addr),
        .dma_length          (dma_length),
        .dram_valid          (dram_valid),
        .dram_data           (dram_data),
        .dram_ready          (dram_ready),
        .dma_done            (dma_done),
        .temp_shift          (temp_shift),
        .p_threshold         (p_threshold),
        .samp_valid          (samp_valid),
        .samp_token          (samp_token)
    );

    // AXI4-Lite write helper
    task automatic axil_write;
        input [11:0] addr;
        input [31:0] data;
        integer g;
        begin
            @(posedge clk); #1;
            s_axil_awaddr  = addr;
            s_axil_wdata   = data;
            s_axil_awvalid = 1;
            s_axil_wvalid  = 1;
            g = 0;
            while ((s_axil_awvalid || s_axil_wvalid) && g < 128) begin
                @(posedge clk); #1;
                if (s_axil_awready) s_axil_awvalid = 0;
                if (s_axil_wready)  s_axil_wvalid  = 0;
                g = g + 1;
            end
            g = 0;
            while (!s_axil_bvalid && g < 128) begin
                @(posedge clk); #1; g = g + 1;
            end
            @(posedge clk); #1;
        end
    endtask

    // DMA single-word load: write one 1024-bit word to dst (dst_sel, dst_addr).
    // dma_engine issues dram_ready after start; we present dram_data one beat.
    task automatic dma_load_word;
        input [1:0]              sel;
        input [14:0]             addr;
        input [DW*HEAD_DIM-1:0]  data;
        integer g;
        begin
            @(posedge clk); #1;
            dma_dst_sel  = sel;
            dma_dst_addr = addr;
            dma_length   = 10'd1;
            dma_src_addr = 32'd0;
            dma_start    = 1;
            @(posedge clk); #1;
            dma_start = 0;
            // wait for dram_ready
            g = 0;
            while (!dram_ready && g < 64) begin
                @(posedge clk); #1; g = g + 1;
            end
            // present one beat
            dram_data  = data;
            dram_valid = 1;
            @(posedge clk); #1;
            dram_valid = 0;
            dram_data  = 0;
            // wait for dma_done
            g = 0;
            while (!dma_done && g < 64) begin
                @(posedge clk); #1; g = g + 1;
            end
            @(posedge clk); #1;
        end
    endtask

    integer fail_count;

    initial begin : stim
        integer wait_cnt;
        fail_count = 0;

        // Release reset
        repeat (20) @(posedge clk); #1;
        rst_n = 1;
        repeat (10) @(posedge clk); #1;

        // Load embedding[0] with all-1.0 (Q8.8 0x0100) -- 64 words
        dma_load_word(2'd0, 15'd0, {HEAD_DIM{16'h0100}});

        // Load lm_head column 63 with all-1.0 -- j=63 is last NBA write, survives in slot 0
        dma_load_word(2'd1, 15'd63, {HEAD_DIM{16'h0100}});

        repeat (10) @(posedge clk);

        // Configure: spec_k=0 (no speculative decode), enable=1
        axil_write(12'h010, 32'd0);       // session_id = 0
        axil_write(12'h018, 32'd0);       // spec_k = 0
        axil_write(12'h00C, 32'd1);       // enable

        // Fire infer_start: triggers embedding lookup (Priority B) ->
        // emb_valid_out -> layer_ctrl.start
        axil_write(12'h000, 32'd1);

        // Wait for samp_valid
        wait_cnt = 0;
        while (!samp_valid && wait_cnt < 800000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end

        if (!samp_valid) begin
            $error("E2E: samp_valid did not assert within 800000 cycles");
            fail_count = fail_count + 1;
        end

        if (samp_token == 15'd0) begin
            $error("E2E: samp_token is zero -- expected non-zero");
            fail_count = fail_count + 1;
        end

        $display("E2E TOKEN: %0d (0x%04h)", samp_token, samp_token);
        if (fail_count == 0)
            $display("CIRCLE X1 E2E: PASS");
        else
            $display("CIRCLE X1 E2E: FAIL");

        $finish;
    end

    initial begin : safety_timeout
        #10000000;
        $error("E2E: simulation timeout at 10ms");
        $display("CIRCLE X1 E2E: FAIL");
        $finish;
    end

endmodule
