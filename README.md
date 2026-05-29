# Circle X1

**Speculative-decode LLM inference accelerator — synthesisable SystemVerilog targeting Skywater 130nm.**

Circle X1 is a complete hardware inference subsystem that implements speculative decoding for large language models. It integrates three tightly coupled engines — a paged KV cache (Vera), a multi-head attention pipeline (Kael), and a speculative decode sequencer (AIS) — behind a single AXI4-Lite control port and a pair of AXI4-Stream data ports. The host writes a handful of registers, streams Q vectors and KV pairs, and receives accepted tokens on an output stream.

---

## Status

| Check | Result |
|---|---|
| `CIRCLE X1 SIM: PASS` | Full speculative decode pipeline, all named checks |
| `CIRCLE X1 E2E: PASS` | Embedding → sampling end-to-end pipeline |
| Synthesis prep | Clean for Yosys: no `$display`, BRAM attributes applied, KV buses widened |

---

## Target

| Item | Value |
|---|---|
| Technology | Skywater 130nm (OpenROAD flow) |
| Development target | Artix-7 `xc7a35tcpg236-1` |
| Simulator | Xilinx xsim (Vivado 2018.2) |
| Language | SystemVerilog (.v extension, flat port style) |

---

## Repository layout

```
circle_x1/
├── src/
│   ├── rtl/                Circle X1 top-level and stream adapters
│   │   ├── circle_x1.v         Top-level integration module
│   │   ├── x1_reg_ctrl.v       AXI4-Lite register file + Vera proxy master
│   │   ├── x1_q_stream_adapter.v   AXI4-Stream Q → AIS draft_q bus
│   │   ├── x1_kv_stream_adapter.v  AXI4-Stream KV → AIS commit_kv bus
│   │   ├── x1_token_output.v   AIS accepted token → AXI4-Stream output
│   │   ├── embedding_lut.v     Vocabulary embedding lookup (BRAM)
│   │   ├── lm_head.v           Language model head projection (BRAM)
│   │   ├── gemm_engine.v       General matrix-multiply engine
│   │   ├── ffn_engine.v        Feed-forward network engine
│   │   ├── layer_ctrl.v        Transformer layer controller
│   │   ├── multihead_ctrl.v    Multi-head attention controller
│   │   ├── rmsnorm_engine.v    RMS normalisation
│   │   ├── residual_adder.v    Residual addition
│   │   ├── rope_unit.v         RoPE positional encoding (LUT-based)
│   │   ├── sampling_engine.v   Top-p / argmax token sampling
│   │   ├── dma_engine.v        DMA weight loader
│   │   ├── exp_lut.mem         Q8.8 exponential LUT (256 entries)
│   │   ├── rope_lut.mem        RoPE sincos LUT (512 entries × 16-bit)
│   │   └── rms_seed_lut.mem    RMSNorm seed LUT (64 entries × 16-bit)
│   └── ip/                 Subsystem IP blocks
│       ├── attention_ctrl.v    Kael: attention pipeline controller
│       ├── qk_dot_engine.v     Kael: Q·K dot product
│       ├── score_scaler.v      Kael: scale by 1/√d
│       ├── softmax_engine.v    Kael: row-wise online softmax
│       ├── v_accumulator.v     Kael: weighted V accumulation
│       ├── kv_cache_ctrl.v     Vera: KV cache top-level
│       ├── block_table.v       Vera: session → page mapping
│       ├── block_allocator.v   Vera: free-page allocator
│       ├── rw_engine.v         Vera: SRAM read/write sequencer
│       ├── prefetch_ctrl.v     Vera: read-ahead prefetch controller
│       ├── eviction_engine.v   Vera: page eviction on rollback
│       ├── axi4_lite_if.v      Vera: AXI4-Lite slave port
│       ├── inference_sequencer.v   AIS: top-level FSM
│       ├── spec_decode_ctrl.v  AIS: speculative draft controller
│       ├── verify_ctrl.v       AIS: candidate verification
│       ├── token_arbiter.v     AIS: accept/reject arbiter
│       └── kv_commit_ctrl.v    AIS: KV write-back and rollback
├── sim/
│   ├── circle_x1_tb.sv         Main integration testbench (SIM)
│   ├── e2e_tb.sv                End-to-end pipeline testbench (E2E)
│   ├── circle_x1_integration_tb.v  AXI4-Lite register-level integration TB
│   ├── tb_rmsnorm.sv            Unit TB: RMSNorm engine
│   ├── tb_residual_adder.sv     Unit TB: residual adder
│   ├── tb_gemm.sv               Unit TB: GEMM engine
│   ├── tb_ffn.sv                Unit TB: FFN engine
│   ├── tb_layer_ctrl.sv         Unit TB: layer controller
│   ├── tb_multihead_ctrl.sv     Unit TB: multi-head controller
│   ├── tb_embedding_lut.sv      Unit TB: embedding lookup
│   ├── tb_lm_head.sv            Unit TB: LM head
│   ├── tb_sampling_engine.sv    Unit TB: sampling engine
│   └── tb_dma_engine.sv         Unit TB: DMA engine
└── scripts/
    ├── run_sim.ps1              Compile + simulate (SIM testbench)
    ├── run_e2e.ps1              Compile + simulate (E2E testbench)
    ├── setup_circle_x1.tcl     Vivado project TCL script
    ├── gen_rope_lut.py          Generate rope_lut.mem
    └── gen_rms_seed_lut.py      Generate rms_seed_lut.mem
```

