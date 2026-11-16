// =============================================================================
// Module: hazard_detection
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #22 - Load-Use Hazard Detection & Pipeline Stall Control
//
// Description:
//   Hazard Detection Unit for the 5-stage in-order RV32I pipelined processor.
//   Identifies Read-After-Write (RAW) data dependencies that cannot be resolved
//   by forwarding alone and asserts the necessary pipeline stall controls.
//
// Primary Detection Logic:
//   In a pipelined CPU with full EX-to-EX and MEM-to-EX forwarding:
//   - ALU instructions produce results at the end of the EX stage, which can be
//     forwarded to dependent instructions without stalling.
//   - Load instructions (LW) only produce valid data at the end of the MEM stage.
//     Therefore, when a LW instruction is in the EX stage and the subsequent
//     instruction in the ID stage consumes the loaded value (rs1 or rs2), a
//     1-cycle pipeline stall (interlock) MUST be inserted.
//
// Stall Condition:
//   stall = ex_valid && ex_mem_read && (ex_rd != 5'd0) &&
//           ((id_uses_rs1 && (id_rs1 == ex_rd)) ||
//            (id_uses_rs2 && (id_rs2 == ex_rd)));
//
// Pipeline Interlock Actions (when stall == 1):
//   1. PC Hold:       pc_stall = 1, pc_en = 0.
//                     Top level drives next_pc = pc (re-fetching current address).
//   2. IF/ID Hold:    if_id_stall = 1, if_id_en = 0.
//                     Holds the instruction in IF/ID across the clock edge.
//   3. ID/EX Bubble:  id_ex_flush = 1 (id_ex_bubble = 1).
//                     Inserts a synchronous NOP bubble into the ID/EX boundary.
//   4. EX/MEM & MEM/WB: Advance normally (en = 1) so the LW progresses to MEM.
//
// Safety Guarantees:
//   - Ignores x0 dependencies: writes to x0 (rd = 0) never trigger a stall.
//   - Ignores invalid/bubble instructions: requires both id_valid and ex_valid.
//   - Qualifies source operands with id_uses_rs1 and id_uses_rs2:
//     Prevents false stalls on immediate fields of I-type instructions (e.g. ADDI, LW)
//     where immediate bits overlap the rs2 bitfield.
//   - Branch override: If a branch is taken in EX (branch_taken == 1), branch
//     redirection and pipeline flushes take precedence over stall requests.
// =============================================================================

