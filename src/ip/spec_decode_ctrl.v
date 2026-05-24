// spec_decode_ctrl.v
// Circle AIS -- speculative decode Q-vector buffer and replay controller.

module spec_decode_ctrl #(
    parameter HEAD_DIM       = 64,
    parameter MAX_CANDIDATES = 7
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control from inference_sequencer
    input  wire        spec_start,
    input  wire [2:0]  session_id,
    input  wire [15:0] token_start,
    input  wire [2:0]  num_candidates,

    // Draft and target Q vector feed from host
    input  wire [15:0] draft_q_data,
    input  wire [5:0]  draft_q_addr,
    input  wire [2:0]  draft_batch_id,
    input  wire        draft_q_valid,

    // Output stream to verify_ctrl
    output reg  [15:0] cand_q_data,
    output reg  [5:0]  cand_q_addr,
    output reg  [2:0]  cand_batch_id,
    output reg         cand_q_valid,
    output reg  [2:0]  cand_count,
    output reg         cand_done,

    // Status
    output reg         spec_busy,
    output reg         spec_idle
);

    localparam IDLE   = 2'd0;
    localparam RECV   = 2'd1;
    localparam STREAM = 2'd2;
    localparam DONE   = 2'd3;

    reg [1:0] state;
    reg [2:0] k_reg;
    reg [2:0] stream_batch;
    reg [5:0] stream_addr;
    reg [15:0] q_buf [0:((MAX_CANDIDATES + 1) * HEAD_DIM) - 1];

    integer reset_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            k_reg         <= 3'd0;
            stream_batch  <= 3'd0;
            stream_addr   <= 6'd0;
            cand_q_data   <= 16'd0;
            cand_q_addr   <= 6'd0;
            cand_batch_id <= 3'd0;
            cand_q_valid  <= 1'b0;
            cand_count    <= 3'd0;
            cand_done     <= 1'b0;
            spec_busy     <= 1'b0;
            spec_idle     <= 1'b1;
            for (reset_idx = 0; reset_idx < (MAX_CANDIDATES + 1) * HEAD_DIM; reset_idx = reset_idx + 1)
                q_buf[reset_idx] <= 16'd0;
        end else begin
            cand_done <= 1'b0;

            case (state)

                IDLE: begin
                    cand_q_valid  <= 1'b0;
                    cand_q_data   <= 16'd0;
                    cand_q_addr   <= 6'd0;
                    cand_batch_id <= 3'd0;
                    spec_idle     <= 1'b1;

                    if (spec_start && !spec_busy) begin
                        k_reg        <= num_candidates;
                        stream_batch <= 3'd0;
                        stream_addr  <= 6'd0;
                        spec_busy    <= 1'b1;
                        spec_idle    <= 1'b0;
                        state        <= RECV;
                    end
                end

                RECV: begin
                    cand_q_valid <= 1'b0;
                    spec_idle    <= 1'b0;

                    if (draft_q_valid) begin
                        q_buf[(draft_batch_id * HEAD_DIM) + draft_q_addr] <= draft_q_data;

                        if ((draft_batch_id == k_reg) && (draft_q_addr == HEAD_DIM - 1)) begin
                            cand_count   <= k_reg + 3'd1;
                            stream_batch <= 3'd0;
                            stream_addr  <= 6'd0;
                            state        <= STREAM;
                        end
                    end
                end

                STREAM: begin
                    spec_idle     <= 1'b0;
                    cand_q_valid  <= 1'b1;
                    cand_q_data   <= q_buf[(stream_batch * HEAD_DIM) + stream_addr];
                    cand_q_addr   <= stream_addr;
                    cand_batch_id <= stream_batch;

                    if ((stream_batch == k_reg) && (stream_addr == HEAD_DIM - 1)) begin
                        state <= DONE;
                    end else if (stream_addr == HEAD_DIM - 1) begin
                        stream_addr  <= 6'd0;
                        stream_batch <= stream_batch + 3'd1;
                    end else begin
                        stream_addr <= stream_addr + 6'd1;
                    end
                end

                DONE: begin
                    cand_q_valid <= 1'b0;
                    cand_done    <= 1'b1;
                    spec_busy    <= 1'b0;
                    spec_idle    <= 1'b1;
                    state        <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