---

## Architecture

```
                     Host
                      │
          ┌───────────┴────────────┐
          │      AXI4-Lite slave   │
          │      x1_reg_ctrl       │
          │  (register file +      │
          │   Vera AXI4-L proxy)   │
          └───────────┬────────────┘
                      │ infer_start / registers
                      │
          ┌───────────▼────────────────────────────┐
          │         inference_sequencer (AIS)       │
          │  IDLE → PREFILL → SPEC_DRAFT →          │
          │  VERIFY → ARBITRATE → COMMIT → DONE     │
          │                                         │
          │  ┌──────────────┐  ┌─────────────────┐  │
          │  │spec_decode_  │  │  verify_ctrl    │  │
          │  │ctrl          │  │                 │  │
          │  └──────────────┘  └─────────────────┘  │
          │  ┌──────────────┐  ┌─────────────────┐  │
          │  │token_arbiter │  │ kv_commit_ctrl  │  │
          │  └──────────────┘  └─────────────────┘  │
          └────────┬───────────────────┬────────────┘
                   │                   │
    ┌──────────────▼──────┐   ┌────────▼─────────────┐
    │    Kael              │   │    Vera               │
    │  (attention engine)  │   │  (KV cache ctrl)      │
    │                      │   │                       │
    │  attention_ctrl      │   │  kv_cache_ctrl        │
    │  qk_dot_engine       │◄──┤  block_table          │
    │  score_scaler        │   │  block_allocator      │
    │  softmax_engine      │   │  rw_engine            │
    │  v_accumulator       │   │  prefetch_ctrl        │
    └──────────┬───────────┘   │  eviction_engine      │
               │ attn_vec_out  │  axi4_lite_if         │
               │               └───────────────────────┘
    ┌──────────▼──────────────────────────────────────┐
    │        Full transformer layer pipeline           │
    │  embedding_lut → rmsnorm → multihead_ctrl →      │
    │  layer_ctrl → ffn_engine → lm_head →             │
    │  sampling_engine → x1_token_output               │
    └──────────────────────┬───────────────────────────┘
                           │ m_axis_token_*
                         Host

    ── AXI4-Stream Q input (s_axis_q_*) ──► x1_q_stream_adapter ──► AIS
    ── AXI4-Stream KV input (s_axis_kv_*) ► x1_kv_stream_adapter ──► AIS
```

---

## Subsystem descriptions

### Vera — KV cache controller

Vera manages a paged KV store with 256 pages × 16 tokens/page = **4096 token capacity per session**, shared across up to 8 concurrent sessions. Each token's key and value vectors are `DATA_WIDTH × HEAD_DIM` bits wide (1024 bits at defaults).

