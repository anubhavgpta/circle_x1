// circle_x1.v -- Circle X1 top-level integration
`timescale 1ns/1ps

module circle_x1 #(
    parameter TOTAL_PAGES      = 256,
    parameter PAGE_SIZE_TOKENS = 16,
    parameter HEAD_DIM         = 64,
    parameter NUM_SESSIONS     = 8,
    parameter DATA_WIDTH       = 16,
    parameter SRAM_BANKS       = 4,
    parameter MAX_BATCH        = 8,
    parameter AXI_ADDR_WIDTH   = 12,
    parameter AXI_DATA_WIDTH   = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite slave
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    input  wire [AXI_DATA_WIDTH-1:0] s_axil_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axil_wstrb,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,
    output wire [1:0]  s_axil_bresp,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,
    output wire [AXI_DATA_WIDTH-1:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,

    // AXI4-Stream Q input
    input  wire [15:0] s_axis_q_tdata,
    input  wire [5:0]  s_axis_q_taddr,
    input  wire [2:0]  s_axis_q_tbatch,
    input  wire        s_axis_q_tvalid,
    output wire        s_axis_q_tready,

    // AXI4-Stream KV input
    input  wire [15:0] s_axis_kv_k_tdata,
    input  wire [15:0] s_axis_kv_v_tdata,
    input  wire [15:0] s_axis_kv_token_idx,
    input  wire        s_axis_kv_tvalid,
    output wire        s_axis_kv_tready,

    // AXI4-Stream token output
    output wire [15:0] m_axis_token_tdata,
    output wire        m_axis_token_tvalid,
    input  wire        m_axis_token_tready,

    // Interrupt
    output wire        intr
);

    // ----------------------------------------------------------------
    // Internal wires: x1_reg_ctrl outputs to AIS
    // ----------------------------------------------------------------
    wire        infer_start;
    wire [2:0]  reg_session_id;
    wire [11:0] reg_prompt_len;
    wire [2:0]  reg_spec_k;
    wire [11:0] reg_max_new_tokens;
    wire [15:0] reg_target_token_id;
    wire [15:0] reg_draft_0, reg_draft_1, reg_draft_2, reg_draft_3;
    wire [15:0] reg_draft_4, reg_draft_5, reg_draft_6;

    // ----------------------------------------------------------------
    // Internal wires: AIS (inference_sequencer) outputs
    // ----------------------------------------------------------------
    wire        wr_req;
    wire [2:0]  wr_session_id;
    wire [15:0] wr_token_pos;
    wire [15:0] wr_k_data;
    wire [15:0] wr_v_data;
    wire        wr_ack;

    wire        ais_evict_valid;
    wire [7:0]  ais_evict_page_id;
    wire [2:0]  ais_evict_session_id;

    wire [15:0] q_data;
    wire [5:0]  q_addr;
    wire [2:0]  q_batch_id;
    wire        q_valid;
    wire [2:0]  kael_batch_size;
    wire [2:0]  kael_session_id;
    wire [15:0] kael_token_start;
    wire [15:0] kael_token_end;
    wire        attn_start;
    wire        attn_done;
    wire        attn_busy;
    wire [15:0] ctx_out;
    wire [2:0]  ctx_batch_id;
    wire        ctx_valid;
    wire        ctx_last;

    wire [15:0] generated_token;
    wire        token_valid;
    wire        infer_done;
    wire        infer_busy;
    wire [2:0]  ais_state;

    // ----------------------------------------------------------------
    // Internal wires: Kael (attention_ctrl) outputs to Vera
    // ----------------------------------------------------------------
    wire        kael_rd_req;
    wire [2:0]  kael_rd_session_id;
    wire [15:0] kael_rd_token_start;
    wire [15:0] kael_rd_token_end;

    // ----------------------------------------------------------------
    // Internal wires: Vera (kv_cache_ctrl) outputs
    // ----------------------------------------------------------------
    wire [15:0] vera_rd_k_data;
    wire [15:0] vera_rd_v_data;
    wire        vera_rd_valid;
    wire        vera_rd_last;
    wire        vera_rd_busy;
    wire        vera_evict_valid;
    wire [7:0]  vera_evict_page_id;
    wire [2:0]  vera_evict_session_id;
    wire        vera_irq;

    // ----------------------------------------------------------------
    // Internal wires: stream adapters
    // ----------------------------------------------------------------
    wire [15:0] draft_q_data;
    wire [5:0]  draft_q_addr;
    wire [2:0]  draft_q_batch_id;
    wire        draft_q_valid;

    wire [15:0] commit_k_data;
    wire [15:0] commit_v_data;
    wire [2:0]  commit_token_idx;
    wire        commit_kv_valid;

    // ----------------------------------------------------------------
    // Vera AXI4-Lite bus (x1_reg_ctrl master <-> vera slave)
    // ----------------------------------------------------------------
    wire        vera_s_awvalid, vera_s_awready;
    wire [31:0] vera_s_awaddr;
    wire        vera_s_wvalid,  vera_s_wready;
    wire [31:0] vera_s_wdata;
    wire [3:0]  vera_s_wstrb;
    wire        vera_s_bvalid,  vera_s_bready;
    wire [1:0]  vera_s_bresp;
    wire        vera_s_arvalid, vera_s_arready;
    wire [31:0] vera_s_araddr;
    wire        vera_s_rvalid,  vera_s_rready;
    wire [31:0] vera_s_rdata;
    wire [1:0]  vera_s_rresp;

    // ----------------------------------------------------------------
    // u_reg_ctrl: AXI4-Lite register file
    // ----------------------------------------------------------------
    x1_reg_ctrl #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_reg_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axil_awvalid   (s_axil_awvalid),
        .s_axil_awready   (s_axil_awready),
        .s_axil_awaddr    (s_axil_awaddr),
        .s_axil_wvalid    (s_axil_wvalid),
        .s_axil_wready    (s_axil_wready),
        .s_axil_wdata     (s_axil_wdata),
        .s_axil_wstrb     (s_axil_wstrb),
        .s_axil_bvalid    (s_axil_bvalid),
        .s_axil_bready    (s_axil_bready),
        .s_axil_bresp     (s_axil_bresp),
        .s_axil_arvalid   (s_axil_arvalid),
        .s_axil_arready   (s_axil_arready),
        .s_axil_araddr    (s_axil_araddr),
        .s_axil_rvalid    (s_axil_rvalid),
        .s_axil_rready    (s_axil_rready),
        .s_axil_rdata     (s_axil_rdata),
        .s_axil_rresp     (s_axil_rresp),
        // Vera proxy master
        .m_axil_vera_awvalid(vera_s_awvalid),
        .m_axil_vera_awready(vera_s_awready),
        .m_axil_vera_awaddr (vera_s_awaddr),
        .m_axil_vera_wvalid (vera_s_wvalid),
        .m_axil_vera_wready (vera_s_wready),
        .m_axil_vera_wdata  (vera_s_wdata),
        .m_axil_vera_wstrb  (vera_s_wstrb),
        .m_axil_vera_bvalid (vera_s_bvalid),
        .m_axil_vera_bready (vera_s_bready),
        .m_axil_vera_bresp  (vera_s_bresp),
        .m_axil_vera_arvalid(vera_s_arvalid),
        .m_axil_vera_arready(vera_s_arready),
        .m_axil_vera_araddr (vera_s_araddr),
        .m_axil_vera_rvalid (vera_s_rvalid),
        .m_axil_vera_rready (vera_s_rready),
        .m_axil_vera_rdata  (vera_s_rdata),
        .m_axil_vera_rresp  (vera_s_rresp),
        // AIS control outputs
        .infer_start      (infer_start),
        .session_id       (reg_session_id),
        .prompt_len       (reg_prompt_len),
        .spec_k           (reg_spec_k),
        .max_new_tokens   (reg_max_new_tokens),
        .target_token_id  (reg_target_token_id),
        .draft_token_id_0 (reg_draft_0),
        .draft_token_id_1 (reg_draft_1),
        .draft_token_id_2 (reg_draft_2),
        .draft_token_id_3 (reg_draft_3),
        .draft_token_id_4 (reg_draft_4),
        .draft_token_id_5 (reg_draft_5),
        .draft_token_id_6 (reg_draft_6),
        // AIS status inputs
        .infer_busy       (infer_busy),
        .infer_done       (infer_done),
        .ais_state        (ais_state),
        .generated_token  (generated_token),
        .token_valid      (token_valid),
        .intr             (intr)
    );

    // ----------------------------------------------------------------
    // u_ais: AIS inference sequencer
    // ----------------------------------------------------------------
    inference_sequencer u_ais (
        .clk              (clk),
        .rst_n            (rst_n),
        .infer_start      (infer_start),
        .session_id       (reg_session_id),
        .prompt_len       ({4'b0, reg_prompt_len}),
        .spec_k           (reg_spec_k),
        .max_new_tokens   ({4'b0, reg_max_new_tokens}),
        .draft_q_data     (draft_q_data),
        .draft_q_addr     (draft_q_addr),
        .draft_batch_id   (draft_q_batch_id),
        .draft_q_valid    (draft_q_valid),
        .draft_token_id_0 (reg_draft_0),
        .draft_token_id_1 (reg_draft_1),
        .draft_token_id_2 (reg_draft_2),
        .draft_token_id_3 (reg_draft_3),
        .draft_token_id_4 (reg_draft_4),
        .draft_token_id_5 (reg_draft_5),
        .draft_token_id_6 (reg_draft_6),
        .target_token_id  (reg_target_token_id),
        .commit_k_data    (commit_k_data),
        .commit_v_data    (commit_v_data),
        .commit_token_idx (commit_token_idx),
        .commit_kv_valid  (commit_kv_valid),
        .wr_req           (wr_req),
        .wr_session_id    (wr_session_id),
        .wr_token_pos     (wr_token_pos),
        .wr_k_data        (wr_k_data),
        .wr_v_data        (wr_v_data),
        .wr_ack           (wr_ack),
        .evict_valid      (ais_evict_valid),
        .evict_page_id    (ais_evict_page_id),
        .evict_session_id (ais_evict_session_id),
        .evict_ack        (1'b1),
        .q_data           (q_data),
        .q_addr           (q_addr),
        .q_batch_id       (q_batch_id),
        .q_valid          (q_valid),
        .kael_batch_size  (kael_batch_size),
        .kael_session_id  (kael_session_id),
        .kael_token_start (kael_token_start),
        .kael_token_end   (kael_token_end),
        .attn_start       (attn_start),
        .attn_done        (attn_done),
        .attn_busy        (attn_busy),
        .ctx_out          (ctx_out),
        .ctx_batch_id     (ctx_batch_id),
        .ctx_valid        (ctx_valid),
        .ctx_last         (ctx_last),
        .generated_token  (generated_token),
        .token_valid      (token_valid),
        .infer_done       (infer_done),
        .infer_busy       (infer_busy),
        .ais_state        (ais_state)
    );

    // ----------------------------------------------------------------
    // u_kael: Kael attention controller
    // ----------------------------------------------------------------
    attention_ctrl #(
        .HEAD_DIM   (HEAD_DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_SESSIONS(NUM_SESSIONS),
        .MAX_BATCH  (MAX_BATCH)
    ) u_kael (
        .clk          (clk),
        .rst_n        (rst_n),
        .q_data       (q_data),
        .q_addr       (q_addr),
        .q_batch_id   (q_batch_id),
        .q_valid      (q_valid),
        .batch_size   (kael_batch_size),
        .session_id   (kael_session_id),
        .token_start  (kael_token_start),
        .token_end    (kael_token_end),
        .attn_start   (attn_start),
        .rd_req       (kael_rd_req),
        .rd_session_id(kael_rd_session_id),
        .rd_token_start(kael_rd_token_start),
        .rd_token_end  (kael_rd_token_end),
        .rd_k_data    (vera_rd_k_data),
        .rd_v_data    (vera_rd_v_data),
        .rd_valid     (vera_rd_valid),
        .rd_last      (vera_rd_last),
        .rd_busy      (vera_rd_busy),
        .ctx_out      (ctx_out),
        .ctx_batch_id (ctx_batch_id),
        .ctx_valid    (ctx_valid),
        .ctx_last     (ctx_last),
        .attn_done    (attn_done),
        .attn_busy    (attn_busy)
    );

    // ----------------------------------------------------------------
    // u_vera: Vera KV cache (HEAD_DIM=1 for 16-bit KV buses)
    // ----------------------------------------------------------------
    kv_cache_ctrl #(
        .TOTAL_PAGES     (TOTAL_PAGES),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS),
        .HEAD_DIM        (1),
        .NUM_SESSIONS    (NUM_SESSIONS),
        .DATA_WIDTH      (DATA_WIDTH),
        .SRAM_BANKS      (SRAM_BANKS)
    ) u_vera (
        .clk            (clk),
        .rst_n          (rst_n),
        // AXI4-Lite slave from reg_ctrl proxy
        .s_axi_awvalid  (vera_s_awvalid),
        .s_axi_awready  (vera_s_awready),
        .s_axi_awaddr   (vera_s_awaddr),
        .s_axi_wvalid   (vera_s_wvalid),
        .s_axi_wready   (vera_s_wready),
        .s_axi_wdata    (vera_s_wdata),
        .s_axi_wstrb    (vera_s_wstrb),
        .s_axi_bvalid   (vera_s_bvalid),
        .s_axi_bready   (vera_s_bready),
        .s_axi_bresp    (vera_s_bresp),
        .s_axi_arvalid  (vera_s_arvalid),
        .s_axi_arready  (vera_s_arready),
        .s_axi_araddr   (vera_s_araddr),
        .s_axi_rvalid   (vera_s_rvalid),
        .s_axi_rready   (vera_s_rready),
        .s_axi_rdata    (vera_s_rdata),
        .s_axi_rresp    (vera_s_rresp),
        .irq            (vera_irq),
        // KV write from AIS
        .wr_req         (wr_req),
        .wr_session_id  (wr_session_id),
        .wr_token_pos   (wr_token_pos[11:0]),
        .wr_k_data      (wr_k_data),
        .wr_v_data      (wr_v_data),
        .wr_ack         (wr_ack),
        // KV read from Kael
        .rd_req         (kael_rd_req),
        .rd_session_id  (kael_rd_session_id),
        .rd_token_start (kael_rd_token_start[11:0]),
        .rd_token_end   (kael_rd_token_end[11:0]),
        .rd_k_data      (vera_rd_k_data),
        .rd_v_data      (vera_rd_v_data),
        .rd_valid       (vera_rd_valid),
        .rd_last        (vera_rd_last),
        .rd_busy        (vera_rd_busy),
        // Eviction (auto-ack -- vera internally decides eviction)
        .evict_valid    (vera_evict_valid),
        .evict_page_id  (vera_evict_page_id),
        .evict_session_id(vera_evict_session_id),
        .evict_ack      (1'b1)
    );

    // ----------------------------------------------------------------
    // u_q_adapter: Q stream to AIS draft_q_*
    // ----------------------------------------------------------------
    x1_q_stream_adapter u_q_adapter (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axis_q_tdata  (s_axis_q_tdata),
        .s_axis_q_taddr  (s_axis_q_taddr),
        .s_axis_q_tbatch (s_axis_q_tbatch),
        .s_axis_q_tvalid (s_axis_q_tvalid),
        .s_axis_q_tready (s_axis_q_tready),
        .draft_q_data    (draft_q_data),
        .draft_q_addr    (draft_q_addr),
        .draft_q_batch_id(draft_q_batch_id),
        .draft_q_valid   (draft_q_valid)
    );

    // ----------------------------------------------------------------
    // u_kv_adapter: KV stream to AIS commit_kv_*
    // ----------------------------------------------------------------
    x1_kv_stream_adapter u_kv_adapter (
        .clk                  (clk),
        .rst_n                (rst_n),
        .s_axis_kv_k_tdata    (s_axis_kv_k_tdata),
        .s_axis_kv_v_tdata    (s_axis_kv_v_tdata),
        .s_axis_kv_token_idx  (s_axis_kv_token_idx),
        .s_axis_kv_tvalid     (s_axis_kv_tvalid),
        .s_axis_kv_tready     (s_axis_kv_tready),
        .commit_k_data        (commit_k_data),
        .commit_v_data        (commit_v_data),
        .commit_token_idx     (commit_token_idx),
        .commit_kv_valid      (commit_kv_valid)
    );

    // ----------------------------------------------------------------
    // u_tok_out: AIS token to AXI4-Stream output
    // ----------------------------------------------------------------
    x1_token_output u_tok_out (
        .clk                (clk),
        .rst_n              (rst_n),
        .generated_token    (generated_token),
        .token_valid        (token_valid),
        .m_axis_token_tdata (m_axis_token_tdata),
        .m_axis_token_tvalid(m_axis_token_tvalid),
        .m_axis_token_tready(m_axis_token_tready),
        .tok_overflow       ()
    );

endmodule
