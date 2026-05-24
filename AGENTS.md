---

# Codex Operating Rules

## Reading Strategy
- Never read a file you were just given context for. If interfaces, parameters, or module skeletons are in the prompt, treat them as ground truth — do not re-read to confirm.
- When you must read, read exactly the lines you need using view with a range. Never cat an entire file to find one signal name.
- If you need to check an interface, grep for the port declaration -- do not open the whole module.
- After your first read of a file, cache what you learned. Do not re-read the same file twice in one task unless you made an edit and need to verify the exact changed lines.

## Editing Strategy
- Prefer str_replace over full rewrites. If a change touches under 40% of a file, always use str_replace.
- Batch your edits mentally before touching the file. Make all changes to one file in one pass, not five sequential str_replace calls where each one reads the result.
- When creating a new file, write the complete final version in one create_file call. Do not create a skeleton and then immediately edit it.

## Verification Strategy
- After an edit, read back only the changed lines to confirm correctness -- not the whole file.
- Run the testbench once. Read the transcript once. Extract pass/fail and any $display output. Do not re-run unless you made a fix.

## Planning
- Before any implementation, write your complete plan as a single block: files to create, edits to make, order of operations. Commit to it. Do not re-plan mid-task.
- If something is ambiguous, state your assumption explicitly and proceed. Do not stop to ask.

## Project Defaults (AIS / Circle Silicon)
- Toolchain: Vivado 2018.2, xsim, Artix-7 xc7a35tcpg236-1
- All RTL files are SystemVerilog with .v extension
- Fixed-point: Q8.8 inputs, Q1.15 scores
- HEAD_DIM=64, MAX_BATCH=8, NUM_SESSIONS=8, DATA_WIDTH=16
- All $display strings and comments are ASCII only
- Flat ports only -- no array ports (avoids xsim elaboration issues)
- Tie-breaking rule: lowest index wins on argmax ties
- token_base_pos is always passed as a top-level input, not computed internally

You are continuing implementation of the Circle AIS (Agentic Inference Subsystem).
token_arbiter.v is complete and verified (26/26 passing). Do not touch it.

PROJECT
Existing project: C:/Users/Anubhav Gupta/Desktop/Projects/ais/ais.xpr
Add files to the existing project -- do not recreate it.
New files:
  rtl/kv_commit_ctrl.v
  tb/tb_kv_commit_ctrl.v

MODULE PURPOSE
kv_commit_ctrl receives the accept/rollback decision from token_arbiter and
acts on it against Vera's KV store:
  - Streams accepted token KV pairs to Vera via the write interface
  - If rollback_needed, issues eviction requests to Vera for all speculative
    pages beyond the accepted tail
  - Signals commit_done when both write and eviction are complete

COMPLETE INTERFACE
module kv_commit_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Control from token_arbiter / inference_sequencer
    input  wire        commit_start,
    input  wire [2:0]  session_id,
    input  wire [15:0] token_base_pos,      // KV position of first candidate token
    input  wire [2:0]  accepted_count,      // 0-7 tokens to write
    input  wire        rollback_needed,
    input  wire [15:0] rollback_token_pos,  // first invalid KV position = token_base_pos + accepted_count
    input  wire [15:0] spec_tail_pos,       // last speculative KV position (token_base_pos + k)

    // KV data stream for accepted tokens (one token per beat)
    input  wire [15:0] commit_k_data,
    input  wire [15:0] commit_v_data,
    input  wire [2:0]  commit_token_idx,    // 0..accepted_count-1
    input  wire        commit_kv_valid,

    // Vera write interface (master)
    output reg         wr_req,
    output reg  [2:0]  wr_session_id,
    output reg  [15:0] wr_token_pos,
    output reg  [15:0] wr_k_data,
    output reg  [15:0] wr_v_data,
    input  wire        wr_ack,

    // Vera eviction interface (master)
    output reg         evict_valid,
    output reg  [7:0]  evict_page_id,
    output reg  [2:0]  evict_session_id,
    input  wire        evict_ack,

    // Status
    output reg         commit_done,         // single-cycle pulse
    output reg         commit_busy
);

PARAMETERS
parameter PAGE_SIZE_TOKENS = 16;    // must match Vera: TOTAL_PAGES=256, PAGE_SIZE=16
parameter MAX_CANDIDATES   = 7;

VERA WRITE PROTOCOL
- Assert wr_req, hold stable wr_session_id, wr_token_pos, wr_k_data, wr_v_data
- Wait for wr_ack (single cycle pulse from Vera)
- Deassert wr_req on the cycle after wr_ack
- One token per transaction, transactions are sequential
- wr_token_pos = token_base_pos + commit_token_idx for each accepted token