**Key features:**
- Page-granular allocation and eviction — no per-token free lists
- Speculative page rollback: evict all pages in `[rollback_pos >> 4 .. spec_tail >> 4]`
- Read prefetch controller reduces attention latency
- AXI4-Lite management port for direct page-table inspection

| Module | Purpose |
|---|---|
| `kv_cache_ctrl.v` | Top-level; arbitrates read / write / evict / prefetch |
| `block_table.v` | Session-indexed page mapping table |
| `block_allocator.v` | Free-page stack; O(1) alloc and release |
| `rw_engine.v` | SRAM bank sequencer; handles multi-bank interleaving |
| `prefetch_ctrl.v` | Issues speculative read-ahead requests |
| `eviction_engine.v` | Walks rollback range, issues eviction one page at a time |
| `axi4_lite_if.v` | AXI4-Lite slave; decodes read/write to internal registers |

---

### Kael — Attention engine

Kael computes scaled dot-product attention for up to 8 batches in parallel. It reads K/V vectors from Vera, computes Q·K scores, applies online softmax, accumulates the weighted V context, and streams the attention output back to AIS.

**Key features:**
- Pipelined: Q·K dot product → scale → softmax → V accumulate
- Online softmax using a precomputed `exp_lut.mem` (256-entry Q8.8 LUT)
- Handles `rd_busy` from Vera correctly — transitions on the falling edge, not the rising edge
- Configurable batch size up to `MAX_BATCH`

| Module | Purpose |
|---|---|
| `attention_ctrl.v` | FSM: IDLE → FETCH_KV → K_START → STREAM → OUTPUT |
| `qk_dot_engine.v` | Fixed-point Q·K dot product; output is Q1.15 |
| `score_scaler.v` | Multiply by 1/√HEAD_DIM (constant shift) |
| `softmax_engine.v` | Row-wise online softmax; loads `exp_lut.mem` at init |
| `v_accumulator.v` | Weighted sum of V vectors per batch |

---

### AIS — Agentic Inference Subsystem

AIS runs the full speculative decode loop. It issues draft Q vectors, waits for Kael to return attention results, arbitrates candidates against the target, commits accepted tokens to Vera, and rolls back speculative pages on rejection.

**Speculative decode flow:**

```
IDLE ──► PREFILL ──► SPEC_DRAFT ──► VERIFY ──► ARBITRATE ──► COMMIT ──► DONE
                         ▲                          │
                         └──────── rejected ────────┘
```

| Module | Purpose |
|---|---|
| `inference_sequencer.v` | Top-level FSM; owns all state transitions |
| `spec_decode_ctrl.v` | Issues draft Q vectors for each candidate batch |
| `verify_ctrl.v` | Runs attention on candidate + target; produces scored context |
| `token_arbiter.v` | Accepts first draft token matching target; handles tie-breaking (lowest index wins) |
| `kv_commit_ctrl.v` | Streams accepted KV pairs to Vera; evicts speculative pages on rollback |

**`kv_commit_ctrl` FSM:**

```
IDLE → WRITE (accepted_count > 0)
     → EVICT (accepted_count == 0 && rollback_needed)
     → DONE  (accepted_count == 0 && !rollback_needed)
WRITE → EVICT (all tokens written, rollback_needed)
      → DONE  (all tokens written, !rollback_needed)
EVICT → DONE  (all pages evicted)
DONE  → IDLE  (commit_done pulse)
```

---

### Circle X1 — top-level integration

`circle_x1.v` wires the three subsystems together and exposes clean AXI interfaces to the host. Stream adapters translate between the AXI4-Stream host interface and the internal flat-bus protocol used by AIS.

