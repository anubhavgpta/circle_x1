// token_arbiter.v
// Circle AIS Layer 2 -- speculative draft token acceptance/rejection
`timescale 1ns/1ps
// Greedy argmax over HEAD_DIM=64 context vector words streamed from Kael.
// Tie-breaking: lowest index wins (first maximum seen is kept).

// BUG FIX 4: argmax must be over vocab logits, not HEAD_DIM context words
module token_arbiter #(
    parameter HEAD_DIM       = 64,
    parameter MAX_CANDIDATES = 7,
    parameter VOCAB_SIZE     = 32000,
    parameter VOCAB_WIDTH    = 15    // ceil(log2(VOCAB_SIZE))
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        arb_start,
    input  wire [2:0]  num_candidates,
    input  wire [2:0]  target_batch_id,

    // Context vectors from Kael
    input  wire [15:0] vctx_out,
    input  wire [2:0]  vctx_batch_id,
    input  wire        vctx_valid,
    input  wire        vctx_last,

    // Draft token IDs (flat, stable before arb_start)
    input  wire [15:0] draft_token_id_0,
    input  wire [15:0] draft_token_id_1,
    input  wire [15:0] draft_token_id_2,
    input  wire [15:0] draft_token_id_3,
    input  wire [15:0] draft_token_id_4,
    input  wire [15:0] draft_token_id_5,
    input  wire [15:0] draft_token_id_6,
    input  wire [15:0] target_token_id,

    // LM head argmax result -- TODO: wire from GEMM engine when built;
    // for now caller drives the winning token index directly
    input  wire [VOCAB_WIDTH-1:0] linear_logits,

    // Rollback base
    input  wire [15:0] token_base_pos,

    // Outputs
    output reg  [2:0]  accepted_count,
    output reg  [15:0] next_token_id,
    output reg         rollback_needed,
    output reg  [15:0] rollback_token_pos,
    output reg         arb_done,
    output reg         arb_busy
);

    // FSM encoding
    localparam IDLE    = 2'd0;
    localparam STREAM  = 2'd1;
    localparam COMPARE = 2'd2;
    localparam DONE    = 2'd3;

    reg [1:0] state;

    // Argmax tracking for current batch
    reg [15:0] max_val;
    reg [5:0]  max_idx;
    reg [5:0]  word_cnt;

    // Latched num_candidates and batch_id from last vctx_last beat
    reg [2:0]  k_reg;
    reg [2:0]  cur_batch_id;

    // Mux: select draft_token_id[i][VOCAB_WIDTH-1:0] by batch_id
    function [14:0] get_draft_token;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: get_draft_token = draft_token_id_0[14:0];
                3'd1: get_draft_token = draft_token_id_1[14:0];
                3'd2: get_draft_token = draft_token_id_2[14:0];
                3'd3: get_draft_token = draft_token_id_3[14:0];
                3'd4: get_draft_token = draft_token_id_4[14:0];
                3'd5: get_draft_token = draft_token_id_5[14:0];
                3'd6: get_draft_token = draft_token_id_6[14:0];
                default: get_draft_token = 15'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= IDLE;
            accepted_count    <= 3'd0;
            next_token_id     <= 16'd0;
            rollback_needed   <= 1'b0;
            rollback_token_pos<= 16'd0;
            arb_done          <= 1'b0;
            arb_busy          <= 1'b0;
            max_val           <= 16'd0;
            max_idx           <= 6'd0;
            word_cnt          <= 6'd0;
            k_reg             <= 3'd0;
            cur_batch_id      <= 3'd0;
        end else begin
            // Default: clear single-cycle pulses
            arb_done <= 1'b0;

            case (state)

                IDLE: begin
                    if (arb_start && !arb_busy) begin
                        arb_busy        <= 1'b1;
                        k_reg           <= num_candidates;
                        accepted_count  <= 3'd0;
                        rollback_needed <= 1'b0;
                        // Prime argmax for first batch
                        max_val         <= 16'd0;
                        max_idx         <= 6'd0;
                        word_cnt        <= 6'd0;
                        state           <= STREAM;
                    end
                end

                STREAM: begin
                    if (vctx_valid) begin
                        // Reset accumulators on first word of a new batch
                        // (word_cnt==0 means we are at the start of a batch)
                        if (word_cnt == 6'd0) begin
                            max_val  <= vctx_out;
                            max_idx  <= 6'd0;
                            word_cnt <= 6'd1;
                        end else begin
                            // Strict greater-than keeps lowest index on tie
                            if (vctx_out > max_val) begin
                                max_val <= vctx_out;
                                max_idx <= word_cnt;
                            end
                            word_cnt <= word_cnt + 6'd1;
                        end

                        if (vctx_last) begin
                            cur_batch_id <= vctx_batch_id;
                            word_cnt     <= 6'd0;
                            state        <= COMPARE;
                        end
                    end
                end

                COMPARE: begin
                    // Use k_reg (latched at arb_start) not live target_batch_id input
                    if (cur_batch_id == k_reg) begin
                        // All candidate batches processed successfully
                        accepted_count     <= k_reg;
                        rollback_needed    <= 1'b0;
                        next_token_id      <= target_token_id;
                        rollback_token_pos <= token_base_pos + {13'd0, k_reg};
                        state              <= DONE;
                    end else begin
                        if (linear_logits != get_draft_token(cur_batch_id)) begin
                            // Mismatch at candidate cur_batch_id
                            accepted_count     <= cur_batch_id;
                            rollback_needed    <= 1'b1;
                            next_token_id      <= target_token_id;
                            rollback_token_pos <= token_base_pos + {13'd0, cur_batch_id};
                            state              <= DONE;
                        end else begin
                            // Match -- continue to next batch
                            state <= STREAM;
                        end
                    end
                end

                DONE: begin
                    arb_done <= 1'b1;
                    arb_busy <= 1'b0;
                    state    <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
