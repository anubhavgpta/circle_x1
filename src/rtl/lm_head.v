`timescale 1ns/1ps

module lm_head #(
  parameter VOCAB_SIZE = 32000,
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16,
  parameter PE_ROWS    = 8,
  parameter PE_COLS    = 8
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            wr_en,
  input  wire [14:0]                     wr_col,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  wr_data,
  input  wire                            start,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  hidden_vec,
  output reg                             logit_valid,
  output reg                             logit_last,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  logit_data
);

  localparam TILE_SIZE = HEAD_DIM;
  localparam NUM_TILES = VOCAB_SIZE / TILE_SIZE;
  localparam FOLD_STEPS = HEAD_DIM / PE_COLS;

  localparam LM_IDLE    = 3'd0;
  localparam LM_LOAD    = 3'd1;
  localparam LM_COMPUTE = 3'd2;
  localparam LM_OUTPUT  = 3'd3;

  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] w_lm [0:VOCAB_SIZE-1][0:HEAD_DIM-1];

  integer init_wi, init_wj;
  initial begin
    for (init_wi = 0; init_wi < VOCAB_SIZE; init_wi = init_wi + 1)
      for (init_wj = 0; init_wj < HEAD_DIM; init_wj = init_wj + 1)
        w_lm[init_wi][init_wj] = {DATA_WIDTH{1'b0}};
  end

  reg [9:0]  tile_cnt;
  reg [6:0]  load_cnt;
  reg [3:0]  fold_cnt;
  reg [3:0]  fold_cnt_q1;   // fold_cnt delayed 1 cycle -- fixes a_data sample alignment
  reg [2:0]  state;
  reg        compute_started;

  reg                             gemm_start;
  reg                             gemm_a_valid;
  reg [DATA_WIDTH*PE_COLS-1:0]    gemm_a_data;
  reg                             gemm_b_wr_en;
  reg [6:0]                       gemm_b_wr_col;
  reg [DATA_WIDTH*HEAD_DIM-1:0]   gemm_b_wr_data;
  wire                            gemm_valid_out;
  wire [DATA_WIDTH*HEAD_DIM-1:0]  gemm_result_out;

  wire [15:0] curr_vocab_col = tile_cnt * TILE_SIZE + load_cnt;

  genvar gk;
  generate
    for (gk = 0; gk < HEAD_DIM; gk = gk + 1) begin : gen_w_wr
      always @(posedge clk) begin
        if (wr_en && (wr_col < VOCAB_SIZE))
          w_lm[wr_col][gk] <= wr_data[gk*DATA_WIDTH +: DATA_WIDTH];
      end
    end
  endgenerate

  integer pk;
  integer pa;
  always @(*) begin
    gemm_b_wr_data = {(DATA_WIDTH*HEAD_DIM){1'b0}};
    for (pk = 0; pk < HEAD_DIM; pk = pk + 1)
      gemm_b_wr_data[pk*DATA_WIDTH +: DATA_WIDTH] = w_lm[curr_vocab_col][pk];
  end

  // fold_cnt_q1: 1-cycle pipeline register so a_data is stable when gemm samples it.
  // When gemm_engine transitions G_IDLE->G_LOAD on cycle T, the first a_valid arrives
  // on cycle T+1. At that moment fold_cnt has already incremented, so using the raw
  // fold_cnt would present fold=1 data in slot 0 and leave a_row_buf[7] unloaded (X).
  // Using fold_cnt_q1 presents the fold=0 data at posedge T+1 as required.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fold_cnt_q1 <= 4'd0;
    else        fold_cnt_q1 <= fold_cnt;
  end

  always @(*) begin
    gemm_a_data = {(DATA_WIDTH*PE_COLS){1'b0}};
    for (pa = 0; pa < PE_COLS; pa = pa + 1)
      gemm_a_data[pa*DATA_WIDTH +: DATA_WIDTH] =
        hidden_vec[((fold_cnt_q1*PE_COLS)+pa)*DATA_WIDTH +: DATA_WIDTH];
  end

  gemm_engine #(
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) u_gemm (
    .clk(clk),
    .rst_n(rst_n),
    .start(gemm_start),
    .m_size(7'd1),
    .n_size(7'd64),
    .a_valid(gemm_a_valid),
    .a_data(gemm_a_data),
    .b_wr_en(gemm_b_wr_en),
    .b_wr_col(gemm_b_wr_col),
    .b_wr_data(gemm_b_wr_data),
    .valid_out(gemm_valid_out),
    .result_out(gemm_result_out)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tile_cnt     <= 10'd0;
      load_cnt     <= 7'd0;
      fold_cnt     <= 4'd0;
      state        <= LM_IDLE;
      compute_started <= 1'b0;
      gemm_start   <= 1'b0;
      gemm_a_valid <= 1'b0;
      gemm_b_wr_en <= 1'b0;
      gemm_b_wr_col<= 7'd0;
      logit_valid  <= 1'b0;
      logit_last   <= 1'b0;
      logit_data   <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
    end else begin
      gemm_start   <= 1'b0;
      gemm_a_valid <= 1'b0;
      gemm_b_wr_en <= 1'b0;
      logit_valid  <= 1'b0;
      logit_last   <= 1'b0;
      case (state)
        LM_IDLE: begin
          tile_cnt <= 10'd0;
          load_cnt <= 7'd0;
          fold_cnt <= 4'd0;
          compute_started <= 1'b0;
          if (start)
            state <= LM_LOAD;
        end
        LM_LOAD: begin
          gemm_b_wr_en  <= 1'b1;
          gemm_b_wr_col <= load_cnt;
          if (load_cnt == TILE_SIZE-1) begin
            load_cnt <= 7'd0;
            fold_cnt <= 4'd0;
            compute_started <= 1'b0;
            state    <= LM_COMPUTE;
          end else begin
            load_cnt <= load_cnt + 7'd1;
          end
        end
        LM_COMPUTE: begin
          if (!compute_started) begin
            gemm_start <= 1'b1;
            compute_started <= 1'b1;
          end else if (fold_cnt < FOLD_STEPS) begin
            gemm_a_valid <= 1'b1;
            fold_cnt <= fold_cnt + 4'd1;
          end
          if (gemm_valid_out) begin
            logit_data <= gemm_result_out;
            compute_started <= 1'b0;
            state <= LM_OUTPUT;
          end
        end
        LM_OUTPUT: begin
          logit_valid <= 1'b1;
          if (tile_cnt == NUM_TILES-1) begin
            logit_last <= 1'b1;
            state <= LM_IDLE;
          end else begin
            tile_cnt <= tile_cnt + 10'd1;
            load_cnt <= 7'd0;
            fold_cnt <= 4'd0;
            compute_started <= 1'b0;
            state <= LM_LOAD;
          end
        end
        default: state <= LM_IDLE;
      endcase
    end
  end

endmodule