| Module | Purpose |
|---|---|
| `circle_x1.v` | Top-level instantiation and bus routing |
| `x1_reg_ctrl.v` | AXI4-Lite register file; proxies writes destined for Vera via an internal AXI4-Lite master |
| `x1_q_stream_adapter.v` | Unpacks AXI4-Stream Q beats into `draft_q_data / draft_q_addr / draft_q_batch_id` |
| `x1_kv_stream_adapter.v` | Unpacks AXI4-Stream KV beats into `commit_k_data / commit_v_data / commit_token_idx` |
| `x1_token_output.v` | Packs AIS `token_valid / token_id` into an AXI4-Stream beat |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `HEAD_DIM` | 64 | Attention head dimension (elements per K/V vector) |
| `DATA_WIDTH` | 16 | Fixed-point word width in bits |
| `MAX_BATCH` | 8 | Max speculative candidates + 1 target |
| `NUM_SESSIONS` | 8 | Concurrent KV cache sessions |
| `TOTAL_PAGES` | 256 | Total KV cache pages (shared across sessions) |
| `PAGE_SIZE_TOKENS` | 16 | Tokens per page (must be a power of 2) |
| `SRAM_BANKS` | 4 | Vera SRAM bank count |
| `VOCAB_SIZE` | 32000 | Vocabulary size (embedding LUT and LM head) |
| `AXI_ADDR_WIDTH` | 12 | AXI4-Lite address width |
| `AXI_DATA_WIDTH` | 32 | AXI4-Lite data width |

**KV bus width** = `DATA_WIDTH × HEAD_DIM` = 1024 bits at default parameters.

**KV cache capacity** = `TOTAL_PAGES × PAGE_SIZE_TOKENS` = 4096 tokens per session.

---

## Fixed-point number formats

| Signal class | Format | Notes |
|---|---|---|
| Q input vectors | Q8.8 | 8 integer + 8 fractional bits, signed |
| KV vectors | Q8.8 | Same format as Q; stored verbatim |
| Attention scores (Q·K) | Q1.15 | 1 integer + 15 fractional bits, signed |
| Softmax outputs | Q1.15 | Probability weights |
| LM head logits | Q8.8 | Pre-sampling |

Division by `PAGE_SIZE_TOKENS` (16) throughout the design is implemented as a 4-bit arithmetic right shift. No hardware divider is instantiated anywhere.

---

## Register map

All registers are 32-bit, word-aligned. The AXI4-Lite address space is 12 bits. Address bit [8] routes writes and reads to Vera's internal AXI4-Lite management port through the proxy master in `x1_reg_ctrl`.

| Address | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x000` | CTRL | W | `0x0` | Bit [0]: write 1 to launch inference; auto-clears on the next cycle |
| `0x004` | STATUS | R | `0x0` | [0] `infer_busy` · [1] `infer_done` · [4:2] `ais_state` encoding |
| `0x008` | INTR_STATUS | R/W1C | `0x0` | [0] inference-done interrupt pending; write 1 to clear |
| `0x00C` | INTR_ENABLE | R/W | `0x0` | [0] enable inference-done interrupt to `intr` output |
| `0x010` | SESSION_ID | R/W | `0x0` | Target session index (0–7) |
| `0x014` | PROMPT_LEN | R/W | `0x0` | KV tail position at inference start (= number of prefill tokens) |
| `0x018` | SPEC_K | R/W | `0x0` | Number of speculative draft candidates (1–7) |
| `0x01C` | MAX_NEW_TOKENS | R/W | `0x0` | Stop after this many accepted output tokens |
| `0x020` | GENERATED_TOKEN | R | `0x0` | Most recently accepted token ID |
| `0x024` | TOKEN_COUNT | R | `0x0` | Cumulative accepted token count since last CTRL write |
| `0x028` | TARGET_TOKEN_ID | R/W | `0x0` | Verifier ground-truth token (provided by host after verification) |
| `0x02C` | DRAFT_TOKEN_0 | R/W | `0x0` | Speculative candidate 0 token ID |
| `0x030` | DRAFT_TOKEN_1 | R/W | `0x0` | Speculative candidate 1 token ID |
| `0x034` | DRAFT_TOKEN_2 | R/W | `0x0` | Speculative candidate 2 token ID |
| `0x038` | DRAFT_TOKEN_3 | R/W | `0x0` | Speculative candidate 3 token ID |
| `0x03C` | DRAFT_TOKEN_4 | R/W | `0x0` | Speculative candidate 4 token ID |
| `0x040` | DRAFT_TOKEN_5 | R/W | `0x0` | Speculative candidate 5 token ID |
| `0x044` | DRAFT_TOKEN_6 | R/W | `0x0` | Speculative candidate 6 token ID |
| `0x100–0x1FF` | VERA_* | R/W | — | Vera internal registers (proxied via AXI4-Lite master in x1_reg_ctrl) |

**STATUS[4:2] AIS state encoding:**

| Value | State |
|---|---|
| `3'd0` | IDLE |
| `3'd1` | PREFILL |
| `3'd2` | SPEC_DRAFT |
| `3'd3` | VERIFY |
| `3'd4` | ARBITRATE |
| `3'd5` | COMMIT |
| `3'd6` | DONE |

