Set-Location "C:\Users\Anubhav Gupta\Desktop\Projects\circle_x1"

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
    "src/rtl/x1_reg_ctrl.v",
    "src/rtl/circle_x1.v",
    "sim/circle_x1_tb.sv"
)

Write-Host "=== XVLOG ==="
& "D:\Vivado\2018.2\bin\xvlog.bat" --sv -i src/rtl -i src/ip @files
$xvlog_exit = $LASTEXITCODE
Write-Host "xvlog exit: $xvlog_exit"

if ($xvlog_exit -eq 0) {
    Write-Host "=== XELAB ==="
    & "D:\Vivado\2018.2\bin\xelab.bat" -debug typical circle_x1_tb -s circle_x1_tb_sim
    $xelab_exit = $LASTEXITCODE
    Write-Host "xelab exit: $xelab_exit"

    if ($xelab_exit -eq 0) {
        Write-Host "=== XSIM ==="
        & "D:\Vivado\2018.2\bin\xsim.bat" circle_x1_tb_sim --runall
        Write-Host "xsim exit: $LASTEXITCODE"
    }
}
