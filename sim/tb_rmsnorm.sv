`timescale 1ns/1ps

module tb_rmsnorm;

    localparam HEAD_DIM  = 64;
    localparam DATA_WIDTH = 16;

    logic clk    = 1'b0;
    logic rst_n  = 1'b0;
    logic [DATA_WIDTH*HEAD_DIM-1:0] vec_in;
    logic [DATA_WIDTH*HEAD_DIM-1:0] scale_in;
    logic valid_in = 1'b0;
    logic [DATA_WIDTH*HEAD_DIM-1:0] vec_out;
    logic valid_out;

    integer fail_count;

    always #5 clk = ~clk;

    rmsnorm_engine #(
        .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .vec_in   (vec_in),
        .scale_in (scale_in),
        .valid_in (valid_in),
        .vec_out  (vec_out),
        .valid_out(valid_out)
    );

    task automatic fill_vec;
        input [15:0] val;
        integer k;
        begin
            for (k = 0; k < HEAD_DIM; k = k + 1)
                vec_in[DATA_WIDTH*k +: DATA_WIDTH] = val;
        end
    endtask

    task automatic fill_scale_uniform;
        input [15:0] val;
        integer k;
        begin
            for (k = 0; k < HEAD_DIM; k = k + 1)
                scale_in[DATA_WIDTH*k +: DATA_WIDTH] = val;
        end
    endtask

    task automatic fill_alt_vec;
        input [15:0] val_even;
        input [15:0] val_odd;
        integer k;
        begin
            for (k = 0; k < HEAD_DIM; k = k + 1)
                vec_in[DATA_WIDTH*k +: DATA_WIDTH] = (k[0] == 0) ? val_even : val_odd;
        end
    endtask

    // Pulse valid_in for one cycle, then wait 5 cycles sampling valid_out each cycle.
    // Returns 1 if valid_out was seen high at least once during the 5-cycle window.
    task automatic pulse_and_wait;
        output logic valid_seen;
        integer c;
        begin
            valid_seen = 1'b0;
            @(posedge clk); #1;
            valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0;
            for (c = 0; c < 5; c = c + 1) begin
                @(posedge clk); #1;
                if (valid_out) valid_seen = 1'b1;
            end
        end
    endtask

    task automatic check_range_all;
        input [15:0] lo;
        input [15:0] hi;
        output logic pass;
        integer k;
        logic [15:0] elem;
        begin
            pass = 1'b1;
            for (k = 0; k < HEAD_DIM; k = k + 1) begin
                elem = vec_out[DATA_WIDTH*k +: DATA_WIDTH];
                if (elem < lo || elem > hi) pass = 1'b0;
            end
        end
    endtask

    initial begin : stim
        logic pass;
        logic vok;

        fail_count = 0;
        vec_in    = {(DATA_WIDTH*HEAD_DIM){1'b0}};
        scale_in  = {(DATA_WIDTH*HEAD_DIM){1'b0}};
        valid_in  = 1'b0;

        repeat (5) @(posedge clk);
        #1;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;

        // Test 1: all x = 0x0080 (0.5 in Q8.8), gamma = 0x0100 (1.0 in Q8.8)
        // Expected output: ~0x0080 (normalised; rms_inv clips to Q1.15 max = 1.0)
        fill_vec(16'h0080);
        fill_scale_uniform(16'h0100);
        pulse_and_wait(vok);
        if (!vok) begin
            $display("[RMSN %0t] CHECK FAIL: test1 valid_out never asserted in 5-cycle window",
                     $time);
            fail_count = fail_count + 1;
        end
        check_range_all(16'h0070, 16'h0090, pass);
        if (pass)
            $display("[RMSN %0t] CHECK PASS: test1 all outputs in [0070,0090], elem0=%04h",
                     $time, vec_out[15:0]);
        else begin
            $display("[RMSN %0t] CHECK FAIL: test1 out of range, elem0=%04h expected [0070,0090]",
                     $time, vec_out[15:0]);
            fail_count = fail_count + 1;
        end

        // Test 2: alternating 0x0100 / 0x0080, gamma = 0x0100
        fill_alt_vec(16'h0100, 16'h0080);
        fill_scale_uniform(16'h0100);
        pulse_and_wait(vok);
        if (vok)
            $display("[RMSN %0t] CHECK PASS: test2 valid_out seen, elem0=%04h elem1=%04h",
                     $time, vec_out[15:0], vec_out[31:16]);
        else begin
            $display("[RMSN %0t] CHECK FAIL: test2 valid_out never asserted", $time);
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display("RMSNORM SIM: PASS");
        else
            $display("RMSNORM SIM: FAIL");

        $finish;
    end

endmodule