---

## External port reference

### Clock and reset

| Port | Direction | Description |
|---|---|---|
| `clk` | input | System clock; all flops are positive-edge triggered |
| `rst_n` | input | Active-low synchronous reset |

### AXI4-Lite slave (`s_axil_*`)

Standard 5-channel AXI4-Lite at `AXI_ADDR_WIDTH` / `AXI_DATA_WIDTH`. Used for all register reads and writes including proxied Vera access.

| Port | Width | Direction | Description |
|---|---|---|---|
| `s_axil_awvalid` | 1 | input | Write address valid |
| `s_axil_awready` | 1 | output | Write address ready |
| `s_axil_awaddr` | 12 | input | Write address |
| `s_axil_wvalid` | 1 | input | Write data valid |
| `s_axil_wready` | 1 | output | Write data ready |
| `s_axil_wdata` | 32 | input | Write data |
| `s_axil_wstrb` | 4 | input | Write byte strobes |
| `s_axil_bvalid` | 1 | output | Write response valid |
| `s_axil_bready` | 1 | input | Write response ready |
| `s_axil_bresp` | 2 | output | Write response (always OKAY) |
| `s_axil_arvalid` | 1 | input | Read address valid |
| `s_axil_arready` | 1 | output | Read address ready |
| `s_axil_araddr` | 12 | input | Read address |
| `s_axil_rvalid` | 1 | output | Read data valid |
| `s_axil_rready` | 1 | input | Read data ready |
| `s_axil_rdata` | 32 | output | Read data |
| `s_axil_rresp` | 2 | output | Read response (always OKAY) |

### AXI4-Stream Q input (`s_axis_q_*`)

Carries one Q-vector element per beat. Stream 64 elements per batch (one complete Q vector), for all `SPEC_K + 1` batches, after asserting `CTRL[0] = 1`.

| Port | Width | Direction | Description |
|---|---|---|---|
| `s_axis_q_tdata` | 16 | input | Q element value (Q8.8) |
| `s_axis_q_taddr` | 6 | input | Element index within head (0–63) |
| `s_axis_q_tbatch` | 3 | input | Batch index (0 = draft candidate 0; SPEC_K = target) |
| `s_axis_q_tvalid` | 1 | input | Beat valid |
| `s_axis_q_tready` | 1 | output | Always asserted; no backpressure |

### AXI4-Stream KV input (`s_axis_kv_*`)

Carries accepted K/V pairs during the commit window (while AIS is in state S_COMMIT).

| Port | Width | Direction | Description |
|---|---|---|---|
| `s_axis_kv_k_tdata` | 16 | input | Key element (Q8.8) |
| `s_axis_kv_v_tdata` | 16 | input | Value element (Q8.8) |
| `s_axis_kv_token_idx` | 16 | input | Token position index (lower 3 bits used as commit index) |
| `s_axis_kv_tvalid` | 1 | input | Beat valid |
| `s_axis_kv_tready` | 1 | output | Always asserted |

### AXI4-Stream token output (`m_axis_token_*`)

Carries one accepted token ID per beat. Valid is a one-cycle pulse per accepted token.

