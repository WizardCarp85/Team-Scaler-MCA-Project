// =============================================================================
// Module: branch_controller
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #23 - Branch Redirect, Flush & Hazard Stall Coordination Logic
//
// Description:
//   Coordinates branch redirection from the EX stage with pipeline hazard
//   stalls and boundary flushes.
//
// Architectural Responsibilities:
//   1. Next-PC Redirection:
//      Accepts branch outcome (branch_taken) and target address (branch_target)
//      from the EX stage branch unit. When a branch is taken, next_pc is redirected
//      to branch_target instead of sequential pc+4 or held pc.
//
//   2. Wrong-Path Pipeline Flushing:
//      Because branches resolve in the EX stage, two younger in-flight instructions
//      are on the mispredicted path when a branch is taken:
//        - The instruction in IF (being fetched)
//        - The instruction in ID (in if_id_reg)
//      When branch_taken == 1, synchronous flushes are asserted to both if_id_reg
//      and id_ex_reg, replacing wrong-path instructions with bubbles (valid = 0, NOP)
//      before they can commit any register or memory side effects.
//
//   3. Deterministic Priority Resolution:
//      Priority is strictly defined as:
//        Priority 1: Branch Taken in EX (branch_taken == 1)
//                    -> Redirection and flush take absolute precedence over
//                       any load-use stall request from younger instructions.
//        Priority 2: Load-Use Hazard Stall (stall_req == 1 && !branch_taken)
//                    -> Holds PC (next_pc = pc), freezes IF/ID (en = 0),
//                       and inserts a bubble into ID/EX (flush = 1).
//        Priority 3: Normal Sequential Progression
//                    -> Advances PC (next_pc = pc+4), enables IF/ID and ID/EX capture.
//
// Safety Guarantees:
//   - Branch target instruction is fetched and executed exactly once.
//   - Flushed instructions have valid = 0, which suppresses all downstream
//     side effects (reg_write, mem_write, mem_read, branch_taken).
//   - Never duplicates PC, branch comparator, or pipeline registers.
// =============================================================================

`timescale 1ns/1ps

module branch_controller #(
    parameter [1:0] PC_PLUS4  = 2'b00,
    parameter [1:0] PC_BRANCH = 2'b01,
    parameter [1:0] PC_HOLD   = 2'b10
) (
    // -------------------------------------------------------------------------
    // Inputs from Fetch (IF) Stage
    // -------------------------------------------------------------------------
    input  wire [31:0] pc,              // Current fetch PC (from pc.v)
    input  wire [31:0] pc_plus4,        // Sequential PC+4 (from if_stage.v)

    // -------------------------------------------------------------------------
    // Inputs from Execute (EX) Stage (Branch Unit / ex_stage)
    // -------------------------------------------------------------------------
    input  wire        branch_taken,    // Branch condition evaluated true in EX
    input  wire [31:0] branch_target,   // Target address (pc + imm) from branch_unit

    // -------------------------------------------------------------------------
    // Input from Hazard Detection Unit (M5)
    // -------------------------------------------------------------------------
    input  wire        stall_req,       // Load-use stall request from hazard_detection.v

    // -------------------------------------------------------------------------
    // Outputs to Fetch (IF) Stage / PC State
    // -------------------------------------------------------------------------
    output reg  [31:0] next_pc,         // Next PC value to load into pc.v
    output reg  [1:0]  pc_src,          // PC mux select (00=PC+4, 01=Branch, 10=Hold)
    output reg         pc_en,           // PC update enable (0 = hold, 1 = advance/redirect)

    // -------------------------------------------------------------------------
    // Outputs to Pipeline Registers (M1/M2/M3 Control)
    // -------------------------------------------------------------------------
    output reg         if_id_flush,     // Synchronous flush to if_id_reg
    output reg         if_id_en,        // Capture enable to if_id_reg
    output reg         id_ex_flush,     // Synchronous flush / bubble to id_ex_reg
    output reg         id_ex_en,        // Capture enable to id_ex_reg

    // -------------------------------------------------------------------------
    // Status & Diagnostics Outputs
    // -------------------------------------------------------------------------
    output reg         stall_out,       // Qualified stall indicator (suppressed on branch)
    output reg         flush_out        // Pipeline flush active (branch_taken)
);

    // -------------------------------------------------------------------------
    // Combinational Coordination Logic with Strict Priority
    // -------------------------------------------------------------------------
    always @* begin
        if (branch_taken) begin
            // -----------------------------------------------------------------
            // Priority 1: Branch Taken in EX
            // -----------------------------------------------------------------
            // Branch redirection takes absolute precedence over any hazard stall.
            // Wrong-path instructions in IF and ID are flushed.
            next_pc     = branch_target;
            pc_src      = PC_BRANCH;
            pc_en       = 1'b1;         // Load branch target into PC

            if_id_flush = 1'b1;         // Flush instruction being fetched in IF
            if_id_en    = 1'b1;         // Allow capture of flush state

            id_ex_flush = 1'b1;         // Flush wrong-path instruction in ID
            id_ex_en    = 1'b1;         // Allow capture of flush state

            stall_out   = 1'b0;         // Suppress stall for wrong-path instructions
            flush_out   = 1'b1;         // Indicate pipeline flush event
        end else if (stall_req) begin
            // -----------------------------------------------------------------
            // Priority 2: Load-Use Hazard Stall
            // -----------------------------------------------------------------
            // Hold current PC and IF/ID; insert synchronous bubble into ID/EX.
            next_pc     = pc;
            pc_src      = PC_HOLD;
            pc_en       = 1'b0;         // PC hold

            if_id_flush = 1'b0;         // Preserve instruction in ID
            if_id_en    = 1'b0;         // Freeze IF/ID register

            id_ex_flush = 1'b1;         // Insert bubble (valid = 0) into EX
            id_ex_en    = 1'b1;         // Advance bubble into EX

            stall_out   = 1'b1;         // Active stall
            flush_out   = 1'b0;
        end else begin
            // -----------------------------------------------------------------
            // Priority 3: Normal Sequential Progression
            // -----------------------------------------------------------------
            next_pc     = pc_plus4;
            pc_src      = PC_PLUS4;
            pc_en       = 1'b1;         // Advance PC

            if_id_flush = 1'b0;         // Normal capture
            if_id_en    = 1'b1;

            id_ex_flush = 1'b0;         // Normal capture
            id_ex_en    = 1'b1;

            stall_out   = 1'b0;
            flush_out   = 1'b0;
        end
    end

endmodule