`timescale 1ns/1ps

module hazard_detection #(
    parameter FORWARDING_SUPPORTED = 1
) (
    // -------------------------------------------------------------------------
    // Inputs from Instruction Decode (ID) Stage
    // -------------------------------------------------------------------------
    input  wire [4:0]  id_rs1,           // Source register 1 address
    input  wire [4:0]  id_rs2,           // Source register 2 address
    input  wire        id_uses_rs1,      // Instruction in ID actively consumes rs1
    input  wire        id_uses_rs2,      // Instruction in ID actively consumes rs2
    input  wire        id_valid,         // Instruction in ID is valid (not a bubble)

    // -------------------------------------------------------------------------
    // Inputs from Execute (EX) Stage (ID/EX Register Outputs)
    // -------------------------------------------------------------------------
    input  wire [4:0]  ex_rd,            // Destination register index in EX
    input  wire        ex_mem_read,      // Instruction in EX is a Load (LW)
    input  wire        ex_reg_write,     // Instruction in EX writes to register file
    input  wire        ex_valid,         // Instruction in EX is valid (not a bubble)

    // -------------------------------------------------------------------------
    // Inputs from Memory (MEM) Stage (EX/MEM Register Outputs)
    // -------------------------------------------------------------------------
    input  wire [4:0]  mem_rd,           // Destination register index in MEM
    input  wire        mem_mem_read,     // Instruction in MEM is a Load (LW)
    input  wire        mem_reg_write,    // Instruction in MEM writes to register file
    input  wire        mem_valid,        // Instruction in MEM is valid (not a bubble)

    // -------------------------------------------------------------------------
    // Branch Control Input (Optional Override)
    // -------------------------------------------------------------------------
    input  wire        branch_taken,     // Branch taken in EX (redirects PC, flushes pipeline)

    // -------------------------------------------------------------------------
    // Stall and Pipeline Control Outputs
    // -------------------------------------------------------------------------
    output wire        stall,            // Unified stall request (active-high)
    output wire        pc_stall,         // PC stall request: 1 = hold current PC
    output wire        pc_en,            // PC update enable: 0 = hold, 1 = advance
    output wire        if_id_stall,      // IF/ID stall request: 1 = hold register
    output wire        if_id_en,         // IF/ID capture enable: 0 = hold, 1 = capture
    output wire        id_ex_flush,      // ID/EX bubble request: 1 = flush / insert NOP
    output wire        id_ex_bubble      // Direct alias for id_ex_flush
);

    // -------------------------------------------------------------------------
    // 1. RAW Dependency Checks
    // -------------------------------------------------------------------------
    // Check if ID instruction's rs1 matches EX destination rd (non-zero)
    wire match_rs1_ex = id_valid && id_uses_rs1 && ex_valid &&
                        (ex_rd != 5'd0) && (id_rs1 == ex_rd);

    // Check if ID instruction's rs2 matches EX destination rd (non-zero)
    wire match_rs2_ex = id_valid && id_uses_rs2 && ex_valid &&
                        (ex_rd != 5'd0) && (id_rs2 == ex_rd);

    // Check if ID instruction's rs1 matches MEM destination rd (non-zero)
    wire match_rs1_mem = id_valid && id_uses_rs1 && mem_valid &&
                         (mem_rd != 5'd0) && (id_rs1 == mem_rd);

    // Check if ID instruction's rs2 matches MEM destination rd (non-zero)
    wire match_rs2_mem = id_valid && id_uses_rs2 && mem_valid &&
                         (mem_rd != 5'd0) && (id_rs2 == mem_rd);

    // -------------------------------------------------------------------------
    // 2. Load-Use Hazard Detection
    // -------------------------------------------------------------------------
    // A load-use hazard occurs when an instruction in EX is a Load (ex_mem_read=1)
    // and an instruction in ID reads from the same destination register.
    // Forwarding cannot supply the data because data is read during MEM stage.
    wire load_use_hazard = ex_mem_read && (match_rs1_ex || match_rs2_ex);

    // -------------------------------------------------------------------------
    // 3. Optional Non-Forwarding RAW Stalls (when FORWARDING_SUPPORTED == 0)
    // -------------------------------------------------------------------------
    // If operand forwarding is disabled, any RAW dependency with EX or MEM
    // must stall until the writing instruction reaches Write-Back.
    wire non_fwd_hazard = (!FORWARDING_SUPPORTED) && (
        (ex_reg_write  && (match_rs1_ex  || match_rs2_ex))  ||
        (mem_reg_write && (match_rs1_mem || match_rs2_mem))
    );

    // -------------------------------------------------------------------------
    // 4. Unified Stall Condition
    // -------------------------------------------------------------------------
    // When a branch is taken, younger instructions are discarded via flush;
    // stall is suppressed so PC immediately branches to the target address.
    wire raw_stall = (load_use_hazard || non_fwd_hazard);
    assign stall = raw_stall && !branch_taken;

    // -------------------------------------------------------------------------
    // 5. Pipeline Control Signals Generation
    // -------------------------------------------------------------------------
    // PC Control:
    // Stalls PC by keeping pc_stall high / pc_en low. Top-level feeds pc back.
    assign pc_stall = stall;
    assign pc_en    = ~stall;

    // IF/ID Pipeline Register Control:
    // When stalled, en = 0 holds all fields across the clock edge.
    assign if_id_stall = stall;
    assign if_id_en    = ~stall;

    // ID/EX Pipeline Register Control:
    // When stalled, id_ex_flush = 1 forces a synchronous NOP bubble into EX.
    assign id_ex_flush  = stall;
    assign id_ex_bubble = stall;

endmodule
