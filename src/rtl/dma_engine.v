`timescale 1ns/1ps

module dma_engine #(
  parameter BURST_LEN  = 64,
  parameter DATA_WIDTH = 16,
  parameter HEAD_DIM   = 64,
  parameter ADDR_WIDTH = 32
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire [31:0]                     src_addr,
  input  wire [1:0]                      dst_sel,
  input  wire [14:0]                     dst_addr,
  input  wire [9:0]                      length,
  input  wire                            start,
  output reg                             done,
  input  wire                            dram_valid,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  dram_data,
  output reg                             dram_ready,
  output reg                             emb_wr_en,
  output reg  [14:0]                     emb_wr_addr,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  emb_wr_data,
  output reg                             lm_wr_en,
  output reg  [14:0]                     lm_wr_col,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  lm_wr_data,
  output reg                             ffn_wr_en,
  output reg  [1:0]                      ffn_b_wr_sel,
  output reg  [6:0]                      ffn_b_wr_col,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  ffn_wr_data,
  output reg                             gam_wr_en,
  output reg  [4:0]                      gam_wr_addr,
  output reg  [31:0]                     gam_wr_data
);

  localparam D_IDLE   = 2'd0;
  localparam D_ACTIVE = 2'd1;
  localparam D_DONE   = 2'd2;

  reg [1:0]  state;
  reg [9:0]  word_cnt;
  reg [14:0] dst_addr_r;
  reg [1:0]  dst_sel_r;
  reg [9:0]  length_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= D_IDLE;
      word_cnt     <= 10'd0;
      dst_addr_r   <= 15'd0;
      dst_sel_r    <= 2'd0;
      length_r     <= 10'd0;
      done         <= 1'b0;
      dram_ready   <= 1'b0;
      emb_wr_en    <= 1'b0;
      emb_wr_addr  <= 15'd0;
      emb_wr_data  <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      lm_wr_en     <= 1'b0;
      lm_wr_col    <= 15'd0;
      lm_wr_data   <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      ffn_wr_en    <= 1'b0;
      ffn_b_wr_sel <= 2'd0;
      ffn_b_wr_col <= 7'd0;
      ffn_wr_data  <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      gam_wr_en    <= 1'b0;
      gam_wr_addr  <= 5'd0;
      gam_wr_data  <= 32'd0;
    end else begin
      done      <= 1'b0;
      emb_wr_en <= 1'b0;
      lm_wr_en  <= 1'b0;
      ffn_wr_en <= 1'b0;
      gam_wr_en <= 1'b0;

      case (state)
        D_IDLE: begin
          if (start) begin
            dst_sel_r  <= dst_sel;
            dst_addr_r <= dst_addr;
            length_r   <= length;
            word_cnt   <= 10'd0;
            dram_ready <= 1'b1;
            state      <= D_ACTIVE;
          end
        end

        D_ACTIVE: begin
          if (dram_valid && dram_ready) begin
            word_cnt   <= word_cnt + 10'd1;
            dst_addr_r <= dst_addr_r + 15'd1;

            case (dst_sel_r)
              2'd0: begin
                emb_wr_en   <= 1'b1;
                emb_wr_addr <= dst_addr_r;
                emb_wr_data <= dram_data;
              end
              2'd1: begin
                lm_wr_en   <= 1'b1;
                lm_wr_col  <= dst_addr_r;
                lm_wr_data <= dram_data;
              end
              2'd2: begin
                ffn_wr_en    <= 1'b1;
                ffn_b_wr_sel <= dram_data[1:0];
                ffn_b_wr_col <= dst_addr_r[6:0];
                ffn_wr_data  <= dram_data;
              end
              2'd3: begin
                gam_wr_en   <= 1'b1;
                gam_wr_addr <= dst_addr_r[4:0];
                gam_wr_data <= dram_data[31:0];
              end
              default: ;
            endcase

            if (word_cnt + 10'd1 == length_r) begin
              dram_ready <= 1'b0;
              state      <= D_DONE;
            end
          end
        end

        D_DONE: begin
          done  <= 1'b1;
          state <= D_IDLE;
        end

        default: state <= D_IDLE;
      endcase
    end
  end

endmodule
