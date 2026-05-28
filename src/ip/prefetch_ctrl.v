`timescale 1ns/1ps
// Vera -- Sequential Read Prefetch Controller
//
// Snoops rw_engine read requests, detects per-session page-boundary
// sequential access, and requests prefetches into a two-entry buffer.
//
// Array ports eliminated (flat ports only for xsim compatibility).

module prefetch_ctrl #(
    parameter NUM_SESSIONS     = 8,
    parameter PAGE_SIZE_TOKENS = 16
) (
    input clk,
    input rst_n,

    // Observed rw_engine read requests
    input  [2:0]  obs_session_id,
    input  [11:0] obs_token_pos,
    input         obs_rd_req,

    // Prefetch request output
    output reg [2:0] pf_session_id,
    output reg [4:0] pf_logical_page,
    output reg       pf_req,
    input            pf_ack,

    // Two-entry prefetch buffer status -- flat ports (no array ports)
    output reg       pf_buf_valid_0,
    output reg       pf_buf_valid_1,
    output reg [4:0] pf_buf_page_0,
    output reg [4:0] pf_buf_page_1,
    output reg [2:0] pf_buf_sess_0,
    output reg [2:0] pf_buf_sess_1
);

    localparam ST_IDLE     = 2'd0;
    localparam ST_WAIT_ACK = 2'd1;

    reg [1:0] state;
    reg [4:0] last_page [0:NUM_SESSIONS-1];
    reg       seen_req  [0:NUM_SESSIONS-1];
    reg       buf_age_0, buf_age_1;
    reg [2:0] pend_session;
    reg [4:0] pend_page;

    wire [4:0] obs_page = obs_token_pos / PAGE_SIZE_TOKENS;
    wire       crosses_next_page =
        obs_rd_req &&
        seen_req[obs_session_id] &&
        (obs_page == (last_page[obs_session_id] + 1'b1));

    integer i;

    // Fill buffer entry 0 or 1 (fill_slot=0 or 1)
    task fill_buffer;
        input [2:0] sess;
        input [4:0] page;
        reg fill_slot;
        begin
            // LRU: pick empty slot first, else evict oldest
            if (!pf_buf_valid_0)
                fill_slot = 1'b0;
            else if (!pf_buf_valid_1)
                fill_slot = 1'b1;
            else if (buf_age_0 == 1'b0)
                fill_slot = 1'b0;
            else
                fill_slot = 1'b1;

            if (fill_slot == 1'b0) begin
                pf_buf_valid_0 <= 1'b1;
                pf_buf_page_0  <= page;
                pf_buf_sess_0  <= sess;
                buf_age_0      <= 1'b1;
                buf_age_1      <= 1'b0;
            end else begin
                pf_buf_valid_1 <= 1'b1;
                pf_buf_page_1  <= page;
                pf_buf_sess_1  <= sess;
                buf_age_1      <= 1'b1;
                buf_age_0      <= 1'b0;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            pf_session_id   <= 3'd0;
            pf_logical_page <= 5'd0;
            pf_req          <= 1'b0;
            pend_session    <= 3'd0;
            pend_page       <= 5'd0;
            pf_buf_valid_0  <= 1'b0;
            pf_buf_valid_1  <= 1'b0;
            pf_buf_page_0   <= 5'd0;
            pf_buf_page_1   <= 5'd0;
            pf_buf_sess_0   <= 3'd0;
            pf_buf_sess_1   <= 3'd0;
            buf_age_0       <= 1'b0;
            buf_age_1       <= 1'b0;
            for (i = 0; i < NUM_SESSIONS; i = i + 1) begin
                last_page[i] <= 5'd0;
                seen_req[i]  <= 1'b0;
            end
        end else begin
            pf_req <= 1'b0;

            if (obs_rd_req) begin
                last_page[obs_session_id] <= obs_page;
                seen_req[obs_session_id]  <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    if (crosses_next_page) begin
                        pf_session_id   <= obs_session_id;
                        pf_logical_page <= obs_page;
                        pend_session    <= obs_session_id;
                        pend_page       <= obs_page;
                        pf_req          <= 1'b1;
                        if (pf_ack) begin
                            fill_buffer(obs_session_id, obs_page);
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_WAIT_ACK;
                        end
                    end
                end

                ST_WAIT_ACK: begin
                    if (pf_ack) begin
                        fill_buffer(pend_session, pend_page);
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
