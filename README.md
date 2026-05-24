# Circle X1

**Speculative-decode LLM inference accelerator in synthesisable SystemVerilog.**

Circle X1 integrates three subsystems — a pipelined KV cache (Vera), a multi-head attention engine (Kael), and a speculative decode sequencer (AIS) — behind a single AXI4-Lite control port and a pair of AXI4-Stream data ports. The host writes a handful of registers, streams Q vectors and KV pairs, and receives accepted tokens on an output stream.

Target: **Artix-7 xc7a35tcpg236-1** · Toolchain: **Vivado 2018.2 / xsim**

---

## Repository layout

```
circle_x1/
  src/
    rtl/          circle_x1 top-level and stream adapters
    ip/           local copies of Vera, Kael, AIS submodule RTL
  sim/            testbenches
  scripts/        TCL project scripts

../vera/rtl/      KV cache controller (Vera)
../kael/rtl/      Attention engine (Kael)
../ais/rtl/       Inference sequencer (AIS)
```

---

## Architecture

```
         AXI4-Lite slave (12-bit addr)
                  │
           x1_reg_ctrl
          ╱       │       ╲
    infer_start  regs    intr
         │
  inference_sequencer  ◄──── AIS
    │        │       │
    │   spec_decode  │
    │   verify_ctrl  │
    │  token_arbiter │
    │  kv_commit_ctrl│
    │                │
  Kael (attention) Vera (KV cache)
    │                │
  q/ctx buses    wr/rd/evict buses
         │
  x1_token_output
         │
  AXI4-Stream token out
```

### Vera — KV cache controller
Manages a paged KV store (256 pages × 16 tokens/page = 4096 token capacity per session). Handles write, read, prefetch, and page-granular eviction. Accepts an AXI4-Lite management port and direct KV read/write buses.

| File | Purpose |
|---|---|
| `kv_cache_ctrl.v` | Top-level, arbitrates read/write/evict |
| `block_table.v` | Session → page mapping table |
| `block_allocator.v` | Free-page allocation and release |
| `rw_engine.v` | SRAM read/write sequencer |
| `prefetch_ctrl.v` | Read-ahead controller |
| `eviction_engine.v` | Page eviction on rollback |
| `axi4_lite_if.v` | AXI4-Lite slave port |

### Kael — Attention engine
Computes scaled dot-product attention for up to 8 batches in parallel. Reads K/V from Vera, computes Q·K scores, applies softmax, accumulates V context, and streams the result back to AIS.

| File | Purpose |
|---|---|
| `attention_ctrl.v` | Orchestrates the pipeline |
| `qk_dot_engine.v` | Q·K dot product |
| `score_scaler.v` | Scale by 1/√d |
| `softmax_engine.v` | Row-wise softmax (LUT-based exp) |
| `v_accumulator.v` | Weighted V accumulation |