| Port | Width | Direction | Description |
|---|---|---|---|
| `m_axis_token_tdata` | 16 | output | Accepted token ID |
| `m_axis_token_tvalid` | 1 | output | One-cycle pulse per token |
| `m_axis_token_tready` | 1 | input | Host flow-control |

### DRAM weight interface

| Port | Width | Direction | Description |
|---|---|---|---|
| `dram_addr` | 32 | output | Weight load address |
| `dram_data` | 1024 | input | Weight data bus (DATA_WIDTH × HEAD_DIM) |
| `dram_valid` | 1 | input | Data beat valid |
| `dram_req` | 1 | output | Request strobe |

### Miscellaneous

| Port | Width | Direction | Description |
|---|---|---|---|
| `intr` | 1 | output | Level interrupt; asserted when inference completes and INTR_ENABLE[0] is set |

---

## Host usage sequence

```
1.  Write SESSION_ID        -- select the active session (0–7)
2.  Write PROMPT_LEN        -- number of tokens already in the KV cache
3.  Write SPEC_K            -- number of speculative candidates (1–7)
4.  Write MAX_NEW_TOKENS    -- stop condition
5.  Write TARGET_TOKEN_ID   -- the verifier's ground-truth token
6.  Write DRAFT_TOKEN_0 ..  -- one register per draft candidate
    DRAFT_TOKEN_{SPEC_K-1}
7.  Write CTRL[0] = 1       -- launch inference
8.  Stream Q vectors:
      for batch in 0 .. SPEC_K:
        stream 64 elements via s_axis_q_* (taddr 0..63, tbatch = batch)
9.  Poll STATUS[0] (infer_busy) until it falls,
    or STATUS[1] (infer_done) asserts,
    or wait for intr if INTR_ENABLE[0] = 1
10. During S_COMMIT window:
      stream accepted KV pairs via s_axis_kv_*
11. Read GENERATED_TOKEN    -- most recent accepted token
12. Read TOKEN_COUNT        -- how many tokens were accepted this round
13. If INTR_ENABLE[0]:
      write 1 to INTR_STATUS[0] to clear the interrupt
14. Repeat from step 1 for the next speculative decode round
```

---

## Simulation

### Prerequisites

- Vivado 2018.2 on `PATH` (Windows: `$env:PATH = "D:\Vivado\2018.2\bin;" + $env:PATH`)
- Run all scripts from the `circle_x1/` project root
- The three `.mem` LUT files must be present at `src/rtl/`:
  - `exp_lut.mem` — 256-entry Q8.8 exponential table
  - `rope_lut.mem` — 512-entry RoPE sincos table (generate with `scripts/gen_rope_lut.py`)
  - `rms_seed_lut.mem` — 64-entry RMSNorm seed table (generate with `scripts/gen_rms_seed_lut.py`)

### Generate LUT files (first-time setup)

```powershell
python scripts/gen_rope_lut.py       # writes src/rtl/rope_lut.mem
python scripts/gen_rms_seed_lut.py   # writes src/rtl/rms_seed_lut.mem
# exp_lut.mem is checked in; no generation needed
```

### Run the speculative decode pipeline simulation (SIM)

```powershell
.\scripts\run_sim.ps1
```

Expected output:

```
MEM check: all .mem files present
=== XVLOG ===
xvlog exit: 0
=== XELAB ===
xelab exit: 0
=== XSIM ===
[TB ...] KV commit complete - kv_ready asserted
[TB ...] SPEC: first candidate issued, k advancing
[TB ...] FETCH_KV: rd_busy_seen asserted
CIRCLE X1 TOKEN_OUT: 002a
CIRCLE X1 SIM: PASS
```

### Run the end-to-end pipeline simulation (E2E)

```powershell
.\scripts\run_e2e.ps1
```

Expected output:

```
MEM check: all .mem files present
=== XVLOG ===
xvlog exit: 0
=== XELAB ===
xelab exit: 0
=== XSIM ===
CIRCLE X1 E2E: PASS
```

### Known benign warning

```
WARNING: port dma_start remains unconnected for this instance
```

This is from the legacy top-level integration testbench only. The DMA start port is driven in production; the TB stub omits it intentionally. All other warnings are errors-in-disguise and should be investigated.

