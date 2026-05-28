// rope_unit.v -- Rotary Position Embedding, 2-cycle pipeline
// Stage 1: latch vec + ROM cos/sin lookup for current token_pos
// Stage 2: Q8.8 x Q1.15 rotation per pair, keep bits[22:7]

module rope_unit #(
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire [DATA_WIDTH*HEAD_DIM-1:0] vec_in,
    input  wire [15:0]                    token_pos,
    input  wire                           valid_in,
    output reg  [DATA_WIDTH*HEAD_DIM-1:0] vec_out,
    output reg                            valid_out
);
    localparam PAIR_COUNT = HEAD_DIM / 2;   // 32
    localparam ROM_DEPTH  = 1024;           // 32 pairs x 16 pos x 2 (cos,sin)

    reg [15:0] rope_rom [0:ROM_DEPTH-1];
    initial $readmemh("rope_lut.mem", rope_rom);

    // Clamp position to LUT range [0,15]
    wire [3:0] pos = (token_pos > 16'd15) ? 4'd15 : token_pos[3:0];

    // Stage 1 registered vector and valid
    reg [DATA_WIDTH*HEAD_DIM-1:0] s1_vec;
    reg                           s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_vec    <= {(DATA_WIDTH*HEAD_DIM){1'b0}};
            s1_valid  <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            s1_vec    <= vec_in;
            s1_valid  <= valid_in;
            valid_out <= s1_valid;
        end
    end

    // One generate iteration per (xi, xi+1) pair
    genvar i;
    generate
        for (i = 0; i < PAIR_COUNT; i = i + 1) begin : g_pair

            // Stage 1: latch cos and sin from ROM
            reg [15:0] s1c;   // cos, Q1.15
            reg [15:0] s1s;   // sin, Q1.15

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1c <= 16'd0;
                    s1s <= 16'd0;
                end else begin
                    s1c <= rope_rom[{i[4:0], pos, 1'b0}];
                    s1s <= rope_rom[{i[4:0], pos, 1'b1}];
                end
            end

            // Stage 2: compute rotation (combinational) and register output
            // out0 = xi*cos - xi1*sin
            // out1 = xi*sin + xi1*cos
            wire signed [31:0] out0 =
                $signed(s1_vec[DATA_WIDTH*(2*i)   +: DATA_WIDTH]) * $signed(s1c) -
                $signed(s1_vec[DATA_WIDTH*(2*i+1) +: DATA_WIDTH]) * $signed(s1s);

            wire signed [31:0] out1 =
                $signed(s1_vec[DATA_WIDTH*(2*i)   +: DATA_WIDTH]) * $signed(s1s) +
                $signed(s1_vec[DATA_WIDTH*(2*i+1) +: DATA_WIDTH]) * $signed(s1c);

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    vec_out[DATA_WIDTH*(2*i)   +: DATA_WIDTH] <= 16'd0;
                    vec_out[DATA_WIDTH*(2*i+1) +: DATA_WIDTH] <= 16'd0;
                end else if (s1_valid) begin
                    vec_out[DATA_WIDTH*(2*i)   +: DATA_WIDTH] <= out0[30:15];
                    vec_out[DATA_WIDTH*(2*i+1) +: DATA_WIDTH] <= out1[30:15];
                end
            end

        end
    endgenerate

endmodule
