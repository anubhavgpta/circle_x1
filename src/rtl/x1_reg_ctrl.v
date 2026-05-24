// x1_reg_ctrl.v -- AXI4-Lite register file and Vera proxy for circle_x1
`timescale 1ns/1ps

module x1_reg_ctrl #(
    parameter AXI_ADDR_WIDTH = 12,
    parameter AXI_DATA_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite slave
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,
    input  wire [AXI_DATA_WIDTH-1:0] s_axil_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axil_wstrb,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    output reg  [1:0]  s_axil_bresp,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,
    output reg  [AXI_DATA_WIDTH-1:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,

    // Vera AXI4-Lite master (proxy port)
    output reg         m_axil_vera_awvalid,
    input  wire        m_axil_vera_awready,
    output reg  [31:0] m_axil_vera_awaddr,
    output reg         m_axil_vera_wvalid,
    input  wire        m_axil_vera_wready,
    output reg  [31:0] m_axil_vera_wdata,
    output reg  [3:0]  m_axil_vera_wstrb,
    input  wire        m_axil_vera_bvalid,
    output reg         m_axil_vera_bready,
    input  wire [1:0]  m_axil_vera_bresp,
    output reg         m_axil_vera_arvalid,
    input  wire        m_axil_vera_arready,
    output reg  [31:0] m_axil_vera_araddr,
    input  wire        m_axil_vera_rvalid,
    output reg         m_axil_vera_rready,
    input  wire [31:0] m_axil_vera_rdata,
    input  wire [1:0]  m_axil_vera_rresp,

    // Outputs to AIS
    output reg         infer_start,
    output reg  [2:0]  session_id,
    output reg  [11:0] prompt_len,
    output reg  [2:0]  spec_k,
    output reg  [11:0] max_new_tokens,
    output reg  [15:0] target_token_id,
    output reg  [15:0] draft_token_id_0,
    output reg  [15:0] draft_token_id_1,
    output reg  [15:0] draft_token_id_2,
    output reg  [15:0] draft_token_id_3,
    output reg  [15:0] draft_token_id_4,
    output reg  [15:0] draft_token_id_5,
    output reg  [15:0] draft_token_id_6,

    // Inputs from AIS
    input  wire        infer_busy,
    input  wire        infer_done,
    input  wire [2:0]  ais_state,
    input  wire [15:0] generated_token,
    input  wire        token_valid,

    // Interrupt
    output reg         intr
);

    // Write FSM
    localparam WS_IDLE  = 3'd0;
    localparam WS_DATAW = 3'd1;
    localparam WS_EXEC  = 3'd2;
    localparam WS_RESP  = 3'd3;
    localparam WS_PAW   = 3'd4;
    localparam WS_PW    = 3'd5;
    localparam WS_PB    = 3'd6;

    // Read FSM
    localparam RS_IDLE  = 3'd0;
    localparam RS_RESP  = 3'd1;
    localparam RS_PAR   = 3'd2;
    localparam RS_PR    = 3'd3;

    reg [2:0]  ws, rs;
    reg [AXI_ADDR_WIDTH-1:0] wr_addr, rd_addr;
    reg [31:0] wr_data;
    reg [3:0]  wr_strb;

    // Register state
    reg done_intr_en;
    reg done_intr;
    reg w1c_intr_clear;   // one-cycle pulse: W1C write to INTR_STATUS
    reg [11:0] token_count;

    // Token count
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        token_count <= 12'd0;
        else if (infer_start) token_count <= 12'd0;
        else if (token_valid) token_count <= token_count + 12'd1;
    end

    // done_intr -- single always block avoids multiple-driver race
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             done_intr <= 1'b0;
        else if (w1c_intr_clear) done_intr <= 1'b0;  // W1C clear wins
        else if (infer_done && done_intr_en) done_intr <= 1'b1;
    end

    // intr output (level-held until cleared)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) intr <= 1'b0;
        else        intr <= done_intr;
    end

    // Read decode (combinatorial function)
    function [31:0] reg_read;
        input [AXI_ADDR_WIDTH-1:0] addr;
        begin
            case (addr)
                12'h000: reg_read = 32'd0;
                12'h004: reg_read = {25'd0, ais_state, 1'b0, infer_done, infer_busy};
                12'h008: reg_read = {31'd0, done_intr};
                12'h00C: reg_read = {31'd0, done_intr_en};
                12'h010: reg_read = {29'd0, session_id};
                12'h014: reg_read = {20'd0, prompt_len};
                12'h018: reg_read = {29'd0, spec_k};
                12'h01C: reg_read = {20'd0, max_new_tokens};
                12'h020: reg_read = {16'd0, generated_token};
                12'h024: reg_read = {20'd0, token_count};
                12'h028: reg_read = {16'd0, target_token_id};
                12'h02C: reg_read = {16'd0, draft_token_id_0};
                12'h030: reg_read = {16'd0, draft_token_id_1};
                12'h034: reg_read = {16'd0, draft_token_id_2};
                12'h038: reg_read = {16'd0, draft_token_id_3};
                12'h03C: reg_read = {16'd0, draft_token_id_4};
                12'h040: reg_read = {16'd0, draft_token_id_5};
                12'h044: reg_read = {16'd0, draft_token_id_6};
                default: reg_read = 32'd0;
            endcase
        end
    endfunction

    // Write FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws               <= WS_IDLE;
            s_axil_awready   <= 1'b1;
            s_axil_wready    <= 1'b0;
            s_axil_bvalid    <= 1'b0;
            s_axil_bresp     <= 2'b00;
            m_axil_vera_awvalid <= 1'b0;
            m_axil_vera_wvalid  <= 1'b0;
            m_axil_vera_bready  <= 1'b0;
            infer_start      <= 1'b0;
            session_id       <= 3'd0;
            prompt_len       <= 12'd0;
            spec_k           <= 3'd0;
            max_new_tokens   <= 12'd0;
            target_token_id  <= 16'd0;
            draft_token_id_0 <= 16'd0;
            draft_token_id_1 <= 16'd0;
            draft_token_id_2 <= 16'd0;
            draft_token_id_3 <= 16'd0;
            draft_token_id_4 <= 16'd0;
            draft_token_id_5 <= 16'd0;
            draft_token_id_6 <= 16'd0;
            done_intr_en     <= 1'b0;
            w1c_intr_clear   <= 1'b0;
            wr_addr          <= {AXI_ADDR_WIDTH{1'b0}};
            wr_data          <= 32'd0;
            wr_strb          <= 4'b1111;
        end else begin
            infer_start      <= 1'b0;
            w1c_intr_clear   <= 1'b0;

            case (ws)
                WS_IDLE: begin
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b0;
                    if (s_axil_awvalid) begin
                        wr_addr        <= s_axil_awaddr;
                        s_axil_awready <= 1'b0;
                        s_axil_wready  <= 1'b1;
                        ws             <= WS_DATAW;
                    end
                end

                WS_DATAW: begin
                    if (s_axil_wvalid) begin
                        wr_data       <= s_axil_wdata;
                        wr_strb       <= s_axil_wstrb;
                        s_axil_wready <= 1'b0;
                        if (wr_addr[8]) begin
                            m_axil_vera_awaddr  <= {20'b0, wr_addr};
                            m_axil_vera_awvalid <= 1'b1;
                            ws                  <= WS_PAW;
                        end else begin
                            ws <= WS_EXEC;
                        end
                    end
                end

                WS_EXEC: begin
                    // W1C
                    if (wr_addr == 12'h008 && wr_data[0])
                        w1c_intr_clear <= 1'b1;
                    // R/W registers
                    case (wr_addr)
                        12'h000: if (wr_data[0]) infer_start <= 1'b1;
                        12'h00C: done_intr_en     <= wr_data[0];
                        12'h010: session_id       <= wr_data[2:0];
                        12'h014: prompt_len       <= wr_data[11:0];
                        12'h018: spec_k           <= wr_data[2:0];
                        12'h01C: max_new_tokens   <= wr_data[11:0];
                        12'h028: target_token_id  <= wr_data[15:0];
                        12'h02C: draft_token_id_0 <= wr_data[15:0];
                        12'h030: draft_token_id_1 <= wr_data[15:0];
                        12'h034: draft_token_id_2 <= wr_data[15:0];
                        12'h038: draft_token_id_3 <= wr_data[15:0];
                        12'h03C: draft_token_id_4 <= wr_data[15:0];
                        12'h040: draft_token_id_5 <= wr_data[15:0];
                        12'h044: draft_token_id_6 <= wr_data[15:0];
                        default: ;
                    endcase
                    s_axil_bvalid <= 1'b1;
                    s_axil_bresp  <= 2'b00;
                    ws            <= WS_RESP;
                end

                WS_RESP: begin
                    if (s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        ws            <= WS_IDLE;
                    end
                end

                WS_PAW: begin
                    if (m_axil_vera_awready) begin
                        m_axil_vera_awvalid <= 1'b0;
                        m_axil_vera_wdata   <= wr_data;
                        m_axil_vera_wstrb   <= wr_strb;
                        m_axil_vera_wvalid  <= 1'b1;
                        ws                  <= WS_PW;
                    end
                end

                WS_PW: begin
                    if (m_axil_vera_wready) begin
                        m_axil_vera_wvalid <= 1'b0;
                        m_axil_vera_bready <= 1'b1;
                        ws                 <= WS_PB;
                    end
                end

                WS_PB: begin
                    if (m_axil_vera_bvalid) begin
                        m_axil_vera_bready <= 1'b0;
                        s_axil_bvalid      <= 1'b1;
                        s_axil_bresp       <= m_axil_vera_bresp;
                        ws                 <= WS_RESP;
                    end
                end

                default: ws <= WS_IDLE;
            endcase
        end
    end

    // Read FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs                  <= RS_IDLE;
            s_axil_arready      <= 1'b1;
            s_axil_rvalid       <= 1'b0;
            s_axil_rdata        <= 32'd0;
            s_axil_rresp        <= 2'b00;
            m_axil_vera_arvalid <= 1'b0;
            m_axil_vera_rready  <= 1'b0;
            m_axil_vera_araddr  <= 32'd0;
            rd_addr             <= {AXI_ADDR_WIDTH{1'b0}};
        end else begin
            case (rs)
                RS_IDLE: begin
                    s_axil_arready <= 1'b1;
                    if (s_axil_arvalid) begin
                        rd_addr        <= s_axil_araddr;
                        s_axil_arready <= 1'b0;
                        if (s_axil_araddr[8]) begin
                            m_axil_vera_araddr  <= {20'b0, s_axil_araddr};
                            m_axil_vera_arvalid <= 1'b1;
                            rs                  <= RS_PAR;
                        end else begin
                            s_axil_rdata  <= reg_read(s_axil_araddr);
                            s_axil_rresp  <= 2'b00;
                            s_axil_rvalid <= 1'b1;
                            rs            <= RS_RESP;
                        end
                    end
                end

                RS_RESP: begin
                    if (s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rs            <= RS_IDLE;
                    end
                end

                RS_PAR: begin
                    if (m_axil_vera_arready) begin
                        m_axil_vera_arvalid <= 1'b0;
                        m_axil_vera_rready  <= 1'b1;
                        rs                  <= RS_PR;
                    end
                end

                RS_PR: begin
                    if (m_axil_vera_rvalid) begin
                        m_axil_vera_rready <= 1'b0;
                        s_axil_rdata       <= m_axil_vera_rdata;
                        s_axil_rresp       <= m_axil_vera_rresp;
                        s_axil_rvalid      <= 1'b1;
                        rs                 <= RS_RESP;
                    end
                end

                default: rs <= RS_IDLE;
            endcase
        end
    end

endmodule
