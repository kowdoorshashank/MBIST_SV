
module bisr_remap #(
    parameter int ADDR_WIDTH    = 4,                 
    parameter int MAX_ROWS      = 16,
    parameter int MAX_COLS      = 16,
    parameter int SPARE_ROWS    = 4,
    parameter int SPARE_COLS    = 4,
    localparam PHYS_ADDR_BITS = $clog2(MAX_ROWS + SPARE_ROWS)

)(
    
    input  logic [ADDR_WIDTH-1:0] row_in,
    input  logic [ADDR_WIDTH-1:0] col_in,

    input  logic [MAX_ROWS-1:0]   row_repair_sig,
    input  logic [MAX_COLS-1:0]   col_repair_sig,

    output logic [PHYS_ADDR_BITS-1 :0] row_out,
    output logic [PHYS_ADDR_BITS-1 :0] col_out
);

    logic [PHYS_ADDR_BITS-1:0] spare_row_map [SPARE_ROWS];
    logic [PHYS_ADDR_BITS-1:0] spare_col_map [SPARE_COLS];

    logic [PHYS_ADDR_BITS-1:0] row_fault_map [MAX_ROWS];
    logic [PHYS_ADDR_BITS-1:0] col_fault_map [MAX_COLS];

    int row_idx_local;
    int col_idx_local;

    // -------------------------------------
    // Initial spare row/column assignments
    // -------------------------------------
    initial begin
        for (int i = 0; i < SPARE_ROWS; i = i + 1)
            spare_row_map[i] = MAX_ROWS + i;   

        for (int j = 0; j < SPARE_COLS; j = j + 1)
            spare_col_map[j] = MAX_COLS + j;
    end

    // ---------------------------------------------------
    // PRECOMPUTE permanent mapping once based on signature
    // (combinational: depends on row_repair_sig/col_repair_sig)
    // ---------------------------------------------------
    always_comb begin
        row_idx_local = 0;
        // build row map: if repaired -> assigned to next spare physical address,
        // else maps to same logical row 
        for (int i = 0; i < MAX_ROWS; i = i + 1) begin
            if (row_repair_sig[i]) begin
                row_fault_map[i] = spare_row_map[row_idx_local];
                row_idx_local ++;
            end else begin
                row_fault_map[i] = i; 
            end
        end
    end

    always_comb begin
        col_idx_local = 0;
        for (int j = 0; j < MAX_COLS; j = j + 1) begin
            if (col_repair_sig[j]) begin
                col_fault_map[j] = spare_col_map[col_idx_local];
                col_idx_local ++;
            end else begin
                col_fault_map[j] = j;
            end
        end
    end

    // -------------------------------------
    // Actual output mapping: index into the table with logical input
    // Note: row_in and col_in are logical rows (0..MAX_ROWS-1)
    // row_fault_map[row_in] is PHYS width so outputs are physical addresses
    // -------------------------------------
    assign row_out = row_fault_map[row_in];
    assign col_out = col_fault_map[col_in];

endmodule
