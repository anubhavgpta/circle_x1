// x1_q_stream_adapter.v -- AXI4-Stream Q vector to AIS draft_q_* signals
`timescale 1ns/1ps

module x1_q_stream_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Stream slave
    input  wire [15:0] s_axis_q_tdata,
    input  wire [5:0]  s_axis_q_taddr,
    input  wire [2:0]  s_axis_q_tbatch,
    input  wire        s_axis_q_tvalid,
    output wire        s_axis_q_tready,

    // AIS outputs (registered)
    output reg  [15:0] draft_q_data,
    output reg  [5:0]  draft_q_addr,
    output reg  [2:0]  draft_q_batch_id,
    output reg         draft_q_valid
);

    // Always ready to accept -- single-entry pass-through register
    assign s_axis_q_tready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            draft_q_data     <= 16'd0;
            draft_q_addr     <= 6'd0;
            draft_q_batch_id <= 3'd0;
            draft_q_valid    <= 1'b0;
        end else if (s_axis_q_tvalid) begin
            draft_q_data     <= s_axis_q_tdata;
            draft_q_addr     <= s_axis_q_taddr;
            draft_q_batch_id <= s_axis_q_tbatch;
            draft_q_valid    <= 1'b1;
        end else begin
            draft_q_valid <= 1'b0;
        end
    end

endmodule
