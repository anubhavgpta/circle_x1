// kv_commit_ctrl.v
// Circle AIS -- KV commit and rollback controller.
// Streams accepted tokens to Vera via wr_req/wr_ack, then evicts speculative
// pages via evict_valid/evict_ack. Page granularity: PAGE_SIZE_TOKENS=16 (>> 4).

module kv_commit_ctrl #(
    parameter PAGE_SIZE_TOKENS = 16,
    parameter MAX_CANDIDATES   = 7
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        commit_start,
    input  wire [2:0]  session_id,
    input  wire [15:0] token_base_pos,
    input  wire [2:0]  accepted_count,
    input  wire        rollback_needed,
    input  wire [15:0] rollback_token_pos,
    input  wire [15:0] spec_tail_pos,

    // KV data stream for accepted tokens
    input  wire [15:0] commit_k_data,
    input  wire [15:0] commit_v_data,
    input  wire [2:0]  commit_token_idx,
    input  wire        commit_kv_valid,

    // Vera write interface
    output reg         wr_req,
    output reg  [2:0]  wr_session_id,
    output reg  [15:0] wr_token_pos,
    output reg  [15:0] wr_k_data,
    output reg  [15:0] wr_v_data,
    input  wire        wr_ack,

    // Vera eviction interface
    output reg         evict_valid,
    output reg  [7:0]  evict_page_id,
    output reg  [2:0]  evict_session_id,
    input  wire        evict_ack,

    // Status
    output reg         commit_done,
    output reg         commit_busy
);

    localparam IDLE  = 2'd0;
    localparam WRITE = 2'd1;
    localparam EVICT = 2'd2;
    localparam DONE  = 2'd3;

    reg [1:0]  state;
    reg [2:0]  k_reg;
    reg        rollback_reg;
    reg [2:0]  session_reg;
    reg [15:0] token_base_reg;
    reg [15:0] rollback_pos_reg;
    reg [15:0] spec_tail_reg;
    reg [2:0]  write_idx;
    reg [7:0]  evict_page_cur;
    reg [7:0]  evict_page_end;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            k_reg            <= 3'd0;
            rollback_reg     <= 1'b0;
            session_reg      <= 3'd0;
            token_base_reg   <= 16'd0;
            rollback_pos_reg <= 16'd0;
            spec_tail_reg    <= 16'd0;
            write_idx        <= 3'd0;
            evict_page_cur   <= 8'd0;
            evict_page_end   <= 8'd0;
            wr_req           <= 1'b0;
            wr_session_id    <= 3'd0;
            wr_token_pos     <= 16'd0;
            wr_k_data        <= 16'd0;
            wr_v_data        <= 16'd0;
            evict_valid      <= 1'b0;
            evict_page_id    <= 8'd0;
            evict_session_id <= 3'd0;
            commit_done      <= 1'b0;
            commit_busy      <= 1'b0;
        end else begin
            commit_done <= 1'b0;

            case (state)

                IDLE: begin
                    if (commit_start && !commit_busy) begin
                        commit_busy      <= 1'b1;
                        k_reg            <= accepted_count;
                        rollback_reg     <= rollback_needed;
                        session_reg      <= session_id;
                        token_base_reg   <= token_base_pos;
                        rollback_pos_reg <= rollback_token_pos;
                        spec_tail_reg    <= spec_tail_pos;
                        write_idx        <= 3'd0;

                        if (accepted_count != 3'd0) begin
                            state <= WRITE;
                        end else if (rollback_needed) begin
                            // page = token_pos >> 4 = token_pos[11:4]
                            evict_page_cur <= rollback_token_pos[11:4];
                            evict_page_end <= spec_tail_pos[11:4];
                            state          <= EVICT;
                        end else begin
                            state <= DONE;
                        end
                    end
                end

                WRITE: begin
                    if (!wr_req) begin
                        // Wait for upstream to present the token we need
                        if (commit_kv_valid && commit_token_idx == write_idx) begin
                            wr_req        <= 1'b1;
                            wr_session_id <= session_reg;
                            wr_token_pos  <= token_base_reg + {13'd0, write_idx};
                            wr_k_data     <= commit_k_data;
                            wr_v_data     <= commit_v_data;
                        end
                    end else begin
                        if (wr_ack) begin
                            wr_req <= 1'b0;
                            if (write_idx == k_reg - 3'd1) begin
                                // Last accepted token written
                                if (rollback_reg) begin
                                    evict_page_cur <= rollback_pos_reg[11:4];
                                    evict_page_end <= spec_tail_reg[11:4];
                                    state          <= EVICT;
                                end else begin
                                    state <= DONE;
                                end
                            end else begin
                                write_idx <= write_idx + 3'd1;
                            end
                        end
                    end
                end

                EVICT: begin
                    if (!evict_valid) begin
                        evict_valid      <= 1'b1;
                        evict_page_id    <= evict_page_cur;
                        evict_session_id <= session_reg;
                    end else if (evict_ack) begin
                        evict_valid <= 1'b0;
                        if (evict_page_cur == evict_page_end) begin
                            state <= DONE;
                        end else begin
                            evict_page_cur <= evict_page_cur + 8'd1;
                        end
                    end
                end

                DONE: begin
                    commit_done <= 1'b1;
                    commit_busy <= 1'b0;
                    state       <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
