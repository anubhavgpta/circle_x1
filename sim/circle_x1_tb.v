// circle_x1_tb.v -- Testbench for circle_x1 new RTL modules
// Five named checks. Each prints CHECK PASS: <name> or CHECK FAIL: <name>.
`timescale 1ns/1ps

module circle_x1_tb;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // ----------------------------------------------------------------
    // AXI4-Lite slave signals (connected to x1_reg_ctrl)
    // ----------------------------------------------------------------
    reg         s_axil_awvalid;
    wire        s_axil_awready;
    reg  [11:0] s_axil_awaddr;
    reg         s_axil_wvalid;
    wire        s_axil_wready;
    reg  [31:0] s_axil_wdata;
    reg  [3:0]  s_axil_wstrb;
    wire        s_axil_bvalid;
    reg         s_axil_bready;
    wire [1:0]  s_axil_bresp;
    reg         s_axil_arvalid;
    wire        s_axil_arready;
    reg  [11:0] s_axil_araddr;
    wire        s_axil_rvalid;
    reg         s_axil_rready;
    wire [31:0] s_axil_rdata;
    wire [1:0]  s_axil_rresp;

    // ----------------------------------------------------------------
    // Vera proxy AXI4-Lite stub wires
    // ----------------------------------------------------------------
    wire        vera_awvalid, vera_wvalid, vera_bready, vera_arvalid, vera_rready;
    wire [31:0] vera_awaddr, vera_wdata, vera_araddr;
    wire [3:0]  vera_wstrb;
    reg         vera_awready, vera_wready, vera_bvalid, vera_arready, vera_rvalid;
    reg  [1:0]  vera_bresp, vera_rresp;
    reg  [31:0] vera_rdata;

    // ----------------------------------------------------------------
    // AIS stub signals
    // ----------------------------------------------------------------
    reg         stub_infer_busy;
    reg         stub_infer_done;
    reg  [2:0]  stub_ais_state;
    reg  [15:0] stub_generated_token;
    reg         stub_token_valid;

    // Auto-latch infer_busy when infer_start pulses
    wire        infer_start_w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stub_infer_busy <= 1'b0;
        else if (infer_start_w) stub_infer_busy <= 1'b1;
    end

    // ----------------------------------------------------------------
    // x1_reg_ctrl DUT
    // ----------------------------------------------------------------
    wire        intr;
    wire [2:0]  reg_session_id;
    wire [11:0] reg_prompt_len;
    wire [2:0]  reg_spec_k;
    wire [11:0] reg_max_new_tokens;
    wire [15:0] reg_target_id;
    wire [15:0] reg_draft_0, reg_draft_1, reg_draft_2, reg_draft_3;
    wire [15:0] reg_draft_4, reg_draft_5, reg_draft_6;

    x1_reg_ctrl #(.AXI_ADDR_WIDTH(12), .AXI_DATA_WIDTH(32)) u_reg_ctrl (
        .clk(clk), .rst_n(rst_n),
        // Slave
        .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_awaddr (s_axil_awaddr),
        .s_axil_wvalid (s_axil_wvalid),  .s_axil_wready(s_axil_wready),
        .s_axil_wdata  (s_axil_wdata),   .s_axil_wstrb(s_axil_wstrb),
        .s_axil_bvalid (s_axil_bvalid),  .s_axil_bready(s_axil_bready),
        .s_axil_bresp  (s_axil_bresp),
        .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_rvalid (s_axil_rvalid),  .s_axil_rready(s_axil_rready),
        .s_axil_rdata  (s_axil_rdata),   .s_axil_rresp(s_axil_rresp),
        // Vera proxy master
        .m_axil_vera_awvalid(vera_awvalid), .m_axil_vera_awready(vera_awready),
        .m_axil_vera_awaddr (vera_awaddr),
        .m_axil_vera_wvalid (vera_wvalid),  .m_axil_vera_wready(vera_wready),
        .m_axil_vera_wdata  (vera_wdata),   .m_axil_vera_wstrb(vera_wstrb),
        .m_axil_vera_bvalid (vera_bvalid),  .m_axil_vera_bready(vera_bready),
        .m_axil_vera_bresp  (vera_bresp),
        .m_axil_vera_arvalid(vera_arvalid), .m_axil_vera_arready(vera_arready),
        .m_axil_vera_araddr (vera_araddr),
        .m_axil_vera_rvalid (vera_rvalid),  .m_axil_vera_rready(vera_rready),
        .m_axil_vera_rdata  (vera_rdata),   .m_axil_vera_rresp(vera_rresp),
        // AIS outputs
        .infer_start   (infer_start_w),
        .session_id    (reg_session_id),
        .prompt_len    (reg_prompt_len),
        .spec_k        (reg_spec_k),
        .max_new_tokens(reg_max_new_tokens),
        .target_token_id(reg_target_id),
        .draft_token_id_0(reg_draft_0), .draft_token_id_1(reg_draft_1),
        .draft_token_id_2(reg_draft_2), .draft_token_id_3(reg_draft_3),
        .draft_token_id_4(reg_draft_4), .draft_token_id_5(reg_draft_5),
        .draft_token_id_6(reg_draft_6),
        // AIS inputs
        .infer_busy    (stub_infer_busy),
        .infer_done    (stub_infer_done),
        .ais_state     (stub_ais_state),
        .generated_token(stub_generated_token),
        .token_valid   (stub_token_valid),
        .intr          (intr)
    );

    // Vera AXI4-Lite stub: always-ready, immediate response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vera_awready <= 1'b0;
            vera_wready  <= 1'b0;
            vera_bvalid  <= 1'b0;
            vera_arready <= 1'b0;
            vera_rvalid  <= 1'b0;
            vera_bresp   <= 2'b00;
            vera_rresp   <= 2'b00;
            vera_rdata   <= 32'hDEAD_BEEF;
        end else begin
            vera_awready <= vera_awvalid;
            vera_wready  <= vera_wvalid;
            vera_bvalid  <= vera_wvalid & vera_wready;
            vera_arready <= vera_arvalid;
            vera_rvalid  <= vera_arvalid & vera_arready;
        end
    end

    // ----------------------------------------------------------------
    // x1_q_stream_adapter DUT
    // ----------------------------------------------------------------
    reg  [15:0] q_tdata;
    reg  [5:0]  q_taddr;
    reg  [2:0]  q_tbatch;
    reg         q_tvalid;
    wire        q_tready;
    wire [15:0] draft_q_data;
    wire [5:0]  draft_q_addr;
    wire [2:0]  draft_q_batch_id;
    wire        draft_q_valid;

    x1_q_stream_adapter u_q_adapter (
        .clk(clk), .rst_n(rst_n),
        .s_axis_q_tdata  (q_tdata),  .s_axis_q_taddr  (q_taddr),
        .s_axis_q_tbatch (q_tbatch), .s_axis_q_tvalid (q_tvalid),
        .s_axis_q_tready (q_tready),
        .draft_q_data    (draft_q_data),
        .draft_q_addr    (draft_q_addr),
        .draft_q_batch_id(draft_q_batch_id),
        .draft_q_valid   (draft_q_valid)
    );

    // ----------------------------------------------------------------
    // x1_kv_stream_adapter DUT
    // ----------------------------------------------------------------
    reg  [15:0] kv_k_tdata, kv_v_tdata, kv_token_idx;
    reg         kv_tvalid;
    wire        kv_tready;
    wire [15:0] commit_k_data, commit_v_data;
    wire [2:0]  commit_token_idx;
    wire        commit_kv_valid;

    x1_kv_stream_adapter u_kv_adapter (
        .clk(clk), .rst_n(rst_n),
        .s_axis_kv_k_tdata  (kv_k_tdata),
        .s_axis_kv_v_tdata  (kv_v_tdata),
        .s_axis_kv_token_idx(kv_token_idx),
        .s_axis_kv_tvalid   (kv_tvalid),
        .s_axis_kv_tready   (kv_tready),
        .commit_k_data      (commit_k_data),
        .commit_v_data      (commit_v_data),
        .commit_token_idx   (commit_token_idx),
        .commit_kv_valid    (commit_kv_valid)
    );

    // ----------------------------------------------------------------
    // x1_token_output DUT
    // ----------------------------------------------------------------
    reg         tok_tready;
    wire [15:0] tok_tdata;
    wire        tok_tvalid;
    wire        tok_overflow;

    x1_token_output u_tok_out (
        .clk(clk), .rst_n(rst_n),
        .generated_token    (stub_generated_token),
        .token_valid        (stub_token_valid),
        .m_axis_token_tdata (tok_tdata),
        .m_axis_token_tvalid(tok_tvalid),
        .m_axis_token_tready(tok_tready),
        .tok_overflow       (tok_overflow)
    );

    // ----------------------------------------------------------------
    // AXI4-Lite tasks
    // ----------------------------------------------------------------
    integer check_pass_count;

    task axi_write;
        input [11:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            s_axil_awvalid = 1'b1; s_axil_awaddr = addr;
            // Wait for AW handshake
            @(posedge clk);
            while (!s_axil_awready) @(posedge clk);
            @(negedge clk);
            s_axil_awvalid = 1'b0;
            s_axil_wvalid  = 1'b1; s_axil_wdata = data; s_axil_wstrb = 4'hF;
            // Wait for W handshake
            @(posedge clk);
            while (!s_axil_wready) @(posedge clk);
            @(negedge clk);
            s_axil_wvalid = 1'b0; s_axil_bready = 1'b1;
            // Wait for B response
            @(posedge clk);
            while (!s_axil_bvalid) @(posedge clk);
            @(negedge clk);
            s_axil_bready = 1'b0;
        end
    endtask

    task axi_read;
        input  [11:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            s_axil_arvalid = 1'b1; s_axil_araddr = addr;
            @(posedge clk);
            while (!s_axil_arready) @(posedge clk);
            @(negedge clk);
            s_axil_arvalid = 1'b0; s_axil_rready = 1'b1;
            @(posedge clk);
            while (!s_axil_rvalid) @(posedge clk);
            data = s_axil_rdata;
            @(negedge clk);
            s_axil_rready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test
    // ----------------------------------------------------------------
    integer i;
    reg [31:0] rdata;
    integer c_pass;
    reg check_ok;

    initial begin
        // Init signals
        clk = 0; rst_n = 0;
        s_axil_awvalid = 0; s_axil_awaddr = 0;
        s_axil_wvalid  = 0; s_axil_wdata  = 0; s_axil_wstrb = 4'hF;
        s_axil_bready  = 0;
        s_axil_arvalid = 0; s_axil_araddr = 0;
        s_axil_rready  = 0;
        q_tdata = 0; q_taddr = 0; q_tbatch = 0; q_tvalid = 0;
        kv_k_tdata = 0; kv_v_tdata = 0; kv_token_idx = 0; kv_tvalid = 0;
        tok_tready = 0;
        stub_infer_done = 0; stub_ais_state = 0;
        stub_generated_token = 0; stub_token_valid = 0;

        // Release reset after 4 cycles
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(2) @(posedge clk);

        check_pass_count = 0;

        // ============================================================
        // C1_reg_rw: Write all R/W registers, read back, verify
        // ============================================================
        $display("--- C1_reg_rw ---");
        axi_write(12'h010, 32'h7);         // SESSION_ID = 7
        axi_write(12'h014, 32'hFFF);       // PROMPT_LEN = 4095
        axi_write(12'h018, 32'h5);         // SPEC_K = 5
        axi_write(12'h01C, 32'hABC);       // MAX_NEW_TOKENS = 0xABC
        axi_write(12'h028, 32'hABCD);      // TARGET_TOKEN_ID = 0xABCD
        axi_write(12'h02C, 32'h0001);      // DRAFT_TOKEN_0
        axi_write(12'h030, 32'h0002);      // DRAFT_TOKEN_1
        axi_write(12'h034, 32'h0003);
        axi_write(12'h038, 32'h0004);
        axi_write(12'h03C, 32'h0005);
        axi_write(12'h040, 32'h0006);
        axi_write(12'h044, 32'h0007);      // DRAFT_TOKEN_6
        axi_write(12'h00C, 32'h1);         // INTR_ENABLE = 1

        check_ok = 1;
        axi_read(12'h010, rdata); if (rdata[2:0] !== 3'd7)   check_ok = 0;
        axi_read(12'h014, rdata); if (rdata[11:0] !== 12'hFFF) check_ok = 0;
        axi_read(12'h018, rdata); if (rdata[2:0] !== 3'd5)   check_ok = 0;
        axi_read(12'h01C, rdata); if (rdata[11:0] !== 12'hABC) check_ok = 0;
        axi_read(12'h028, rdata); if (rdata[15:0] !== 16'hABCD) check_ok = 0;
        axi_read(12'h02C, rdata); if (rdata[15:0] !== 16'h0001) check_ok = 0;
        axi_read(12'h030, rdata); if (rdata[15:0] !== 16'h0002) check_ok = 0;
        axi_read(12'h034, rdata); if (rdata[15:0] !== 16'h0003) check_ok = 0;
        axi_read(12'h038, rdata); if (rdata[15:0] !== 16'h0004) check_ok = 0;
        axi_read(12'h03C, rdata); if (rdata[15:0] !== 16'h0005) check_ok = 0;
        axi_read(12'h040, rdata); if (rdata[15:0] !== 16'h0006) check_ok = 0;
        axi_read(12'h044, rdata); if (rdata[15:0] !== 16'h0007) check_ok = 0;
        axi_read(12'h00C, rdata); if (rdata[0] !== 1'b1)    check_ok = 0;
        // Verify BRESP and RRESP == 0 throughout (checked implicitly -- no error resp)
        if (s_axil_bresp !== 2'b00) check_ok = 0;
        if (s_axil_rresp !== 2'b00) check_ok = 0;

        if (check_ok) begin
            $display("CHECK PASS: C1_reg_rw");
            check_pass_count = check_pass_count + 1;
        end else begin
            $display("CHECK FAIL: C1_reg_rw");
        end

        repeat(2) @(posedge clk);

        // ============================================================
        // C2_infer_launch: Write params, write CTRL, verify STATUS[0]
        // ============================================================
        $display("--- C2_infer_launch ---");
        // Reset infer_busy stub
        @(negedge clk); stub_infer_busy = 0;
        axi_write(12'h010, 32'h1);   // SESSION_ID=1
        axi_write(12'h014, 32'h8);   // PROMPT_LEN=8
        axi_write(12'h018, 32'h3);   // SPEC_K=3
        axi_write(12'h01C, 32'h10);  // MAX_NEW_TOKENS=16
        // Write CTRL[0]=1 (infer_start pulse)
        axi_write(12'h000, 32'h1);
        // Stub latches infer_busy during the write. Now read STATUS within 4 cycles.
        check_ok = 0;
        for (i = 0; i < 4; i = i + 1) begin
            axi_read(12'h004, rdata);
            if (rdata[0]) begin check_ok = 1; i = 4; end // STATUS[0]=infer_busy
        end

        if (check_ok) begin
            $display("CHECK PASS: C2_infer_launch");
            check_pass_count = check_pass_count + 1;
        end else begin
            $display("CHECK FAIL: C2_infer_launch");
        end

        repeat(2) @(posedge clk);

        // ============================================================
        // C3_q_stream: Stream 64 words, verify draft_q_valid + data/addr
        // ============================================================
        $display("--- C3_q_stream ---");
        check_ok = 1;
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            q_tdata  = i[15:0] + 16'hA000;
            q_taddr  = i[5:0];
            q_tbatch = 3'd0;
            q_tvalid = 1'b1;
            @(posedge clk);
            // After posedge, q_tvalid=1 and q_tready=1 -> handshake
            // Next posedge will have draft_q_valid=1 with latched data
            @(negedge clk);
            q_tvalid = 1'b0;
            @(posedge clk);
            // Now check draft_q_valid and data
            if (!draft_q_valid)             check_ok = 0;
            if (draft_q_data  !== (i[15:0] + 16'hA000)) check_ok = 0;
            if (draft_q_addr  !== i[5:0])  check_ok = 0;
            if (draft_q_batch_id !== 3'd0) check_ok = 0;
        end

        if (check_ok) begin
            $display("CHECK PASS: C3_q_stream");
            check_pass_count = check_pass_count + 1;
        end else begin
            $display("CHECK FAIL: C3_q_stream");
        end

        // ============================================================
        // C4_kv_stream: Stream 4 KV pairs, verify commit_kv_valid
        // ============================================================
        $display("--- C4_kv_stream ---");
        check_ok = 1;
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            kv_k_tdata    = 16'h1000 + i;
            kv_v_tdata    = 16'h2000 + i;
            kv_token_idx  = i;
            kv_tvalid     = 1'b1;
            @(posedge clk);
            @(negedge clk);
            kv_tvalid = 1'b0;
            @(posedge clk);
            if (!commit_kv_valid)                    check_ok = 0;
            if (commit_k_data   !== (16'h1000 + i))  check_ok = 0;
            if (commit_v_data   !== (16'h2000 + i))  check_ok = 0;
            if (commit_token_idx !== i[2:0])          check_ok = 0;
        end

        if (check_ok) begin
            $display("CHECK PASS: C4_kv_stream");
            check_pass_count = check_pass_count + 1;
        end else begin
            $display("CHECK FAIL: C4_kv_stream");
        end

        // ============================================================
        // C5_token_out_and_intr
        // ============================================================
        $display("--- C5_token_out_and_intr ---");
        // Write INTR_ENABLE[0]=1 (already done in C1, but set again)
        axi_write(12'h00C, 32'h1);
        // Clear any pending intr
        axi_write(12'h008, 32'h1);
        repeat(3) @(posedge clk);

        // Keep tready=0 so token stays in buffer
        @(negedge clk); tok_tready = 1'b0;

        // Drive token_valid=1, generated_token=0xABCD, infer_done=1 for one cycle
        @(negedge clk);
        stub_generated_token = 16'hABCD;
        stub_token_valid     = 1'b1;
        stub_infer_done      = 1'b1;
        @(posedge clk); // Posedge N: latch token, latch done_intr
        @(negedge clk);
        stub_token_valid = 1'b0;
        stub_infer_done  = 1'b0;

        // Wait for outputs to settle (2 cycles)
        @(posedge clk); // N+1: tok_tvalid=1, tok_tdata=0xABCD, done_intr=1
        @(posedge clk); // N+2: intr=1

        check_ok = 1;
        if (!tok_tvalid)                 check_ok = 0;
        if (tok_tdata !== 16'hABCD)      check_ok = 0;
        if (!intr)                        check_ok = 0;

        // Acknowledge the token
        @(negedge clk); tok_tready = 1'b1;
        @(posedge clk);
        @(negedge clk); tok_tready = 1'b0;

        // Clear interrupt via W1C on INTR_STATUS[0]
        axi_write(12'h008, 32'h1);

        // Verify intr deasserts within 2 cycles after write completes
        @(posedge clk);
        @(posedge clk);

        if (intr) check_ok = 0; // Should be 0

        if (check_ok) begin
            $display("CHECK PASS: C5_token_out_and_intr");
            check_pass_count = check_pass_count + 1;
        end else begin
            $display("CHECK FAIL: C5_token_out_and_intr");
        end

        // ============================================================
        // Final result
        // ============================================================
        repeat(5) @(posedge clk);
        $display("%0d/5 circle_x1 checks passing", check_pass_count);
        $finish;
    end

endmodule