`softmax_engine` loads `rtl/exp_lut.mem` at simulation time (see [Simulation](#simulation)).

### AIS — Agentic Inference Subsystem
Runs the full speculative decode loop: draft → verify → arbitrate → commit.

| File | Purpose |
|---|---|
| `inference_sequencer.v` | Top-level FSM (IDLE→PREFILL→SPEC_DRAFT→VERIFY→ARBITRATE→COMMIT→DONE) |
| `spec_decode_ctrl.v` | Issues draft Q vectors, waits for candidate batch |
| `verify_ctrl.v` | Runs attention on all candidates + target |
| `token_arbiter.v` | Picks the first accepted draft or the target token |
| `kv_commit_ctrl.v` | Writes accepted KV pairs; evicts speculative pages on rollback |

### Circle X1 — top-level
Wires the three subsystems together and exposes clean AXI interfaces to the host.

| File | Purpose |
|---|---|
| `circle_x1.v` | Top-level instantiation |
| `x1_reg_ctrl.v` | AXI4-Lite register file + Vera proxy master |
| `x1_q_stream_adapter.v` | AXI4-Stream Q input → AIS draft_q bus |
| `x1_kv_stream_adapter.v` | AXI4-Stream KV input → AIS commit_kv bus |
| `x1_token_output.v` | AIS token_valid → AXI4-Stream output |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `TOTAL_PAGES` | 256 | KV cache pages (shared across sessions) |
| `PAGE_SIZE_TOKENS` | 16 | Tokens per page |
| `HEAD_DIM` | 64 | Attention head dimension |
| `NUM_SESSIONS` | 8 | Concurrent sessions |
| `DATA_WIDTH` | 16 | Fixed-point word width (Q8.8 inputs, Q1.15 scores) |
| `SRAM_BANKS` | 4 | Vera SRAM bank count |
| `MAX_BATCH` | 8 | Max speculative candidates + target |
| `AXI_ADDR_WIDTH` | 12 | AXI4-Lite address bits |
| `AXI_DATA_WIDTH` | 32 | AXI4-Lite data bits |

---

## Register map

All registers are 32-bit, word-aligned. Address bit [8] routes writes/reads to Vera's internal AXI4-Lite port.

| Address | Name | Access | Description |
|---|---|---|---|
| `0x000` | CTRL | W | Bit [0]: write 1 to launch inference (auto-clears) |
| `0x004` | STATUS | R | [0] infer_busy · [1] infer_done · [4:2] ais_state |
| `0x008` | INTR_STATUS | R/W1C | [0] done interrupt pending; write 1 to clear |
| `0x00C` | INTR_ENABLE | R/W | [0] enable done interrupt |
| `0x010` | SESSION_ID | R/W | Target session (0–7) |
| `0x014` | PROMPT_LEN | R/W | KV tail position at inference start |
| `0x018` | SPEC_K | R/W | Number of draft candidates (1–7) |
| `0x01C` | MAX_NEW_TOKENS | R/W | Stop after this many accepted tokens |
| `0x020` | GENERATED_TOKEN | R | Most recently accepted token ID |
| `0x024` | TOKEN_COUNT | R | Cumulative accepted token count |
| `0x028` | TARGET_TOKEN_ID | R/W | Verifier's ground-truth token |
| `0x02C–0x044` | DRAFT_TOKEN_0–6 | R/W | Speculative candidate token IDs |

---

## External ports

### AXI4-Lite slave (`s_axil_*`)
Standard 5-channel AXI4-Lite at `AXI_ADDR_WIDTH`/`AXI_DATA_WIDTH`. Used for all register reads and writes.

### AXI4-Stream Q input (`s_axis_q_*`)

| Signal | Width | Description |
|---|---|---|
| `s_axis_q_tdata` | 16 | Q element value |
| `s_axis_q_taddr` | 6 | Element index within the head (0–63) |
| `s_axis_q_tbatch` | 3 | Batch index (0 = draft candidate 0, …, spec_k = target) |
| `s_axis_q_tvalid` | 1 | |
| `s_axis_q_tready` | 1 | Always asserted (no backpressure) |

Stream one complete Q vector (64 words) per batch, for all `spec_k + 1` batches, after writing `CTRL[0]=1`.

### AXI4-Stream KV input (`s_axis_kv_*`)

| Signal | Width | Description |
|---|---|---|
| `s_axis_kv_k_tdata` | 16 | Key element |
| `s_axis_kv_v_tdata` | 16 | Value element |
| `s_axis_kv_token_idx` | 16 | Token position (lower 3 bits used as commit index) |
| `s_axis_kv_tvalid` | 1 | |
| `s_axis_kv_tready` | 1 | Always asserted |

Stream accepted KV pairs during the commit window (while AIS is in S_COMMIT).

### AXI4-Stream token output (`m_axis_token_*`)

| Signal | Width | Description |
|---|---|---|
| `m_axis_token_tdata` | 16 | Accepted token ID |
| `m_axis_token_tvalid` | 1 | One-cycle pulse per accepted token |
| `m_axis_token_tready` | 1 | Host flow-control |

### Interrupt
`intr` is a level signal asserted when inference completes and `INTR_ENABLE[0]` is set. Deasserts one cycle after the host writes 1 to `INTR_STATUS[0]`.

---

## Host usage sequence

```
1. Write SESSION_ID, PROMPT_LEN, SPEC_K, MAX_NEW_TOKENS
2. Write TARGET_TOKEN_ID, DRAFT_TOKEN_0 .. DRAFT_TOKEN_{SPEC_K-1}
3. Write CTRL[0] = 1                     // launch
4. Stream Q vectors: batch 0, 1, ..., SPEC_K  (64 words each)
5. Stream KV pairs for accepted tokens during S_COMMIT
6. Poll STATUS[1] (infer_done) or wait for intr
7. Read GENERATED_TOKEN, TOKEN_COUNT
8. If INTR_ENABLE[0]: write 1 to INTR_STATUS[0] to clear
9. Repeat from step 1 for next round
```

---

## Simulation

### Prerequisites
- Vivado 2018.2 on PATH (`set PATH=D:\Vivado\2018.2\bin;%PATH%` on Windows)
- Run all commands from `circle_x1/` so relative paths resolve correctly
- The softmax LUT must be visible as `rtl/exp_lut.mem` relative to the working directory:

```cmd
mkdir rtl
copy ..\kael\rtl\exp_lut.mem rtl\
```

### Compile

```cmd
xvlog --sv ^
  "..\vera\rtl\axi4_lite_if.v" ^
  "..\vera\rtl\block_allocator.v" ^
  "..\vera\rtl\block_table.v" ^
  "..\vera\rtl\eviction_engine.v" ^
  "..\vera\rtl\kv_cache_ctrl.v" ^
  "..\vera\rtl\prefetch_ctrl.v" ^
  "..\vera\rtl\rw_engine.v" ^
  "..\kael\rtl\attention_ctrl.v" ^
  "..\kael\rtl\qk_dot_engine.v" ^
  "..\kael\rtl\score_scaler.v" ^
  "..\kael\rtl\softmax_engine.v" ^
  "..\kael\rtl\v_accumulator.v" ^
  "..\ais\rtl\inference_sequencer.v" ^
  "..\ais\rtl\kv_commit_ctrl.v" ^
  "..\ais\rtl\spec_decode_ctrl.v" ^
  "..\ais\rtl\token_arbiter.v" ^
  "..\ais\rtl\verify_ctrl.v" ^
  "src\rtl\circle_x1.v" ^
  "src\rtl\x1_kv_stream_adapter.v" ^
  "src\rtl\x1_q_stream_adapter.v" ^
  "src\rtl\x1_reg_ctrl.v" ^
  "src\rtl\x1_token_output.v" ^
  "sim\circle_x1_integration_tb.v"
```

### Elaborate

```cmd
xelab -debug typical ^
  --top circle_x1_integration_tb ^
  --snapshot circle_x1_integ_sim ^
  -L xil_defaultlib
```

### Simulate

```cmd
xsim circle_x1_integ_sim --runall
```

Expected output:

```
DEBUG: reset released
DEBUG: C1 reads done
INTEG PASS: INTEG_C1_boot
DEBUG: C2 config done
DEBUG: C2 launched
DEBUG: C2 q streamed
DEBUG: C2 kv streamed
DEBUG: C2 waiting infer_done
INTEG PASS: INTEG_C2_single_round
INTEG PASS: INTEG_C3_intr_end_to_end
3/3 circle_x1 integration checks passing
```

### Integration checks

| Check | What it verifies |
|---|---|
| `INTEG_C1_boot` | All registers read back reset defaults (zero) after deasserting rst_n |
| `INTEG_C2_single_round` | Full speculative decode round: GENERATED_TOKEN non-zero, TOKEN_COUNT ≥ 1, m_axis_token_tvalid pulsed |
| `INTEG_C3_intr_end_to_end` | Interrupt asserted after infer_done, INTR_STATUS[0] set, clears on W1C write |

A 200 ms sim-time hard timeout is wired in the testbench; xsim will always exit even if the DUT hangs.

---

## Design notes

**Fixed-point format** — inputs are Q8.8 (8 integer + 8 fractional bits). Attention scores are Q1.15. Division by `PAGE_SIZE_TOKENS` (16) is implemented as a 4-bit right shift; no hardware divider is instantiated.

**Flat ports** — no array ports anywhere in the design. Each draft token and each data bus is a discrete signal. This is required for clean elaboration in xsim 2018.2.

**Single-cycle infer_done** — `infer_done` is a one-clock pulse from `inference_sequencer`. The `x1_reg_ctrl` STATUS register exposes it directly. Polling software must either read fast enough to catch it or watch `infer_busy` transition 1→0 (which is level-held and always observable).

**KV eviction** — rollback is page-granular. `kv_commit_ctrl` evicts every page in the range `[rollback_token_pos >> 4 .. spec_tail_pos >> 4]` in ascending order, one `evict_valid/evict_ack` handshake per page.

**exp_lut.mem** — `softmax_engine` loads this file with `$readmemh` using the relative path `rtl/exp_lut.mem`. The file must exist relative to the xsim working directory at simulation time; it is not needed for synthesis.
