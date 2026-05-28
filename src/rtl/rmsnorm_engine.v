`timescale 1ns/1ps

module rmsnorm_engine #(
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire [DATA_WIDTH*HEAD_DIM-1:0] vec_in,
    input  wire [DATA_WIDTH*HEAD_DIM-1:0] scale_in,
    input  wire                          valid_in,
    output reg  [DATA_WIDTH*HEAD_DIM-1:0] vec_out,
    output reg                           valid_out
);

    localparam SEED_DEPTH = 64;

    reg [15:0] seed_rom [0:SEED_DEPTH-1];
    initial $readmemh("src/rtl/rms_seed_lut.mem", seed_rom);

    genvar g;
    integer i;

    wire signed [31:0] sq_raw [0:HEAD_DIM-1];
    generate
        for (g = 0; g < HEAD_DIM; g = g + 1) begin : gen_square
            assign sq_raw[g] = $signed(vec_in[DATA_WIDTH*g +: DATA_WIDTH]) *
                               $signed(vec_in[DATA_WIDTH*g +: DATA_WIDTH]);
        end
    endgenerate

    reg [31:0] sum_sq_comb;
    always @(*) begin
        sum_sq_comb = 32'd0;
        for (i = 0; i < HEAD_DIM; i = i + 1) begin
            sum_sq_comb = sum_sq_comb + {8'd0, sq_raw[i][23:8], 8'd0};
        end
    end

    reg [DATA_WIDTH*HEAD_DIM-1:0] s1_vec;
    reg [DATA_WIDTH*HEAD_DIM-1:0] s1_scale;
    reg [31:0]                    s1_mean;
    reg                           s1_valid;
    reg                           s1_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_vec   <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
            s1_scale <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
            s1_mean  <= 32'd0;
            s1_valid <= 1'b0;
            s1_zero  <= 1'b0;
        end else begin
            s1_vec   <= vec_in;
            s1_scale <= scale_in;
            s1_mean  <= sum_sq_comb / HEAD_DIM;
            s1_valid <= valid_in;
            s1_zero  <= (sum_sq_comb == 32'd0);
        end
    end

    wire [5:0] lut_idx = (s1_mean[21:16] > 6'd63) ? 6'd63 : s1_mean[21:16];
    wire [15:0] x0 = seed_rom[lut_idx];

    wire [31:0] x0_sq_raw = x0 * x0;
    wire [15:0] x0_sq = x0_sq_raw[30:15];
    wire [47:0] mean_term_raw = s1_mean * x0_sq;
    wire [17:0] mean_term = mean_term_raw[33:16];
    wire [17:0] half_term = mean_term >> 1;
    wire [17:0] correction = (half_term >= 18'h0C000) ? 18'd0 : (18'h0C000 - half_term);
    wire [33:0] x1_raw = x0 * correction;
    wire [18:0] x1_wide = x1_raw[33:15];
    wire [15:0] x1 = (x1_wide > 19'h07FFF) ? 16'h7FFF : x1_wide[15:0];

    reg [DATA_WIDTH*HEAD_DIM-1:0] s2_vec;
    reg [DATA_WIDTH*HEAD_DIM-1:0] s2_scale;
    reg [15:0]                    s2_rsqrt;
    reg                           s2_valid;
    reg                           s2_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_vec    <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
            s2_scale  <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
            s2_rsqrt  <= 16'd0;
            s2_valid  <= 1'b0;
            s2_zero   <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            s2_vec    <= s1_vec;
            s2_scale  <= s1_scale;
            s2_rsqrt  <= s1_zero ? 16'h7FFF : x1;
            s2_valid  <= s1_valid;
            s2_zero   <= s1_zero;
            valid_out <= s2_valid;
        end
    end

    generate
        for (g = 0; g < HEAD_DIM; g = g + 1) begin : gen_scale
            wire signed [31:0] norm_raw = $signed(s2_vec[DATA_WIDTH*g +: DATA_WIDTH]) *
                                          $signed({1'b0, s2_rsqrt[14:0]});
            wire signed [15:0] norm_q8_8 = norm_raw[30:15];
            wire signed [31:0] scale_raw = $signed(norm_q8_8) *
                                           $signed(s2_scale[DATA_WIDTH*g +: DATA_WIDTH]);

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    vec_out[DATA_WIDTH*g +: DATA_WIDTH] <= 16'd0;
                end else if (s2_valid) begin
                    vec_out[DATA_WIDTH*g +: DATA_WIDTH] <= s2_zero ? 16'd0 : scale_raw[23:8];
                end
            end
        end
    endgenerate

endmodule
