// fault_injector_2d.sv
// Mode 2: faults may be applied per-row, per-col, or per-cell
module fault_injector #(
    parameter int ROW_ADDR_BITS = 4,
    parameter int COL_ADDR_BITS = 4,
    parameter int DATA_WIDTH    = 8
)(
    input  logic                            clk,
    input  logic                            wr_en,        // write enable from MBIST
    input  logic [ROW_ADDR_BITS-1:0]        row_addr,     // logical row (MBIST view)
    input  logic [COL_ADDR_BITS-1:0]        col_addr,     // logical col (MBIST view)
    input  logic [DATA_WIDTH-1:0]           data_in,      // data being written (MBIST)
    input  logic [DATA_WIDTH-1:0]           data_out_mem, // data read from physical memory (after remap mux)
    output logic [DATA_WIDTH-1:0]           data_out_faulted // data presented to MBIST
);

    // Fault target selection (choose which kind of targeting is enabled)
    // set these from TB as needed before you start MBIST/BIRA
    logic apply_to_row    = 1'b0; // if 1, target applies to entire row (row_target)
    logic apply_to_col    = 1'b0; // if 1, target applies to entire col (col_target)
    logic apply_to_cell   = 1'b1; // if 1, target applies to a single cell (row+col)
    // You can set any combination. Example: apply_to_row=1, apply_to_col=0 -> row faults.

    // Fault coordinates (programmable by TB)
    logic [ROW_ADDR_BITS-1:0] target_row   = 'h3; // row index for row-target or cell-target
    logic [COL_ADDR_BITS-1:0] target_col   = 'h2; // col index for col-target or cell-target

    // Enumerated fault types
    typedef enum logic [2:0] {
        NONE = 3'b000,
        SAF  = 3'b001, // stuck-at-0 (or 1 with config)
        TF   = 3'b010, // transition fault
        AF   = 3'b011, // address fault (data redirected / corrupted)
        CF   = 3'b100  // coupling fault (aggressor affects victim)
    } fault_e;

    fault_e fault_type = NONE;

    // SAF configuration: which value to force (0 or 1)
    logic saf_force_value = 1'b0; // default SA0

    // TF config: bit position to flip
    int tf_bit = 0;

    // AF config: for AF we will replace read data from victim with data_in on write
    // (TB can set semantics). Here AF triggers when write occurs at target address.
    // CF config: map aggressor -> victim (row/col). TB can set aggressor/victim coords.
    logic [ROW_ADDR_BITS-1:0] cf_aggr_row = 'h2;
    logic [COL_ADDR_BITS-1:0] cf_aggr_col = 'h3;
    logic [ROW_ADDR_BITS-1:0] cf_victim_row = 'h3;
    logic [COL_ADDR_BITS-1:0] cf_victim_col = 'h4;
    int cf_bit = 0;
    logic target_hit;

    // For TF we save last read value (simple single-stage history)
    logic [DATA_WIDTH-1:0] prev_read_value;

    // Convenience: is current access matching a target?
    function logic is_cell_target(input logic [ROW_ADDR_BITS-1:0] r, input logic [COL_ADDR_BITS-1:0] c);
        return ((apply_to_cell && (r == target_row) && (c == target_col)));
    endfunction

    function logic is_row_target(input logic [ROW_ADDR_BITS-1:0] r);
        return (apply_to_row && (r == target_row));
    endfunction

    function logic is_col_target(input logic [COL_ADDR_BITS-1:0] c);
        return (apply_to_col && (c == target_col));
    endfunction

    // store previous read value on clock for TF detection
    always_ff @(posedge clk) begin
        prev_read_value <= data_out_mem;
    end

    // Main combinational fault application:
    always_comb begin
        // default: pass-through memory data
        data_out_faulted = data_out_mem;

        // Check if this access is affected by ANY active target
        
        target_hit = is_cell_target(row_addr, col_addr) || is_row_target(row_addr) || is_col_target(col_addr);

        unique case (fault_type)
            NONE: begin
                // pass-through
            end

            SAF: begin
                if (target_hit) begin
                    // drive selected bit(s) to saf_force_value; here only single bit tf_bit
                    data_out_faulted[tf_bit] = saf_force_value;
                end
            end

            TF: begin
                // transition fault: if write is happening at target, flip bit compared to previous
                if (target_hit && wr_en) begin
                    // if stable (no change) then force flip of tf_bit
                    if (data_out_mem[tf_bit] == prev_read_value[tf_bit])
                        data_out_faulted[tf_bit] = ~data_out_mem[tf_bit];
                    else
                        data_out_faulted[tf_bit] = data_out_mem[tf_bit];
                end
            end

            AF: begin
                // address fault: when writing to the targeted address, the victim's read data is replaced by written data
                if (target_hit && wr_en) begin
                    data_out_faulted = data_in; // simple semantics: written data appears unexpectedly
                end
            end

            CF: begin
                // coupling: a write to aggressor cell flips victim bit when aggressor matches
                if ( (row_addr == cf_aggr_row && col_addr == cf_aggr_col) && wr_en ) begin
                    // if this write is to the aggressor, then present victim's data flipped on next read
                    // Here we apply coupling immediately to read data (simple behavioural model)
                    if (row_addr == cf_victim_row && col_addr == cf_victim_col) begin
                        data_out_faulted[cf_bit] = ~data_out_mem[cf_bit];
                    end else begin
                        // if aggressor write and current read happens to be victim (same time), flip
                        // otherwise pass-through
                    end
                end
                // Note: a more detailed CF model would store an effect and apply on victim access.
            end

            default: begin
                // pass-through
            end
        endcase
    end

endmodule
