Set-Location "C:\Users\Anubhav Gupta\Desktop\Projects\circle_x1"

# Verify .mem files are accessible from project root
$memFiles = @(
    "src\rtl\rope_lut.mem",
    "src\rtl\exp_lut.mem",
    "src\rtl\rms_seed_lut.mem"
)
foreach ($f in $memFiles) {
    if (-not (Test-Path $f)) {
        Write-Host "ERROR: missing $f" -ForegroundColor Red
        exit 1
    }
}
Write-Host "MEM check: all .mem files present"

$files = @(
    "src/ip/qk_dot_engine.v",
    "src/ip/softmax_engine.v",
    "src/ip/score_scaler.v",
    "src/ip/v_accumulator.v",
    "src/ip/kv_cache_ctrl.v",
    "src/ip/block_table.v",
    "src/ip/block_allocator.v",
    "src/ip/rw_engine.v",
    "src/ip/axi4_lite_if.v",
    "src/ip/eviction_engine.v",
    "src/ip/prefetch_ctrl.v",
    "src/ip/attention_ctrl.v",
    "src/ip/spec_decode_ctrl.v",
    "src/ip/verify_ctrl.v",
    "src/ip/token_arbiter.v",
    "src/ip/kv_commit_ctrl.v",
    "src/ip/inference_sequencer.v",
    "src/rtl/rope_unit.v",
    "src/rtl/x1_kv_stream_adapter.v",
    "src/rtl/x1_q_stream_adapter.v",
    "src/rtl/x1_token_output.v",
    "src/rtl/rmsnorm_engine.v",
    "src/rtl/residual_adder.v",
    "src/rtl/gemm_engine.v",
    "src/rtl/ffn_engine.v",
    "src/rtl/layer_ctrl.v",
    "src/rtl/multihead_ctrl.v",
    "src/rtl/embedding_lut.v",
    "src/rtl/lm_head.v",
    "src/rtl/sampling_engine.v",
    "src/rtl/dma_engine.v",
    "src/rtl/x1_reg_ctrl.v",
    "src/rtl/circle_x1.v",
    "sim/e2e_tb.sv"
)

Write-Host "=== XVLOG ==="
& "D:\Vivado\2018.2\bin\xvlog.bat" --sv -i src/rtl -i src/ip @files
$xvlog_exit = $LASTEXITCODE
Write-Host "xvlog exit: $xvlog_exit"

if ($xvlog_exit -eq 0) {
    Write-Host "=== XELAB ==="
    & "D:\Vivado\2018.2\bin\xelab.bat" -debug typical e2e_tb -s e2e_sim
    $xelab_exit = $LASTEXITCODE
    Write-Host "xelab exit: $xelab_exit"

    if ($xelab_exit -eq 0) {
        Write-Host "=== XSIM ==="
        & "D:\Vivado\2018.2\bin\xsim.bat" e2e_sim --runall
        Write-Host "xsim exit: $LASTEXITCODE"
    }
}