VERA EVICTION PROTOCOL
- Eviction is page-granular: evict_page_id = token_pos / PAGE_SIZE_TOKENS
- Rollback range: rollback_token_pos .. spec_tail_pos (inclusive)
- First page to evict: rollback_token_pos / PAGE_SIZE_TOKENS
- Last page to evict: spec_tail_pos / PAGE_SIZE_TOKENS
- If rollback_token_pos and spec_tail_pos fall on the same page, one eviction only
- Assert evict_valid + evict_page_id + evict_session_id
- Wait for evict_ack (single cycle pulse from Vera)
- Deassert evict_valid, increment page_id, repeat until last page evicted
- Evict pages in ascending order

FSM STATES
IDLE        -- waiting for commit_start
WRITE       -- streaming accepted tokens to Vera one by one via wr_req/wr_ack
EVICT       -- issuing eviction requests page by page (only if rollback_needed)
DONE        -- assert commit_done for one cycle, return to IDLE

Transition rules:
  IDLE  -> WRITE      on commit_start, if accepted_count > 0
  IDLE  -> EVICT      on commit_start, if accepted_count == 0 && rollback_needed
  IDLE  -> DONE       on commit_start, if accepted_count == 0 && !rollback_needed
  WRITE -> EVICT      all accepted tokens written, rollback_needed == 1
  WRITE -> DONE       all accepted tokens written, rollback_needed == 0
  EVICT -> DONE       all pages evicted
  DONE  -> IDLE       always (commit_done is the pulse)

DESIGN RULES
- commit_busy high from commit_start until commit_done
- commit_done is a single-cycle pulse
- commit_start while busy must be ignored
- wr_req and evict_valid must never be asserted simultaneously
- accepted_count == 0 with rollback_needed == 1 is valid (pure rollback, no writes)
- Division by PAGE_SIZE_TOKENS (16) is a right-shift by 4 -- use >> 4, no divider
- All flops reset to 0 on rst_n == 0
- Flat ports only, no arrays
- ASCII only in all $display and comments

TESTBENCH
Create tb/tb_kv_commit_ctrl.v with these named tests (-> PASS / -> FAIL):

Test 1: accepted_count=3, rollback_needed=0
  - 3 KV pairs written to Vera in order
  - No eviction issued
  - commit_done asserted after 3 wr_acks
  - Check: wr_token_pos sequence = token_base_pos, +1, +2

Test 2: accepted_count=0, rollback_needed=1, single page eviction
  - token_base_pos=32, spec_tail_pos=35 (same page: page 2)
  - No writes
  - One eviction: evict_page_id=2
  - commit_done after evict_ack

Test 3: accepted_count=2, rollback_needed=1, multi-page eviction
  - token_base_pos=16, accepted_count=2, rollback_token_pos=18, spec_tail_pos=31
  - 2 writes: positions 16, 17
  - Evict pages 1 (tokens 16-31) -- rollback_token_pos=18 >> 4 = page 1
  - spec_tail_pos=31 >> 4 = page 1, so one eviction only
  - commit_done after evict_ack

Test 4: accepted_count=0, rollback_needed=0
  - commit_done immediately (one cycle after commit_start)
  - No writes, no evictions

Test 5: multi-page eviction spanning 3 pages
  - token_base_pos=0, accepted_count=0, rollback_needed=1
  - rollback_token_pos=0, spec_tail_pos=47
  - Evict pages 0, 1, 2 in order
  - Check: 3 evict_valid pulses with correct page_ids and evict_acks

Test 6: commit_start ignored while busy
  - Start a 3-write commit, assert commit_start again mid-flight
  - Verify accepted_count and final state reflect only the first transaction

Test 7: accepted_count=7, rollback_needed=0 (max accepted, no rollback)
  - 7 sequential writes, no eviction
  - commit_done after 7 wr_acks

TCL
Do not recreate the project. In scripts/setup_kv_commit.tcl:
  open_project {C:/Users/Anubhav Gupta/Desktop/Projects/ais/ais.xpr}
  add_files -norecurse rtl/kv_commit_ctrl.v
  add_files -fileset sim_1 -norecurse tb/tb_kv_commit_ctrl.v
  set_property top tb_kv_commit_ctrl [get_filesets sim_1]
  launch_simulation -simset sim_1 -mode behavioral
  run 10ms
  close_sim

TARGET: 7/7 tests, all named checks passing.
Timescale warning on token_arbiter.v is known and harmless -- ignore it.
