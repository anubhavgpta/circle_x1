`timescale 1ns/1ps

module embedding_lut #(
  parameter VOCAB_SIZE = 32000,
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16
)(
  input  wire                            clk,
  input  wire                            rst_n,
  // Write port (preload)
  input  wire                            wr_en,
  input  wire [14:0]                     wr_addr,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  wr_data,
  // Read port
  input  wire                            rd_en,
  input  wire [14:0]                     rd_addr,
  output reg                             valid_out,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  emb_out
);

  (* ram_style = "block" *) reg [DATA_WIDTH*HEAD_DIM-1:0] emb_ram [0:VOCAB_SIZE-1];
  reg [14:0] rd_addr_r;
  reg        rd_valid_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      rd_addr_r  <= 15'd0;
      rd_valid_r <= 1'b0;
      valid_out  <= 1'b0;
      emb_out    <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
    end else begin
      if (wr_en) begin
        emb_ram[wr_addr] <= wr_data;
      end

      rd_addr_r  <= rd_addr;
      rd_valid_r <= rd_en;

      emb_out   <= emb_ram[rd_addr_r];
      valid_out <= rd_valid_r;
    end
  end

endmodule
