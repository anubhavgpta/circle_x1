// x1_kv_stream_adapter.v -- AXI4-Stream KV commit input to AIS commit_kv_* signals
`timescale 1ns/1ps

module x1_kv_stream_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Stream slave
    input  wire [15:0] s_axis_kv_k_tdata,
    input  wire [15:0] s_axis_kv_v_tdata,
    input  wire [15:0] s_axis_kv_token_idx,
    input  wire        s_axis_kv_tvalid,
    output wire        s_axis_kv_tready,

    // AIS outputs (registered)
    output reg  [15:0] commit_k_data,
    output reg  [15:0] commit_v_data,
    output reg  [2:0]  commit_token_idx,
    output reg         commit_kv_valid
);

    assign s_axis_kv_tready = 1'b1;

    reg [15:0] k_buf [0:7];
    reg [15:0] v_buf [0:7];
    reg [7:0]  valid_buf;
    reg [2:0]  scan_idx;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            commit_k_data     <= 16'd0;
            commit_v_data     <= 16'd0;
            commit_token_idx  <= 3'd0;
            commit_kv_valid   <= 1'b0;
            valid_buf         <= 8'd0;
            scan_idx          <= 3'd0;
            for (i = 0; i < 8; i = i + 1) begin
                k_buf[i] <= 16'd0;
                v_buf[i] <= 16'd0;
            end
        end else if (s_axis_kv_tvalid) begin
            k_buf[s_axis_kv_token_idx[2:0]] <= s_axis_kv_k_tdata;
            v_buf[s_axis_kv_token_idx[2:0]] <= s_axis_kv_v_tdata;
            valid_buf[s_axis_kv_token_idx[2:0]] <= 1'b1;
            commit_k_data     <= s_axis_kv_k_tdata;
            commit_v_data     <= s_axis_kv_v_tdata;
            commit_token_idx  <= s_axis_kv_token_idx[2:0];
            commit_kv_valid   <= 1'b1;
            scan_idx          <= s_axis_kv_token_idx[2:0] + 3'd1;
        end else begin
            // BUG FIX 3: clear valid bit after use so each entry replays exactly once
            if (valid_buf[scan_idx]) begin
                commit_k_data       <= k_buf[scan_idx];
                commit_v_data       <= v_buf[scan_idx];
                commit_token_idx    <= scan_idx;
                commit_kv_valid     <= 1'b1;
                valid_buf[scan_idx] <= 1'b0;
            end else begin
                commit_kv_valid <= 1'b0;
            end
            scan_idx <= scan_idx + 3'd1;
        end
    end

endmodule
