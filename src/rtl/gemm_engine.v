`timescale 1ns/1ps

module gemm_engine #(
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16,
  parameter PE_ROWS    = 8,
  parameter PE_COLS    = 8
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            start,
  input  wire [6:0]                      m_size,
  input  wire [6:0]                      n_size,
  input  wire                            a_valid,
  input  wire [DATA_WIDTH*PE_COLS-1:0]   a_data,
  input  wire                            b_wr_en,
  input  wire [6:0]                      b_wr_col,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  b_wr_data,
  output reg                             valid_out,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  result_out
);

  localparam G_IDLE   = 2'd0;
  localparam G_LOAD   = 2'd1;
  localparam G_FOLD   = 2'd2;
  localparam G_OUTPUT = 2'd3;

  reg [DATA_WIDTH-1:0]         b_ram     [0:HEAD_DIM-1][0:HEAD_DIM-1];
  reg [31:0]                   acc       [0:PE_ROWS-1][0:PE_COLS-1];
  reg [2:0]                    fold_cnt;
  reg [6:0]                    row_cnt;
  reg [5:0]                    col_base;
  reg [1:0]                    state;
  reg [DATA_WIDTH*PE_COLS-1:0] a_row_buf [0:PE_ROWS-1];

  genvar gk, gi, gj;
  integer                    pack_t, pack_j;
  wire                       clr_acc = (state == G_IDLE && start) ||
                                       (state == G_OUTPUT && row_cnt < m_size - 7'd1);
  wire [DATA_WIDTH-1:0]      sat_out [0:PE_ROWS-1][0:PE_COLS-1];

  generate
    for (gk = 0; gk < HEAD_DIM; gk = gk + 1) begin : gen_b_wr
      always @(posedge clk) begin
        if (b_wr_en)
          b_ram[b_wr_col][gk] <= b_wr_data[gk*DATA_WIDTH +: DATA_WIDTH];
      end
    end
  endgenerate

  generate
    for (gi = 0; gi < PE_ROWS; gi = gi + 1) begin : gen_pe_row
      for (gj = 0; gj < PE_COLS; gj = gj + 1) begin : gen_pe_col
        wire [DATA_WIDTH-1:0] pe_a = a_row_buf[fold_cnt][gj*DATA_WIDTH +: DATA_WIDTH];
        wire [DATA_WIDTH-1:0] pe_b = b_ram[col_base + gj][fold_cnt * PE_COLS + gi];
        wire signed [31:0]    pe_p = $signed(pe_a) * $signed(pe_b);
        always @(posedge clk or negedge rst_n) begin
          if (!rst_n)
            acc[gi][gj] <= 32'd0;
          else if (clr_acc)
            acc[gi][gj] <= 32'd0;
          else if (state == G_FOLD)
            acc[gi][gj] <= acc[gi][gj] + pe_p;
        end
        wire signed [31:0] acc_norm = $signed(acc[gi][gj]) >>> 11;
        assign sat_out[gi][gj] = (acc_norm > $signed(32'sd32767)) ? 16'h7FFF :
                                  (acc_norm < $signed(-32'sd32768)) ? 16'h8000 :
                                  acc_norm[15:0];
      end
    end
  endgenerate

  always @(*) col_base = fold_cnt * PE_COLS;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= G_IDLE;
      valid_out  <= 1'b0;
      result_out <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
      row_cnt    <= 7'd0;
      fold_cnt   <= 3'd0;
    end else begin
      valid_out <= 1'b0;
      case (state)
        G_IDLE: begin
          if (start) begin
            row_cnt  <= 7'd0;
            fold_cnt <= 3'd0;
            state    <= G_LOAD;
          end
        end
        G_LOAD: begin
          if (a_valid) begin
            a_row_buf[fold_cnt] <= a_data;
            if (fold_cnt == 3'd7) begin
              fold_cnt <= 3'd0;
              state    <= G_FOLD;
            end else begin
              fold_cnt <= fold_cnt + 3'd1;
            end
          end
        end
        G_FOLD: begin
          if (fold_cnt == 3'd7) begin
            fold_cnt <= 3'd0;
            state    <= G_OUTPUT;
          end else begin
            fold_cnt <= fold_cnt + 3'd1;
          end
        end
        G_OUTPUT: begin
          valid_out <= 1'b1;
          for (pack_t = 0; pack_t < HEAD_DIM/PE_COLS; pack_t = pack_t + 1)
            for (pack_j = 0; pack_j < PE_COLS; pack_j = pack_j + 1)
              result_out[(pack_t*PE_COLS+pack_j)*DATA_WIDTH +: DATA_WIDTH] <= sat_out[pack_t][pack_j];
          if (row_cnt < m_size - 7'd1) begin
            row_cnt  <= row_cnt + 7'd1;
            fold_cnt <= 3'd0;
            state    <= G_LOAD;
          end else begin
            state <= G_IDLE;
          end
        end
        default: state <= G_IDLE;
      endcase
    end
  end

endmodule
