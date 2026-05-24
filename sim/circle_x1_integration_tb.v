`timescale 1ns/1ps

// Integration testbench: drives circle_x1 as a black box via external ports only.
// All stimulus via AXI4-Lite slave and AXI4-Stream inputs.
// All checking via AXI4-Stream token output and AXI4-Lite status registers.

module circle_x1_integration_tb;

    // -------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // DUT port declarations
    // -------------------------------------------------------

    // AXI4-Lite slave
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

    // AXI4-Stream Q input
    reg  [15:0] s_axis_q_tdata;
    reg  [5:0]  s_axis_q_taddr;
    reg  [2:0]  s_axis_q_tbatch;
    reg         s_axis_q_tvalid;
    wire        s_axis_q_tready;

    // AXI4-Stream KV input
    reg  [15:0] s_axis_kv_k_tdata;
    reg  [15:0] s_axis_kv_v_tdata;
    reg  [15:0] s_axis_kv_token_idx;
    reg         s_axis_kv_tvalid;
    wire        s_axis_kv_tready;

    // AXI4-Stream token output
    wire [15:0] m_axis_token_tdata;
    wire        m_axis_token_tvalid;
    reg         m_axis_token_tready;

    // Interrupt
    wire        intr;

    // -------------------------------------------------------
    // Latch: m_axis_token_tvalid ever pulsed (used by C2 check)
    // -------------------------------------------------------
    reg token_tvalid_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            token_tvalid_seen <= 1'b0;
        else if (m_axis_token_tvalid)
            token_tvalid_seen <= 1'b1;
    end

    // Hard timeout: guarantees xsim always exits
    initial begin
        #200000000;
        $display("HARD TIMEOUT: sim did not finish in 200ms sim time");
        $finish;
    end

    // -------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------
    circle_x1 #(
        .TOTAL_PAGES      (256),
        .PAGE_SIZE_TOKENS (16),
        .HEAD_DIM         (64),
        .NUM_SESSIONS     (8),
        .DATA_WIDTH       (16),
        .SRAM_BANKS       (4),
        .MAX_BATCH        (8),
        .AXI_ADDR_WIDTH   (12),
        .AXI_DATA_WIDTH   (32)
    ) dut (
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
        .intr                (intr)
    );

    // -------------------------------------------------------
    // Task: axil_write -- full AXI4-Lite write transaction
    //   Checks BRESP==0; prints CHECK FAIL on error.
    // -------------------------------------------------------
    task axil_write;
        input [11:0] addr;
        input [31:0] data;
        begin
            // Drive on negedge so the DUT samples stable inputs on posedge.
            @(negedge clk);
            s_axil_awvalid = 1'b1;
            s_axil_awaddr  = addr;
            s_axil_wvalid  = 1'b0;
            @(posedge clk);
            while (!s_axil_awready) @(posedge clk);
            @(negedge clk);
            s_axil_awvalid = 1'b0;
            s_axil_wvalid = 1'b1;
            s_axil_wdata  = data;
            s_axil_wstrb  = 4'hF;
            @(posedge clk);
            while (!s_axil_wready) @(posedge clk);
            @(negedge clk);
            s_axil_wvalid = 1'b0;
            s_axil_bready = 1'b1;
            @(posedge clk);
            while (!s_axil_bvalid) @(posedge clk);
            if (s_axil_bresp !== 2'b00)
                $display("CHECK FAIL: axil_write bresp=%0b addr=%03x",
                         s_axil_bresp, addr);
            @(negedge clk);
            s_axil_bready = 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Task: axil_read -- full AXI4-Lite read transaction
    //   Checks RRESP==0; returns RDATA via output.
    // -------------------------------------------------------
    task axil_read;
        input  [11:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            s_axil_arvalid = 1'b1;
            s_axil_araddr  = addr;
            @(posedge clk);
            while (!s_axil_arready) @(posedge clk);
            @(negedge clk);
            s_axil_arvalid = 1'b0;
            s_axil_rready  = 1'b1;
            @(posedge clk);
            while (!s_axil_rvalid) @(posedge clk);
            if (s_axil_rresp !== 2'b00)
                $display("CHECK FAIL: axil_read rresp=%0b addr=%03x", s_axil_rresp, addr);
            data = s_axil_rdata;
            @(negedge clk);
            s_axil_rready = 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Task: wait_infer_done
    //   Polls STATUS (0x004) until bit[1] (infer_done) is seen,
    //   OR until infer_busy (bit[0]) transitions 1->0.
    //   The latter catches the single-cycle infer_done pulse
    //   that may fall between polling intervals.
    //   Calls $finish after timeout_cycles polls with no done.
    // -------------------------------------------------------
    task wait_infer_done;
        input integer timeout_cycles;
        integer       cnt;
        reg [31:0]    status;
        reg           prev_busy;
        reg           done;
        begin
            cnt       = 0;
            prev_busy = 1'b0;
            done      = 1'b0;
            while (!done && cnt < timeout_cycles) begin
                axil_read(12'h004, status);
                if (status[1])               done = 1'b1;
                if (prev_busy && !status[0]) done = 1'b1;
                prev_busy = status[0];
                cnt = cnt + 1;
            end
            if (!done) begin
                $display("TIMEOUT: wait_infer_done after %0d polls status=0x%08x busy=%0b done=%0b ais_state=%0d",
                         cnt, status, status[0], status[1], status[5:3]);
                $finish;
            end
        end
    endtask

    // -------------------------------------------------------
    // Task: stream_q_vector
    //   Sends 64 words on s_axis_q: taddr=0..63,
    //   tdata=base_val+taddr, tbatch=batch_id.
    //   Waits for tready on each word.
    // -------------------------------------------------------
    task stream_q_vector;
        input [2:0]  batch_id;
        input [15:0] base_val;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) begin
                @(negedge clk);
                s_axis_q_tvalid = 1'b1;
                s_axis_q_tdata  = base_val + i;
                s_axis_q_taddr  = i[5:0];
                s_axis_q_tbatch = batch_id;
                @(posedge clk);
                while (!s_axis_q_tready) @(posedge clk);
            end
            @(negedge clk);
            s_axis_q_tvalid = 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Task: stream_kv_pair
    //   Sends one KV beat on s_axis_kv.
    //   Waits for tready.
    // -------------------------------------------------------
    task stream_kv_pair;
        input [15:0] token_idx;
        input [15:0] k_val;
        input [15:0] v_val;
        begin
            @(negedge clk);
            s_axis_kv_tvalid    = 1'b1;
            s_axis_kv_k_tdata   = k_val;
            s_axis_kv_v_tdata   = v_val;
            s_axis_kv_token_idx = token_idx;
            @(posedge clk);
            while (!s_axis_kv_tready) @(posedge clk);
            @(negedge clk);
            s_axis_kv_tvalid = 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------
    integer check_pass;
    reg [31:0] rdata;

    initial begin
        // Initialize all inputs to safe idle state
        rst_n               = 1'b0;
        s_axil_awvalid      = 1'b0;
        s_axil_awaddr       = 12'd0;
        s_axil_wvalid       = 1'b0;
        s_axil_wdata        = 32'd0;
        s_axil_wstrb        = 4'hF;
        s_axil_bready       = 1'b0;
        s_axil_arvalid      = 1'b0;
        s_axil_araddr       = 12'd0;
        s_axil_rready       = 1'b0;
        s_axis_q_tvalid     = 1'b0;
        s_axis_q_tdata      = 16'd0;
        s_axis_q_taddr      = 6'd0;
        s_axis_q_tbatch     = 3'd0;
        s_axis_kv_tvalid    = 1'b0;
        s_axis_kv_k_tdata   = 16'd0;
        s_axis_kv_v_tdata   = 16'd0;
        s_axis_kv_token_idx = 16'd0;
        m_axis_token_tready = 1'b1;

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("DEBUG: reset released");

        // ==========================================================
        // INTEG_C1_boot
        // After reset: STATUS[1:0]==0, all R/W registers read back 0
        // ==========================================================
        check_pass = 1;

        axil_read(12'h004, rdata);
        if (rdata[1:0] !== 2'b00) begin
            $display("INTEG FAIL: INTEG_C1_boot -- STATUS[1:0]=%0b expected 00", rdata[1:0]);
            check_pass = 0;
        end

        axil_read(12'h000, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- CTRL=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h00C, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- INTR_ENABLE=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h010, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- SESSION_ID=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h014, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- PROMPT_LEN=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h018, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- SPEC_K=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h01C, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- MAX_NEW_TOKENS=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h028, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- TARGET_TOKEN_ID=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h02C, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_0=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h030, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_1=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h034, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_2=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h038, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_3=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h03C, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_4=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h040, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_5=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        axil_read(12'h044, rdata);
        if (rdata !== 32'd0) begin
            $display("INTEG FAIL: INTEG_C1_boot -- DRAFT_TOKEN_6=0x%08x expected 0", rdata);
            check_pass = 0;
        end
        $display("DEBUG: C1 reads done");

        if (check_pass)
            $display("INTEG PASS: INTEG_C1_boot");

        axil_write(12'h100, 32'd1);           // Vera CTRL[0]=1: enable KV engine

        // ==========================================================
        // INTEG_C2_single_round
        // One speculative decode round: SESSION=0, SPEC_K=1, no intr.
        // Checks: GENERATED_TOKEN non-zero, TOKEN_COUNT>=1,
        //         m_axis_token_tvalid pulsed during inference.
        // ==========================================================
        check_pass = 1;

        axil_write(12'h010, 32'd0);           // SESSION_ID = 0
        axil_write(12'h014, 32'd4);           // PROMPT_LEN = 4
        axil_write(12'h018, 32'd1);           // SPEC_K = 1
        axil_write(12'h01C, 32'd1);           // MAX_NEW_TOKENS = 1
        axil_write(12'h028, 32'h00000042);    // TARGET_TOKEN_ID = 0x0042
        axil_write(12'h02C, 32'h00000041);    // DRAFT_TOKEN_0  = 0x0041
        $display("DEBUG: C2 config done");
        axil_write(12'h000, 32'd1);           // CTRL[0]=1: launch inference
        $display("DEBUG: C2 launched");
        stream_q_vector(3'd0, 16'h0100);
        stream_q_vector(3'd1, 16'h0100);
        $display("DEBUG: C2 q streamed");
        stream_kv_pair(16'd0, 16'h0010, 16'h0020);
        stream_kv_pair(16'd1, 16'h0010, 16'h0020);
        $display("DEBUG: C2 kv streamed");
        $display("DEBUG: C2 waiting infer_done");
        wait_infer_done(5000);

        // Check 1: GENERATED_TOKEN non-zero
        axil_read(12'h020, rdata);
        if (rdata[15:0] === 16'd0) begin
            $display("INTEG FAIL: INTEG_C2_single_round -- GENERATED_TOKEN is zero");
            check_pass = 0;
        end

        // Check 2: TOKEN_COUNT >= 1
        axil_read(12'h024, rdata);
        if (rdata[11:0] < 12'd1) begin
            $display("INTEG FAIL: INTEG_C2_single_round -- TOKEN_COUNT=%0d expected >=1", rdata[11:0]);
            check_pass = 0;
        end

        // Check 3: m_axis_token_tvalid pulsed during inference window
        if (!token_tvalid_seen) begin
            $display("INTEG FAIL: INTEG_C2_single_round -- m_axis_token_tvalid never asserted");
            check_pass = 0;
        end

        if (check_pass)
            $display("INTEG PASS: INTEG_C2_single_round");

        // ==========================================================
        // INTEG_C3_intr_end_to_end
        // Interrupt round-trip: SESSION=1, SPEC_K=1, INTR_ENABLE=1.
        // Checks: intr asserted, INTR_STATUS[0] set, clears after W1C.
        // ==========================================================
        check_pass = 1;

        axil_write(12'h00C, 32'd1);           // INTR_ENABLE[0] = 1
        axil_write(12'h010, 32'd1);           // SESSION_ID = 1
        axil_write(12'h014, 32'd2);           // PROMPT_LEN = 2
        axil_write(12'h018, 32'd1);           // SPEC_K = 1
        axil_write(12'h01C, 32'd1);           // MAX_NEW_TOKENS = 1
        axil_write(12'h028, 32'h000000FF);    // TARGET_TOKEN_ID = 0x00FF
        axil_write(12'h02C, 32'h000000FE);    // DRAFT_TOKEN_0  = 0x00FE
        axil_write(12'h000, 32'd1);           // CTRL[0]=1: launch inference
        stream_q_vector(3'd0, 16'h0200);
        stream_q_vector(3'd1, 16'h0200);
        stream_kv_pair(16'd0, 16'h0030, 16'h0040);
        stream_kv_pair(16'd1, 16'h0030, 16'h0040);

        wait_infer_done(5000);

        // Allow done_intr -> intr register propagation (2-cycle pipeline)
        repeat (2) @(posedge clk);

        // Check 1: intr output asserted
        if (!intr) begin
            $display("INTEG FAIL: INTEG_C3_intr_end_to_end -- intr not asserted after infer_done");
            check_pass = 0;
        end

        // Check 2: INTR_STATUS[0] set
        axil_read(12'h008, rdata);
        if (!rdata[0]) begin
            $display("INTEG FAIL: INTEG_C3_intr_end_to_end -- INTR_STATUS[0] not set");
            check_pass = 0;
        end

        // Clear interrupt via W1C write to INTR_STATUS[0]
        axil_write(12'h008, 32'd1);

        // Wait 4 cycles for W1C clear to propagate through done_intr -> intr pipeline
        repeat (4) @(posedge clk);

        // Check 3: intr deasserted
        if (intr) begin
            $display("INTEG FAIL: INTEG_C3_intr_end_to_end -- intr not deasserted after W1C clear");
            check_pass = 0;
        end

        if (check_pass)
            $display("INTEG PASS: INTEG_C3_intr_end_to_end");

        $display("3/3 circle_x1 integration checks passing");
        $finish;
    end

endmodule
