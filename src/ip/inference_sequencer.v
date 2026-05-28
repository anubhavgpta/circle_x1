// inference_sequencer.v
// Circle AIS -- Layer 2 speculative inference top-level sequencer.
`timescale 1ns/1ps

module inference_sequencer (
    input  wire        clk,
    input  wire        rst_n,

    // Host control
    input  wire        infer_start,
    input  wire [2:0]  session_id,
    input  wire [15:0] prompt_len,
    input  wire [2:0]  spec_k,
    input  wire [15:0] max_new_tokens,

    // Draft Q feed from host
    input  wire [15:0] draft_q_data,
    input  wire [5:0]  draft_q_addr,
    input  wire [2:0]  draft_batch_id,
    input  wire        draft_q_valid,

    // Draft token IDs from host
    input  wire [15:0] draft_token_id_0,
    input  wire [15:0] draft_token_id_1,
    input  wire [15:0] draft_token_id_2,
    input  wire [15:0] draft_token_id_3,
    input  wire [15:0] draft_token_id_4,
    input  wire [15:0] draft_token_id_5,
    input  wire [15:0] draft_token_id_6,
    input  wire [15:0] target_token_id,

    // KV commit feed from host
    input  wire [15:0] commit_k_data,
    input  wire [15:0] commit_v_data,
    input  wire [2:0]  commit_token_idx,
    input  wire        commit_kv_valid,

    // Vera write interface
    output wire        wr_req,
    output wire [2:0]  wr_session_id,
    output wire [15:0] wr_token_pos,
    output wire [15:0] wr_k_data,
    output wire [15:0] wr_v_data,
    input  wire        wr_ack,

    // Vera eviction interface
    output wire        evict_valid,
    output wire [7:0]  evict_page_id,
    output wire [2:0]  evict_session_id,
    input  wire        evict_ack,

    // Kael attention interface
    output wire [15:0] q_data,
    output wire [5:0]  q_addr,
    output wire [2:0]  q_batch_id,
    output wire        q_valid,
    output wire [2:0]  kael_batch_size,
    output wire [2:0]  kael_session_id,
    output wire [15:0] kael_token_start,
    output wire [15:0] kael_token_end,
    output wire [15:0] kael_token_pos,
    output wire        attn_start,
    input  wire        attn_done,
    input  wire        attn_busy,

    // Kael context output
    input  wire [15:0] ctx_out,
    input  wire [2:0]  ctx_batch_id,
    input  wire        ctx_valid,
    input  wire        ctx_last,

    // Host outputs
    output reg  [15:0] generated_token,
    output reg         token_valid,
    output reg         infer_done,
    output reg         infer_busy,
    output reg  [2:0]  ais_state
);

    localparam S_IDLE       = 3'd0;
    localparam S_PREFILL    = 3'd1;
    localparam S_SPEC_DRAFT = 3'd2;
    localparam S_VERIFY     = 3'd3;
    localparam S_ARBITRATE  = 3'd4;
    localparam S_COMMIT     = 3'd5;
    localparam S_DONE       = 3'd6;

    reg [15:0] kv_tail;
    reg [15:0] tokens_generated;
    reg [15:0] spec_tail;

    reg [2:0]  session_reg;
    reg [2:0]  spec_k_reg;
    reg [15:0] max_new_reg;

    reg spec_start;
    reg verify_start;
    reg arb_start;
    reg commit_start;
    reg arb_complete;

    // spec_decode_ctrl outputs
    wire [15:0] cand_q_data;
    wire [5:0]  cand_q_addr;
    wire [2:0]  cand_batch_id;
    wire        cand_q_valid;
    wire [2:0]  cand_count;
    wire        cand_done;
    wire        spec_busy;
    wire        spec_idle;

    // verify_ctrl outputs
    wire [15:0] vctx_out;
    wire [2:0]  vctx_batch_id;
    wire        vctx_valid;
    wire        vctx_last;
    wire        verify_done;
    wire        verify_busy;

    // token_arbiter outputs
    wire [2:0]  accepted_count;
    wire [15:0] next_token_id;
    wire        rollback_needed;
    wire [15:0] rollback_token_pos;
    wire        arb_done;
    wire        arb_busy;

    // kv_commit_ctrl outputs
    wire commit_done;
    wire commit_busy;

    spec_decode_ctrl u_spec_decode_ctrl (
        .clk           (clk),
        .rst_n         (rst_n),
        .spec_start    (spec_start),
        .session_id    (session_reg),
        .token_start   (kv_tail),
        .num_candidates(spec_k_reg),
        .draft_q_data  (draft_q_data),
        .draft_q_addr  (draft_q_addr),
        .draft_batch_id(draft_batch_id),
        .draft_q_valid (draft_q_valid),
        .cand_q_data   (cand_q_data),
        .cand_q_addr   (cand_q_addr),
        .cand_batch_id (cand_batch_id),
        .cand_q_valid  (cand_q_valid),
        .cand_count    (cand_count),
        .cand_done     (cand_done),
        .spec_busy     (spec_busy),
        .spec_idle     (spec_idle)
    );

    verify_ctrl u_verify_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .verify_start    (verify_start),
        .session_id      (session_reg),
        .token_start     (kv_tail),
        // BUG FIX 5: token_end is inclusive tail, not tail-1
        .token_end       (kv_tail),
        .token_pos       (kv_tail),
        .batch_size      (spec_k_reg + 3'd1),
        .cand_q_data     (cand_q_data),
        .cand_q_addr     (cand_q_addr),
        .cand_batch_id   (cand_batch_id),
        .cand_q_valid    (cand_q_valid),
        .cand_done       (cand_done),
        .q_data          (q_data),
        .q_addr          (q_addr),
        .q_batch_id      (q_batch_id),
        .q_valid         (q_valid),
        .kael_batch_size (kael_batch_size),
        .kael_session_id (kael_session_id),
        .kael_token_start(kael_token_start),
        .kael_token_end  (kael_token_end),
        .kael_token_pos  (kael_token_pos),
        .attn_start      (attn_start),
        .attn_done       (attn_done),
        .attn_busy       (attn_busy),
        .ctx_out         (ctx_out),
        .ctx_batch_id    (ctx_batch_id),
        .ctx_valid       (ctx_valid),
        .ctx_last        (ctx_last),
        .vctx_out        (vctx_out),
        .vctx_batch_id   (vctx_batch_id),
        .vctx_valid      (vctx_valid),
        .vctx_last       (vctx_last),
        .verify_done     (verify_done),
        .verify_busy     (verify_busy)
    );

    token_arbiter u_token_arbiter (
        .clk             (clk),
        .rst_n           (rst_n),
        .arb_start       (arb_start),
        .num_candidates  (spec_k_reg),
        .target_batch_id (spec_k_reg),
        .vctx_out        (vctx_out),
        .vctx_batch_id   (vctx_batch_id),
        .vctx_valid      (vctx_valid),
        .vctx_last       (vctx_last),
        .draft_token_id_0(draft_token_id_0),
        .draft_token_id_1(draft_token_id_1),
        .draft_token_id_2(draft_token_id_2),
        .draft_token_id_3(draft_token_id_3),
        .draft_token_id_4(draft_token_id_4),
        .draft_token_id_5(draft_token_id_5),
        .draft_token_id_6(draft_token_id_6),
        .target_token_id (target_token_id),
        .token_base_pos  (kv_tail),
        .accepted_count  (accepted_count),
        .next_token_id   (next_token_id),
        .rollback_needed (rollback_needed),
        .rollback_token_pos(rollback_token_pos),
        .arb_done        (arb_done),
        .arb_busy        (arb_busy)
    );

    kv_commit_ctrl u_kv_commit_ctrl (
        .clk               (clk),
        .rst_n             (rst_n),
        .commit_start      (commit_start),
        .session_id        (session_reg),
        .token_base_pos    (kv_tail),
        .accepted_count    (accepted_count),
        .rollback_needed   (rollback_needed),
        .rollback_token_pos(rollback_token_pos),
        .spec_tail_pos     (spec_tail),
        .commit_k_data     (commit_k_data),
        .commit_v_data     (commit_v_data),
        .commit_token_idx  (commit_token_idx),
        .commit_kv_valid   (commit_kv_valid),
        .wr_req            (wr_req),
        .wr_session_id     (wr_session_id),
        .wr_token_pos      (wr_token_pos),
        .wr_k_data         (wr_k_data),
        .wr_v_data         (wr_v_data),
        .wr_ack            (wr_ack),
        .evict_valid       (evict_valid),
        .evict_page_id     (evict_page_id),
        .evict_session_id  (evict_session_id),
        .evict_ack         (evict_ack),
        .commit_done       (commit_done),
        .commit_busy       (commit_busy)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ais_state        <= S_IDLE;
            kv_tail          <= 16'd0;
            tokens_generated <= 16'd0;
            spec_tail        <= 16'd0;
            session_reg      <= 3'd0;
            spec_k_reg       <= 3'd0;
            max_new_reg      <= 16'd0;
            spec_start       <= 1'b0;
            verify_start     <= 1'b0;
            arb_start        <= 1'b0;
            commit_start     <= 1'b0;
            arb_complete     <= 1'b0;
            generated_token  <= 16'd0;
            token_valid      <= 1'b0;
            infer_done       <= 1'b0;
            infer_busy       <= 1'b0;
        end else begin
            spec_start   <= 1'b0;
            verify_start <= 1'b0;
            arb_start    <= 1'b0;
            commit_start <= 1'b0;
            token_valid  <= 1'b0;
            infer_done   <= 1'b0;

            if (arb_done)
                arb_complete <= 1'b1;

            case (ais_state)

                S_IDLE: begin
                    if (infer_start && !infer_busy) begin
                        session_reg      <= session_id;
                        spec_k_reg       <= spec_k;
                        max_new_reg      <= max_new_tokens;
                        kv_tail          <= prompt_len;
                        tokens_generated <= 16'd0;
                        infer_busy       <= 1'b1;
                        ais_state        <= S_PREFILL;
                    end
                end

                S_PREFILL: begin
                    $display("[SEQ %0t] PREFILL: firing spec_start/verify_start/arb_start, spec_k=%0d", $time, spec_k_reg);
                    spec_start   <= 1'b1;
                    verify_start <= 1'b1;
                    arb_start    <= 1'b1;
                    arb_complete <= 1'b0;
                    spec_tail    <= kv_tail + {13'd0, spec_k_reg};
                    ais_state    <= S_SPEC_DRAFT;
                end

                S_SPEC_DRAFT: begin
                    if (cand_done) begin
                        $display("[SEQ %0t] cand_done seen, moving to S_VERIFY", $time);
                        ais_state <= S_VERIFY;
                    end
                end

                S_VERIFY: begin
                    if (verify_done) begin
                        $display("[SEQ %0t] verify_done seen, moving to S_ARBITRATE", $time);
                        ais_state <= S_ARBITRATE;
                    end
                end

                S_ARBITRATE: begin
                    if (arb_complete || arb_done) begin
                        commit_start <= 1'b1;
                        arb_complete <= 1'b0;
                        ais_state    <= S_COMMIT;
                    end
                end

                S_COMMIT: begin
                    if (commit_done) begin
                        generated_token  <= next_token_id;
                        token_valid      <= 1'b1;
                        tokens_generated <= tokens_generated + {13'd0, accepted_count} + 16'd1;
                        if (!rollback_needed)
                            kv_tail <= kv_tail + {13'd0, accepted_count};

                        if (((tokens_generated + {13'd0, accepted_count} + 16'd1) >= max_new_reg) ||
                            (next_token_id == 16'hFFFF)) begin
                            ais_state <= S_DONE;
                        end else begin
                            spec_start   <= 1'b1;
                            verify_start <= 1'b1;
                            arb_start    <= 1'b1;
                            arb_complete <= 1'b0;
                            spec_tail    <= (rollback_needed ? kv_tail : kv_tail + {13'd0, accepted_count}) +
                                            {13'd0, spec_k_reg};
                            ais_state    <= S_SPEC_DRAFT;
                        end
                    end
                end

                S_DONE: begin
                    infer_done <= 1'b1;
                    infer_busy <= 1'b0;
                    ais_state  <= S_IDLE;
                end

                default: begin
                    ais_state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
