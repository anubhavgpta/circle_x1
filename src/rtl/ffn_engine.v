`timescale 1ns/1ps

module ffn_engine #(
  parameter HEAD_DIM   = 64,
  parameter DATA_WIDTH = 16,
  parameter PE_ROWS    = 8,
  parameter PE_COLS    = 8
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            start,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  vec_in,
  input  wire                            b_wr_en,
  input  wire [1:0]                      b_wr_sel,
  input  wire [6:0]                      b_wr_col,
  input  wire [DATA_WIDTH*HEAD_DIM-1:0]  b_wr_data,
  output reg                             valid_out,
  output reg  [DATA_WIDTH*HEAD_DIM-1:0]  vec_out
);

  // Three gemm_engine instantiation wires
  reg                             gate_start;
  reg                             gate_a_valid;
  wire                            gate_valid_out;
  wire                            gate_b_wr_en;

  reg                             up_start;
  reg                             up_a_valid;
  wire                            up_valid_out;
  wire                            up_b_wr_en;

  reg                             down_start;
  reg                             down_a_valid;
  wire                            down_valid_out;
  wire                            down_b_wr_en;

  wire [DATA_WIDTH*HEAD_DIM-1:0]  gate_result;
  wire [DATA_WIDTH*HEAD_DIM-1:0]  up_result;
  wire [DATA_WIDTH*HEAD_DIM-1:0]  down_result;

  // SwiGLU intermediate
  reg  [DATA_WIDTH*HEAD_DIM-1:0]  swiglu_vec;
  reg                             swiglu_valid;
  reg                             swiglu_pending;
  reg  [3:0]                      load_cnt;
  reg  [DATA_WIDTH*PE_COLS-1:0]   a_slice;

  integer                         i;
  reg signed [15:0]               up_elem;
  reg signed [15:0]               gate_elem;
  reg signed [15:0]               sig;
  reg signed [15:0]               silu_elem;
  reg signed [15:0]               swiglu_elem;
  reg signed [31:0]               silu_mul;
  reg signed [31:0]               swiglu_mul;
  reg                             gate_done;
  reg                             up_done;

  // FSM states
  localparam [2:0] F_IDLE    = 3'd0;
  localparam [2:0] F_GATE_UP = 3'd1;
  localparam [2:0] F_SWIGLU  = 3'd2;
  localparam [2:0] F_DOWN    = 3'd3;
  localparam [2:0] F_DONE    = 3'd4;
  reg [2:0] state;

  // b_wr routing
  assign gate_b_wr_en = b_wr_en && (b_wr_sel == 2'd0);
  assign up_b_wr_en   = b_wr_en && (b_wr_sel == 2'd1);
  assign down_b_wr_en = b_wr_en && (b_wr_sel == 2'd2);

  gemm_engine #(
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) u_gate (
    .clk(clk),
    .rst_n(rst_n),
    .start(gate_start),
    .m_size(7'd1),
    .n_size(7'd64),
    .a_valid(gate_a_valid),
    .a_data(a_slice),
    .b_wr_en(gate_b_wr_en),
    .b_wr_col(b_wr_col),
    .b_wr_data(b_wr_data),
    .valid_out(gate_valid_out),
    .result_out(gate_result)
  );

  gemm_engine #(
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) u_up (
    .clk(clk),
    .rst_n(rst_n),
    .start(up_start),
    .m_size(7'd1),
    .n_size(7'd64),
    .a_valid(up_a_valid),
    .a_data(a_slice),
    .b_wr_en(up_b_wr_en),
    .b_wr_col(b_wr_col),
    .b_wr_data(b_wr_data),
    .valid_out(up_valid_out),
    .result_out(up_result)
  );

  gemm_engine #(
    .HEAD_DIM(HEAD_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS)
  ) u_down (
    .clk(clk),
    .rst_n(rst_n),
    .start(down_start),
    .m_size(7'd1),
    .n_size(7'd64),
    .a_valid(down_a_valid),
    .a_data(a_slice),
    .b_wr_en(down_b_wr_en),
    .b_wr_col(b_wr_col),
    .b_wr_data(b_wr_data),
    .valid_out(down_valid_out),
    .result_out(down_result)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= F_IDLE;
      gate_start    <= 1'b0;
      up_start      <= 1'b0;
      down_start    <= 1'b0;
      gate_a_valid  <= 1'b0;
      up_a_valid    <= 1'b0;
      down_a_valid  <= 1'b0;
      swiglu_vec    <= {DATA_WIDTH*HEAD_DIM{1'b0}};
      swiglu_valid  <= 1'b0;
      swiglu_pending<= 1'b0;
      load_cnt      <= 4'd0;
      a_slice       <= {(DATA_WIDTH*PE_COLS){1'b0}};
      gate_done     <= 1'b0;
      up_done       <= 1'b0;
      valid_out     <= 1'b0;
      vec_out       <= {DATA_WIDTH*HEAD_DIM{1'b0}};
    end else begin
      gate_start   <= 1'b0;
      up_start     <= 1'b0;
      down_start   <= 1'b0;
      gate_a_valid <= 1'b0;
      up_a_valid   <= 1'b0;
      down_a_valid <= 1'b0;
      swiglu_valid <= 1'b0;
      valid_out    <= 1'b0;
      if (swiglu_pending) begin
        swiglu_valid   <= 1'b1;
        swiglu_pending <= 1'b0;
      end

      case (state)
        F_IDLE: begin
          if (start) begin
            gate_start <= 1'b1;
            up_start   <= 1'b1;
            load_cnt   <= 4'd0;
            gate_done  <= 1'b0;
            up_done    <= 1'b0;
            state      <= F_GATE_UP;
          end
        end

        F_GATE_UP: begin
          if (gate_valid_out)
            gate_done <= 1'b1;
          if (up_valid_out)
            up_done <= 1'b1;
          if (load_cnt <= 4'd7) begin
            gate_a_valid <= 1'b1;
            up_a_valid   <= 1'b1;
            a_slice      <= vec_in[(load_cnt*PE_COLS*DATA_WIDTH) +: (PE_COLS*DATA_WIDTH)];
            if (load_cnt == 4'd7)
              load_cnt <= 4'd8;
            else
              load_cnt <= load_cnt + 4'd1;
          end else if (gate_done && up_done) begin
            load_cnt <= 4'd0;
            state    <= F_SWIGLU;
          end
        end

        F_SWIGLU: begin
          for (i = 0; i < HEAD_DIM; i = i + 1) begin
            up_elem   = up_result[i*DATA_WIDTH +: DATA_WIDTH];
            gate_elem = gate_result[i*DATA_WIDTH +: DATA_WIDTH];

            if ($signed(up_elem) >= $signed(16'h0300))
              sig = 16'h7FFF;
            else if ($signed(up_elem) <= $signed(16'hFD00))
              sig = 16'h0001;
            else if (up_elem[15])
              sig = 16'h3000;
            else if (!up_elem[15] && (up_elem[14:13] == 2'b00))
              sig = 16'h5000;
            else
              sig = 16'h7000;

            silu_mul   = $signed(up_elem) * $signed(sig);
            silu_elem  = silu_mul[30:15];
            swiglu_mul = $signed(gate_elem) * $signed(silu_elem);
            swiglu_elem = swiglu_mul[23:8];

            swiglu_vec[i*DATA_WIDTH +: DATA_WIDTH] <= swiglu_elem;
          end
          swiglu_pending <= 1'b1;
          down_start     <= 1'b1;
          load_cnt       <= 4'd0;
          state          <= F_DOWN;
        end

        F_DOWN: begin
          if (load_cnt <= 4'd7) begin
            down_a_valid <= 1'b1;
            a_slice      <= swiglu_vec[(load_cnt*PE_COLS*DATA_WIDTH) +: (PE_COLS*DATA_WIDTH)];
            if (load_cnt == 4'd7)
              load_cnt <= 4'd8;
            else
              load_cnt <= load_cnt + 4'd1;
          end else if (down_valid_out)
            state <= F_DONE;
        end

        F_DONE: begin
          valid_out <= 1'b1;
          for (i = 0; i < HEAD_DIM; i = i + 1)
            vec_out[i*DATA_WIDTH +: DATA_WIDTH] <= $signed(down_result[i*DATA_WIDTH +: DATA_WIDTH]) <<< 3;
          state     <= F_IDLE;
        end

        default: begin
          state <= F_IDLE;
        end
      endcase
    end
  end

endmodule
