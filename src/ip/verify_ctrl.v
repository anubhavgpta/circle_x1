// verify_ctrl.v
// Circle AIS -- verification controller for Kael parallel attention scoring.
`timescale 1ns/1ps

module verify_ctrl #(
    parameter HEAD_DIM  = 64,
    parameter MAX_BATCH = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control from inference_sequencer
    input  wire        verify_start,
    input  wire [2:0]  session_id,
    input  wire [15:0] token_start,
    input  wire [15:0] token_end,
    input  wire [15:0] token_pos,
    input  wire [2:0]  batch_size,

    // Q vector stream from spec_decode_ctrl
    input  wire [15:0] cand_q_data,
    input  wire [5:0]  cand_q_addr,
    input  wire [2:0]  cand_batch_id,
    input  wire        cand_q_valid,
    input  wire        cand_done,

    // Kael attention_ctrl interface
    output reg  [15:0] q_data,
    output reg  [5:0]  q_addr,
    output reg  [2:0]  q_batch_id,
    output reg         q_valid,
    output reg  [2:0]  kael_batch_size,
    output reg  [2:0]  kael_session_id,
    output reg  [15:0] kael_token_start,
    output reg  [15:0] kael_token_end,
    output reg  [15:0] kael_token_pos,
    output reg         attn_start,

    input  wire        attn_done,
    input  wire        attn_busy,

    // Context output from Kael
    input  wire [15:0] ctx_out,
    input  wire [2:0]  ctx_batch_id,
    input  wire        ctx_valid,
    input  wire        ctx_last,

    output reg  [15:0] vctx_out,
    output reg  [2:0]  vctx_batch_id,
    output reg         vctx_valid,
    output reg         vctx_last,

    // Status
    output reg         verify_done,
    output reg         verify_busy
);

    localparam IDLE = 3'd0;
    localparam LOAD = 3'd1;
    localparam FIRE = 3'd2;
    localparam WAIT = 3'd3;
    localparam DONE = 3'd4;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            q_data           <= 16'd0;
            q_addr           <= 6'd0;
            q_batch_id       <= 3'd0;
            q_valid          <= 1'b0;
            kael_batch_size  <= 3'd0;
            kael_session_id  <= 3'd0;
            kael_token_start <= 16'd0;
            kael_token_end   <= 16'd0;
            kael_token_pos   <= 16'd0;
            attn_start       <= 1'b0;
            vctx_out         <= 16'd0;
            vctx_batch_id    <= 3'd0;
            vctx_valid       <= 1'b0;
            vctx_last        <= 1'b0;
            verify_done      <= 1'b0;
            verify_busy      <= 1'b0;
        end else begin
            attn_start  <= 1'b0;
            verify_done <= 1'b0;

            case (state)

                IDLE: begin
                    q_valid       <= 1'b0;
                    vctx_out      <= 16'd0;
                    vctx_batch_id <= 3'd0;
                    vctx_valid    <= 1'b0;
                    vctx_last     <= 1'b0;

                    if (verify_start && !verify_busy) begin
                        verify_busy <= 1'b1;
                        state       <= LOAD;
                    end
                end

                LOAD: begin
                    q_data     <= cand_q_data;
                    q_addr     <= cand_q_addr;
                    q_batch_id <= cand_batch_id;
                    q_valid    <= cand_q_valid;

                    vctx_out      <= 16'd0;
                    vctx_batch_id <= 3'd0;
                    vctx_valid    <= 1'b0;
                    vctx_last     <= 1'b0;

                    if (cand_done) begin
                        kael_batch_size  <= batch_size;
                        kael_session_id  <= session_id;
                        kael_token_start <= token_start;
                        kael_token_end   <= token_end;
                        kael_token_pos   <= token_pos;
                        state            <= FIRE;
                    end
                end

                FIRE: begin
                    q_valid       <= 1'b0;
                    attn_start    <= 1'b1;
                    vctx_out      <= 16'd0;
                    vctx_batch_id <= 3'd0;
                    vctx_valid    <= 1'b0;
                    vctx_last     <= 1'b0;
                    state         <= WAIT;
                end

                WAIT: begin
                    q_valid       <= 1'b0;
                    vctx_out      <= ctx_out;
                    vctx_batch_id <= ctx_batch_id;
                    vctx_valid    <= ctx_valid;
                    vctx_last     <= ctx_last;

                    if (attn_done) begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    q_valid       <= 1'b0;
                    vctx_out      <= 16'd0;
                    vctx_batch_id <= 3'd0;
                    // One-cycle pulse lets token_arbiter exit STREAM->COMPARE
                    vctx_valid    <= 1'b1;
                    vctx_last     <= 1'b1;
                    verify_done   <= 1'b1;
                    verify_busy   <= 1'b0;
                    state         <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
