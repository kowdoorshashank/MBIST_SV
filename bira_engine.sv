
import bira_pkg::*;

module bira_engine #(
    parameter int MAX_ROWS   = 16,
    parameter int MAX_COLS   = 16,
    parameter int MAX_FAULTS = 8,
    parameter int SPARE_ROWS = 4,
    parameter int SPARE_COLS = 4
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start_bira,
    input  logic [3:0] fault_count,
    input  fault_rec_t fault_list [MAX_FAULTS-1:0] ,
    output logic bira_done,
    output logic bira_success,
    output logic [MAX_ROWS-1:0] row_repair_sig,
    output logic [MAX_COLS-1:0] col_repair_sig
);

    //=====================================================
    // Internal Signals and Registers
    //=====================================================
    typedef enum logic [2:0] {
        IDLE,
        LOAD_FAULTS,
        ANALYZE,
        REPAIR,
        DONE
    } bira_state_t;

    bira_state_t state, next_state;

    // Internal variables
    int row_faults   [0:MAX_ROWS-1];
    int col_faults   [0:MAX_COLS-1];
    int total_faults;
    int repair_row_count, repair_col_count;
    int s;



    //=====================================================
    // Sequential State Transition
    //=====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    //=====================================================
    // Next State Logic
    //=====================================================
    always_comb begin
        next_state = state;
        case (state)
            IDLE:        if (start_bira) next_state = LOAD_FAULTS;
            LOAD_FAULTS: next_state = ANALYZE;
            ANALYZE:     next_state = (total_faults > 0) ? REPAIR : DONE;
            REPAIR:      next_state = DONE;
            DONE:        next_state = IDLE;
        endcase
    end

    //=====================================================
    // Main FSM Behavior
    //=====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bira_done    <= 0;
            bira_success <= 0;
            total_faults <= 0;
            repair_row_count <= 0;
            repair_col_count <= 0;
            s <= 0;
            foreach (row_faults[i]) row_faults[i] = 0;
            foreach (col_faults[i]) col_faults[i] = 0;
            row_repair_sig <= '0;
            col_repair_sig <= '0;
        end
        else begin
            case (state)

                //-----------------------------------------
                // IDLE
                //-----------------------------------------
                IDLE: begin
                    bira_done    <= 0;
                    bira_success <= 0;
                    total_faults <= 0;
                    repair_row_count <= 0;
                    repair_col_count <= 0;
                    s <= 0;
                    foreach (row_faults[i]) row_faults[i] = 0;
                    foreach (col_faults[i]) col_faults[i] = 0;
                    row_repair_sig <= '0;
                    col_repair_sig <= '0;
                end

                //-----------------------------------------
                // LOAD_FAULTS
                //-----------------------------------------
                LOAD_FAULTS: begin
                    $display("=== [BIRA] Loading Fault Information ===");
                    total_faults = fault_count;

                    foreach (fault_list[i]) begin
                        if (i < fault_count) begin
                            row_faults[fault_list[i].row]++;
                            col_faults[fault_list[i].col]++;
                            $display("[BIRA] Fault %0d: Row=%0d Col=%0d Type=%b",
                                     i, fault_list[i].row, fault_list[i].col, fault_list[i].fault_type);
                            s = 1;
                        end else
                            s = 0;
                    end

                    if (s == 0)
                        $display("[BIRA] No Fault Information");
                end

                //-----------------------------------------
                // ANALYZE
                //-----------------------------------------
                ANALYZE: begin
                    $display("=== [BIRA] Analyzing Fault Distribution ===");
                    s = 0;
                    
                    for (int i = 0; i < MAX_ROWS; i++)
                        if (row_faults[i] > 0) begin
                            $display("  Row %0d has %0d faults", i, row_faults[i]);
                            s = 1;
                        end
                    for (int j = 0; j < MAX_COLS; j++)
                        if (col_faults[j] > 0) begin
                            $display("  Col %0d has %0d faults", j, col_faults[j]);
                            s = 1;
                        end
                    if (s == 0)
                        $display("[BIRA] No Fault Information");
                end

                //-----------------------------------------
                // REPAIR (Apply Redundancy + Generate Signature)
                //-----------------------------------------
                REPAIR: begin
                    $display("=== [BIRA] Repair Stage Initiated ===");
                    bira_success = 1;
                    s = 0;

                    // Row replacement logic
                    for (int i = 0; i < MAX_ROWS; i++) begin
                        if (row_faults[i] > 0 && repair_row_count < SPARE_ROWS) begin
                            repair_row_count++;
                            row_repair_sig[i] = 1'b1;
                            $display("[BIRA] -> Replacing Row %0d with Spare Row %0d", i, repair_row_count);
                            s = 1;
                        end
                        else if (row_faults[i] > 0 && repair_row_count >= SPARE_ROWS) begin
                            bira_success = 0;
                            $display("[BIRA] !! Not enough spare rows for Row %0d", i);
                            s = 1;
                        end
                    end

                    // Column replacement logic
                    for (int j = 0; j < MAX_COLS; j++) begin
                        if (col_faults[j] > 0 && repair_col_count < SPARE_COLS) begin
                            repair_col_count++;
                            col_repair_sig[j] = 1'b1;
                            $display("[BIRA] -> Replacing Col %0d with Spare Col %0d", j, repair_col_count);
                            s = 1;
                        end
                        else if (col_faults[j] > 0 && repair_col_count >= SPARE_COLS) begin
                            bira_success = 0;
                            $display("[BIRA] !! Not enough spare columns for Col %0d", j);
                            s = 1;
                        end
                    end

                    if (s != 1)
                        $display("[BIRA] No Fault Information");
                end

                //-----------------------------------------
                // DONE
                //-----------------------------------------
                DONE: begin
                    bira_done <= 1;
                    $display("\n=== [BIRA] Generated Repair Signatures ===");
                    $display("Row Repair Signature : %b", row_repair_sig);
                    $display("Col Repair Signature : %b", col_repair_sig);

                    if (s == 0)
                        $display("[BIRA] SUCCESS: No Fault Detected");
                    else if (bira_success)
                        $display(" [BIRA] SUCCESS: All faults repaired!");
                    else
                        $display(" [BIRA] FAIL: Insufficient spares!");

                    $display("[BIRA] Repair Signatures Ready for BISR\n");
                end
            endcase
        end
    end
endmodule