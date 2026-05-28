`timescale 1ns/1ps

module circle_x1_tb;

    localparam HEAD_DIM = 64;

    logic clk = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk;

    logic        s_axil_awvalid = 1'b0;
    logic        s_axil_awready;
    logic [11:0] s_axil_awaddr  = 12'h000;
    logic        s_axil_wvalid  = 1'b0;
    logic        s_axil_wready;
    logic [31:0] s_axil_wdata   = 32'h0000_0000;
    logic  [3:0] s_axil_wstrb   = 4'hF;
    logic        s_axil_bvalid;
    logic        s_axil_bready  = 1'b1;
    logic  [1:0] s_axil_bresp;
    logic        s_axil_arvalid = 1'b0;
    logic        s_axil_arready;
    logic [11:0] s_axil_araddr  = 12'h000;
    logic        s_axil_rvalid;
    logic        s_axil_rready  = 1'b1;
    logic [31:0] s_axil_rdata;
    logic  [1:0] s_axil_rresp;

    logic [15:0] s_axis_q_tdata  = 16'h0000;
    logic  [5:0] s_axis_q_taddr  = 6'd0;
    logic  [2:0] s_axis_q_tbatch = 3'd0;
    logic        s_axis_q_tvalid = 1'b0;
    logic        s_axis_q_tready;

    logic [15:0] s_axis_kv_k_tdata   = 16'h0000;
    logic [15:0] s_axis_kv_v_tdata   = 16'h0000;
    logic [15:0] s_axis_kv_token_idx = 16'h0000;
    logic        s_axis_kv_tvalid    = 1'b0;
    logic        s_axis_kv_tready;

    logic [15:0] m_axis_token_tdata;
    logic        m_axis_token_tvalid;
    logic        m_axis_token_tready = 1'b0;
    logic        intr;
    logic        dbg_rd_busy_seen;
    logic        tb_rd_busy_seen_reported = 1'b0;
    logic        tb_spec_reported = 1'b0;

    integer fail_count;

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
        .dbg_rd_busy_seen    (dbg_rd_busy_seen)
    );

    always @(posedge clk) begin
        if (dbg_rd_busy_seen && !tb_rd_busy_seen_reported) begin
            $display("[TB %0t] FETCH_KV: rd_busy_seen asserted", $time);
            tb_rd_busy_seen_reported <= 1'b1;
        end
        if (dut.u_ais.u_spec_decode_ctrl.cand_q_valid &&
            (dut.u_ais.u_spec_decode_ctrl.cand_batch_id == 3'd0) &&
            (dut.u_ais.u_spec_decode_ctrl.cand_q_addr == 6'd0) &&
            !tb_spec_reported) begin
            $display("[TB %0t] SPEC: first candidate issued, k advancing", $time);
            tb_spec_reported <= 1'b1;
        end
    end

    task automatic axil_write;
        input [11:0] addr;
        input [31:0] data;
        integer guard;
        begin
            @(posedge clk);
            #1;
            s_axil_awaddr  = addr;
            s_axil_wdata   = data;
            s_axil_wstrb   = 4'hF;
            s_axil_awvalid = 1'b1;
            s_axil_wvalid  = 1'b1;

            guard = 0;
            while ((s_axil_awvalid || s_axil_wvalid) && guard < 128) begin
                @(posedge clk);
                #1;
                if (s_axil_awready)
                    s_axil_awvalid = 1'b0;
                if (s_axil_wready)
                    s_axil_wvalid = 1'b0;
                guard = guard + 1;
            end

            guard = 0;
            while (!s_axil_bvalid && guard < 128) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            @(posedge clk);
            #1;
        end
    endtask

    task automatic axil_read;
        input [11:0] addr;
        output [31:0] data;
        integer guard;
        begin
            @(posedge clk);
            #1;
            s_axil_araddr  = addr;
            s_axil_arvalid = 1'b1;
            guard = 0;
            while (s_axil_arvalid && guard < 128) begin
                @(posedge clk);
                #1;
                if (s_axil_arready)
                    s_axil_arvalid = 1'b0;
                guard = guard + 1;
            end
            guard = 0;
            while (!s_axil_rvalid && guard < 128) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            data = s_axil_rdata;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic drive_q_vector;
        input [2:0] batch_id;
        integer elem;
        begin
            for (elem = 0; elem < HEAD_DIM; elem = elem + 1) begin
                @(posedge clk);
                #1;
                s_axis_q_tdata  = 16'h0100;
                s_axis_q_taddr  = elem[5:0];
                s_axis_q_tbatch = batch_id;
                s_axis_q_tvalid = 1'b1;
            end
            @(posedge clk);
            #1;
            s_axis_q_tvalid = 1'b0;
        end
    endtask

    task automatic drive_kv_token;
        input [2:0] token_idx;
        begin
            @(posedge clk);
            #1;
            s_axis_kv_k_tdata   = 16'h0100;
            s_axis_kv_v_tdata   = 16'h0100;
            s_axis_kv_token_idx = {13'd0, token_idx};
            s_axis_kv_tvalid    = 1'b1;
            @(posedge clk);
            #1;
            s_axis_kv_tvalid = 1'b0;
        end
    endtask

    initial begin : stim
        integer i;
        integer irq_wait;
        integer token_wait;
        integer kv_wait;
        logic [31:0] rd_data;
        logic irq_seen;
        logic token_seen_after_irq;

        fail_count = 0;
        irq_seen = 1'b0;
        token_seen_after_irq = 1'b0;

        repeat (20) @(posedge clk);
        #1;
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        repeat (10) @(posedge clk);
        axil_write(12'h010, 32'h0000_0000);
        repeat (10) @(posedge clk);
        axil_write(12'h014, 32'h0000_0004);
        repeat (10) @(posedge clk);
        axil_write(12'h018, 32'h0000_0000);
        repeat (10) @(posedge clk);
        axil_write(12'h01C, 32'h0000_0001);
        repeat (10) @(posedge clk);
        axil_write(12'h028, 32'h0000_002A);
        repeat (10) @(posedge clk);
        axil_write(12'h02C, 32'h0000_002A);
        repeat (10) @(posedge clk);
        axil_write(12'h030, 32'h0000_002A);
        repeat (10) @(posedge clk);
        axil_write(12'h034, 32'h0000_002A);
        repeat (10) @(posedge clk);
        axil_write(12'h038, 32'h0000_002A);
        repeat (10) @(posedge clk);
        axil_write(12'h00C, 32'h0000_0001);
        repeat (300) @(posedge clk);

        for (i = 0; i < 4; i = i + 1) begin
            drive_kv_token(i[2:0]);
            repeat (40) @(posedge clk);
        end

        for (kv_wait = 0; kv_wait < 5000; kv_wait = kv_wait + 1) begin
            axil_read(12'h020, rd_data);
            if (rd_data[0]) begin
                $display("[TB %0t] KV commit complete - kv_ready asserted", $time);
                kv_wait = 5000;
            end
        end

        if (!rd_data[0]) begin
            $error("KV ready did not assert before 5000-cycle timeout");
            fail_count = fail_count + 1;
        end

        axil_write(12'h000, 32'h0000_0001);

        for (i = 0; i < 4; i = i + 1)
            drive_q_vector(i[2:0]);

        for (irq_wait = 0; irq_wait < 20000; irq_wait = irq_wait + 1) begin
            @(posedge clk);
            if (intr) begin
                irq_seen = 1'b1;
                irq_wait = 20000;
            end
        end

        if (!irq_seen) begin
            $error("IRQ did not assert before 20000-cycle timeout");
            fail_count = fail_count + 1;
        end

        for (token_wait = 0; token_wait < 100; token_wait = token_wait + 1) begin
            @(posedge clk);
            if (m_axis_token_tvalid) begin
                token_seen_after_irq = 1'b1;
                token_wait = 100;
            end
        end

        if (!token_seen_after_irq) begin
            $error("token_out_tvalid did not assert within 100 cycles of IRQ");
            fail_count = fail_count + 1;
        end

        if (m_axis_token_tdata == 16'd0) begin
            $error("token_out_tdata is zero");
            fail_count = fail_count + 1;
        end

        if (m_axis_token_tdata == 16'h0001) begin
            $error("token_out_tdata is 0001, reset leakthrough still present");
            fail_count = fail_count + 1;
        end

        m_axis_token_tready = 1'b1;

        $display("CIRCLE X1 TOKEN_OUT: %h", m_axis_token_tdata);
        if (fail_count == 0)
            $display("CIRCLE X1 SIM: PASS");
        else
            $display("CIRCLE X1 SIM: FAIL");

        $finish;
    end

    initial begin : safety_timeout
        #2500000;
        $error("CIRCLE X1 SIM: timeout");
        $display("CIRCLE X1 SIM: FAIL");
        $finish;
    end

endmodule
