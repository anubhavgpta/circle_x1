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
    output wire        intr,

    // Debug
    output wire        dbg_rd_busy_seen,

    // DMA host interface
    input  wire                            dma_start,
    input  wire [31:0]                     dma_src_addr,
    input  wire [1:0]                      dma_dst_sel,
    input  wire [14:0]                     dma_dst_addr,
    input  wire [9:0]                      dma_length,
    input  wire                            dram_valid,
    input  wire [DATA_WIDTH*HEAD_DIM-1:0]  dram_data,
    output wire                            dram_ready,
    output wire                            dma_done,
    // Sampling parameters
    input  wire [2:0]                      temp_shift,
    input  wire [15:0]                     p_threshold,
    // Sampled token output
    output wire                            samp_valid,
    output wire [14:0]                     samp_token
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
    wire [DATA_WIDTH*HEAD_DIM-1:0] reg_gamma;

    // ----------------------------------------------------------------
    // Internal wires: AIS (inference_sequencer) outputs
    // ----------------------------------------------------------------
    wire        ais_wr_req;
    wire [2:0]  ais_wr_session_id;
    wire [15:0] ais_wr_token_pos;
    wire [15:0] ais_wr_k_data;
    wire [15:0] ais_wr_v_data;
    wire        wr_ack;
    reg         prefill_wr_req;
    reg  [2:0]  prefill_wr_session_id;
    reg  [15:0] prefill_wr_token_pos;
    reg  [15:0] prefill_wr_k_data;
    reg  [15:0] prefill_wr_v_data;
    reg  [2:0]  prefill_count;
    reg         kv_ready;
    wire        vera_wr_req;
    wire [2:0]  vera_wr_session_id;
    wire [15:0] vera_wr_token_pos;
    wire [15:0] vera_wr_k_data;
    wire [15:0] vera_wr_v_data;

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
    wire [15:0] kael_token_pos;
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
    // Internal wires: new modules
    // ----------------------------------------------------------------
    wire                             emb_wr_en;
    wire [14:0]                      emb_wr_addr;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   emb_wr_data;
    wire                             lm_wr_en;
    wire [14:0]                      lm_wr_col;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   lm_wr_data;
    wire                             ffn_wr_en;
    wire [1:0]                       ffn_b_wr_sel;
    wire [6:0]                       ffn_b_wr_col;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   ffn_wr_data;
    wire                             gam_wr_en;
    wire [4:0]                       gam_wr_addr;
    wire [31:0]                      gam_wr_data;

    wire [DATA_WIDTH*HEAD_DIM-1:0]   emb_vec_out;
    wire                             emb_valid_out;

    wire                             lm_logit_valid;
    wire                             lm_logit_last;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   lm_logit_data;

    wire                             samp_valid_out;
    wire [14:0]                      samp_token_id;

    wire                             lc_valid_out;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   lc_vec_out;
    wire                             lc_attn_start;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   lc_attn_vec;

    wire                             mh_valid_out;
    wire [DATA_WIDTH*HEAD_DIM*8-1:0] mh_vec_out;
    wire                             mh_attn_start;
    wire [DATA_WIDTH*HEAD_DIM-1:0]   mh_attn_q;

    // attn_out stub: no accumulated wide output from u_kael exists
    wire [DATA_WIDTH*HEAD_DIM-1:0]   attn_out_wire;
    assign attn_out_wire = {(DATA_WIDTH*HEAD_DIM){1'b0}};

    // gamma_word_array: unpack reg_gamma into 32 x 32-bit words for layer_ctrl
    wire [31:0] gamma_word_array [0:31];
    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : gen_gamma_words
            assign gamma_word_array[gi] = reg_gamma[gi*32 +: 32];
        end
    endgenerate

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
        .gamma_out        (reg_gamma),
        // AIS status inputs
        .infer_busy       (infer_busy),
        .infer_done       (infer_done),
        .ais_state        (ais_state),
        .generated_token  (generated_token),
        .token_valid      (token_valid),
        .kv_ready         (kv_ready),
        .intr             (intr)
    );

    assign vera_wr_req        = infer_busy ? ais_wr_req        : (prefill_wr_req & !wr_ack);
    assign vera_wr_session_id = infer_busy ? ais_wr_session_id : prefill_wr_session_id;
    assign vera_wr_token_pos  = infer_busy ? ais_wr_token_pos  : prefill_wr_token_pos;
    assign vera_wr_k_data     = infer_busy ? ais_wr_k_data     : prefill_wr_k_data;
    assign vera_wr_v_data     = infer_busy ? ais_wr_v_data     : prefill_wr_v_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prefill_wr_req        <= 1'b0;
            prefill_wr_session_id <= 3'd0;
            prefill_wr_token_pos  <= 16'd0;
            prefill_wr_k_data     <= 16'd0;
            prefill_wr_v_data     <= 16'd0;
            prefill_count         <= 3'd0;
            kv_ready              <= 1'b0;
        end else if (!infer_busy) begin
            if (prefill_wr_req) begin
                if (wr_ack) begin
                    prefill_wr_req <= 1'b0;
                    prefill_count  <= prefill_count + 3'd1;
                    if (prefill_count == 3'd3)
                        kv_ready <= 1'b1;
                end
            end else if (commit_kv_valid) begin
                prefill_wr_req        <= 1'b1;
                prefill_wr_session_id <= reg_session_id;
                prefill_wr_token_pos  <= {13'd0, commit_token_idx};
                prefill_wr_k_data     <= commit_k_data;
                prefill_wr_v_data     <= commit_v_data;
                kv_ready              <= 1'b0;
            end
        end
    end

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
        .wr_req           (ais_wr_req),
        .wr_session_id    (ais_wr_session_id),
        .wr_token_pos     (ais_wr_token_pos),
        .wr_k_data        (ais_wr_k_data),
        .wr_v_data        (ais_wr_v_data),
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
        .kael_token_pos   (kael_token_pos),
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
        .token_pos    (kael_token_pos),
        .gamma_in     (reg_gamma),
        .residual_vec ({(DATA_WIDTH*HEAD_DIM){1'b0}}),
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
        .attn_busy    (attn_busy),
        .dbg_rd_busy_seen(dbg_rd_busy_seen)
    );

    // ----------------------------------------------------------------
    // u_vera: Vera KV cache (HEAD_DIM=1 for 16-bit KV buses)
    // ----------------------------------------------------------------
    // BUG FIX 1: pass HEAD_DIM parameter correctly instead of hardcoded 1
    kv_cache_ctrl #(
        .TOTAL_PAGES     (TOTAL_PAGES),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS),
        .HEAD_DIM        (HEAD_DIM),
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
        .wr_req         (vera_wr_req),
        .wr_session_id  (vera_wr_session_id),
        .wr_token_pos   (vera_wr_token_pos[11:0]),
        .wr_k_data      (vera_wr_k_data),
        .wr_v_data      (vera_wr_v_data),
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

    // ----------------------------------------------------------------
    // u_dma: DMA engine
    // ----------------------------------------------------------------
    dma_engine u_dma (
        .clk(clk), .rst_n(rst_n),
        .src_addr(dma_src_addr), .dst_sel(dma_dst_sel),
        .dst_addr(dma_dst_addr), .length(dma_length),
        .start(dma_start), .done(dma_done),
        .dram_valid(dram_valid), .dram_data(dram_data), .dram_ready(dram_ready),
        .emb_wr_en(emb_wr_en), .emb_wr_addr(emb_wr_addr), .emb_wr_data(emb_wr_data),
        .lm_wr_en(lm_wr_en),   .lm_wr_col(lm_wr_col),   .lm_wr_data(lm_wr_data),
        .ffn_wr_en(ffn_wr_en), .ffn_b_wr_sel(ffn_b_wr_sel),
        .ffn_b_wr_col(ffn_b_wr_col), .ffn_wr_data(ffn_wr_data),
        .gam_wr_en(gam_wr_en), .gam_wr_addr(gam_wr_addr), .gam_wr_data(gam_wr_data)
    );

    // ----------------------------------------------------------------
    // u_embedding: Embedding lookup table
    // ----------------------------------------------------------------
    embedding_lut #(.VOCAB_SIZE(32000),.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH))
    u_embedding (
        .clk(clk), .rst_n(rst_n),
        .wr_en(emb_wr_en), .wr_addr(emb_wr_addr), .wr_data(emb_wr_data),
        .rd_en(1'b0), .rd_addr(15'd0),
        .valid_out(emb_valid_out), .emb_out(emb_vec_out)
    );

    // ----------------------------------------------------------------
    // u_lm_head: LM head projection
    // ----------------------------------------------------------------
    lm_head #(.VOCAB_SIZE(32000),.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH))
    u_lm_head (
        .clk(clk), .rst_n(rst_n),
        .wr_en(lm_wr_en), .wr_col(lm_wr_col), .wr_data(lm_wr_data),
        .start(lc_valid_out),
        .hidden_vec(lc_vec_out),
        .logit_valid(lm_logit_valid), .logit_last(lm_logit_last),
        .logit_data(lm_logit_data)
    );

    // ----------------------------------------------------------------
    // u_sampling: Sampling engine
    // ----------------------------------------------------------------
    sampling_engine #(.VOCAB_SIZE(32000),.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH))
    u_sampling (
        .clk(clk), .rst_n(rst_n),
        .start(lc_valid_out),
        .logit_valid(lm_logit_valid), .logit_last(lm_logit_last),
        .logit_data(lm_logit_data),
        .temp_shift(temp_shift), .p_threshold(p_threshold),
        .valid_out(samp_valid_out), .token_id(samp_token_id)
    );

    assign samp_valid = samp_valid_out;
    assign samp_token = samp_token_id;

    // ----------------------------------------------------------------
    // u_layer_ctrl: Transformer layer stack
    // ----------------------------------------------------------------
    layer_ctrl #(.NUM_LAYERS(4),.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH))
    u_layer_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(infer_start),
        .vec_in(emb_vec_out),
        .attn_start(lc_attn_start), .attn_vec(lc_attn_vec),
        .attn_done(mh_valid_out),   .attn_out(mh_vec_out[DATA_WIDTH*HEAD_DIM-1:0]),
        .b_wr_en(ffn_wr_en), .b_wr_sel(ffn_b_wr_sel),
        .b_wr_col(ffn_b_wr_col), .b_wr_data(ffn_wr_data),
        .gamma_word(gamma_word_array),
        .valid_out(lc_valid_out), .vec_out(lc_vec_out)
    );

    // ----------------------------------------------------------------
    // u_multihead: Multi-head attention dispatcher
    // ----------------------------------------------------------------
    multihead_ctrl #(.NUM_HEADS(8),.HEAD_DIM(HEAD_DIM),.DATA_WIDTH(DATA_WIDTH))
    u_multihead (
        .clk(clk), .rst_n(rst_n),
        .start(lc_attn_start),
        .vec_in({8{lc_attn_vec}}),
        .attn_start(mh_attn_start), .attn_q(mh_attn_q),
        .attn_done(attn_done),  .attn_out(attn_out_wire),
        .valid_out(mh_valid_out), .vec_out(mh_vec_out)
    );

endmodule
