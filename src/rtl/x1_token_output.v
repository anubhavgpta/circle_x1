// x1_token_output.v -- AIS token output to AXI4-Stream
`timescale 1ns/1ps

module x1_token_output (
    input  wire        clk,
    input  wire        rst_n,

    // From AIS
    input  wire [15:0] generated_token,
    input  wire        token_valid,

    // AXI4-Stream master
    output reg  [15:0] m_axis_token_tdata,
    output reg         m_axis_token_tvalid,
    input  wire        m_axis_token_tready,

    // Overflow indicator
    output reg         tok_overflow
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_token_tdata  <= 16'd0;
            m_axis_token_tvalid <= 1'b0;
            tok_overflow        <= 1'b0;
        end else begin
            tok_overflow <= 1'b0;

            if (token_valid) begin
                if (m_axis_token_tvalid && !m_axis_token_tready) begin
                    // Buffer full -- incoming token dropped
                    tok_overflow <= 1'b1;
                end else begin
                    m_axis_token_tdata  <= generated_token;
                    m_axis_token_tvalid <= 1'b1;
                end
            end else if (m_axis_token_tvalid && m_axis_token_tready) begin
                // Handshake completed -- clear valid
                m_axis_token_tvalid <= 1'b0;
            end
        end
    end

endmodule