---

## Synthesis preparation (Yosys / OpenROAD)

The RTL has been cleaned for synthesis. The following transformations have been applied:

### 1. Debug port removal
`dbg_rd_busy_seen` was a simulation-only output port on `attention_ctrl` and `circle_x1`. Both ports and all associated wiring have been removed. The testbench now monitors the signal via hierarchical path.

### 2. KV bus widening
The `vera_wr_k_data`, `vera_wr_v_data`, `vera_rd_k_data`, `vera_rd_v_data` wires in `circle_x1.v` have been widened from 16 bits to `DATA_WIDTH × HEAD_DIM` (1024 bits) to match `kv_cache_ctrl`'s port declarations. 16-bit sources are zero-padded on write; only `[15:0]` is consumed by `attention_ctrl` on read.

### 3. `$readmemh` placement
All four LUT arrays (`rope_rom`, `exp_lut`, `seed_rom`) use `$readmemh` inside `initial begin...end` blocks with no subsequent write ports. This is the Yosys ROM inference pattern and requires no changes.

### 4. `$display` removal
All `$display` calls in synthesisable RTL have been removed. They were present in `x1_reg_ctrl`, `attention_ctrl`, `inference_sequencer`, and `verify_ctrl`. Testbenches retain their `$display` instrumentation.

### 5. BRAM inference attributes
Yosys `(* ram_style *)` attributes added to the three large arrays:

| Module | Array | Attribute |
|---|---|---|
| `embedding_lut.v` | `emb_ram [0:VOCAB_SIZE-1]` | `"block"` |
| `lm_head.v` | `w_lm [0:VOCAB_SIZE-1][0:HEAD_DIM-1]` | `"block"` |
| `gemm_engine.v` | `b_ram [0:HEAD_DIM-1][0:HEAD_DIM-1]` | `"distributed"` |

`embedding_lut` and `lm_head` hold 32000-entry tables and must map to BRAM. `gemm_engine`'s 64×64 bias array fits comfortably in distributed LUTRAM.

---

## Design notes

### Speculative decode arbitration

`token_arbiter` compares each draft candidate against the target token. The first draft (lowest batch index) that matches the target is accepted, and all subsequent speculative tokens are rolled back. On a full rejection, the target token is accepted alone. Tie-breaking always favours the lowest candidate index — this is deterministic and requires no random number generation in hardware.

### Commit and rollback

`kv_commit_ctrl` receives the accepted count and rollback decision from `token_arbiter`. It:
1. Streams accepted KV pairs to Vera one at a time via `wr_req / wr_ack` handshake
2. If rollback is needed, evicts every page in the range `[rollback_token_pos >> 4 .. spec_tail_pos >> 4]` in ascending order via `evict_valid / evict_ack`

The two interfaces (`wr_req` and `evict_valid`) are never asserted simultaneously.

### Flat port convention

No module in this design uses array ports. Every draft token, every K/V bus, and every batch signal is a discrete named wire. This convention is required for clean elaboration in xsim 2018.2 and also simplifies Yosys elaboration.

### Single-cycle pulses

`infer_done`, `commit_done`, and `token_valid` are all one-clock pulses. Software polling `STATUS[1]` must sample at sufficient rate or use the interrupt. The `infer_busy` status bit is a level signal and is always safe to poll.

### Interrupt behaviour

`intr` is a level signal, not a pulse. It asserts when inference completes **and** `INTR_ENABLE[0]` is set. It deasserts one cycle after the host writes 1 to `INTR_STATUS[0]` (W1C). If `INTR_ENABLE[0]` is clear, the interrupt line stays deasserted regardless of inference state.

---

## Timing and area (preliminary — Artix-7 xc7a35tcpg236-1)

Vivado implementation has not been run on this revision. The design is sized for Artix-7 as a functional prototyping target; the OpenROAD / Skywater 130nm flow is the tapeout path. Estimates will be added after first-pass synthesis completes.

---

## Authors

Developed by Anubhav Gupta (AIS / Circle Silicon).
