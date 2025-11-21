// tb_mbist_2d_final.sv
`timescale 1ns/1ps

`include "bira_pkg.sv"
import bira_pkg::*;

`include "memory_model.sv"
`include "fault_injector.sv"
`include "mbist_controller.sv"
`include "bira_engine.sv"
`include "bisr_remap.sv"

module tb_mbist_2d_final;

    // ------------------------------------------------------------
    // Config - adjust if you changed RTL parameters
    // ------------------------------------------------------------
    parameter int LOGICAL_ROW_BITS = 4;    // logical rows (16)
    parameter int LOGICAL_COL_BITS = 4;    // logical cols (16)
    parameter int MAX_ROWS         = 16;
    parameter int MAX_COLS         = 16;
    parameter int SPARE_ROWS       = 4;
    parameter int SPARE_COLS       = 4;
    parameter int DATA_WIDTH       = 8;
    parameter int MAX_FAULTS       = 8;

    // flattened logical address passed to MBIST = {row, col}
    parameter int LOGICAL_ADDR_WIDTH = LOGICAL_ROW_BITS + LOGICAL_COL_BITS;
    parameter int PHYS_ROW_BITS = $clog2(MAX_ROWS + SPARE_ROWS);
    parameter int PHYS_COL_BITS = $clog2(MAX_COLS + SPARE_COLS);

    // ------------------------------------------------------------
    // Clocks / resets
    // ------------------------------------------------------------
    logic clk;
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz simulated

    // Two resets: global (for mem/bira/etc) and mbist-specific (so we can rerun MBIST)
    logic global_rst_n;
    logic mbist_rst_n;

    initial begin
        global_rst_n = 0;
        mbist_rst_n  = 0;
        #20;
        global_rst_n = 1;
        mbist_rst_n  = 1; // MBIST allowed to run after this
    end

    // ------------------------------------------------------------
    // MBIST interface (flattened address)
    // ------------------------------------------------------------
    // --- MBIST interface (correct widths + flattened addr)
logic wr_en;
logic [LOGICAL_ROW_BITS-1:0] row_addr;
logic [LOGICAL_COL_BITS-1:0] col_addr;
logic [LOGICAL_ADDR_WIDTH-1:0] addr;
assign addr = {row_addr, col_addr};

logic [DATA_WIDTH-1:0] data_in;
logic [DATA_WIDTH-1:0] data_out_mem;
logic [DATA_WIDTH-1:0] data_out_faulted;
logic [DATA_WIDTH-1:0] data_out_final;

logic bist_done;
logic bist_fail;

    // MBIST outputs (driven by mbist_controller) - TB reads these (do NOT drive)
    logic [3:0] fault_count_mbist;
    fault_rec_t fault_list_mbist [MAX_FAULTS-1:0];

    // TB-driven BIRA inputs (we copy MBIST outputs into these)
    logic [3:0] bira_fault_count;
    fault_rec_t bira_fault_list [MAX_FAULTS-1:0];

    // BIRA outputs
    logic [MAX_ROWS-1:0] row_repair_sig;
    logic [MAX_COLS-1:0] col_repair_sig;
    logic bira_done;
    logic bira_pass;
    logic start_bira;

    // BISR outputs
    logic [PHYS_ROW_BITS-1:0] remap_row_addr;
    logic [PHYS_COL_BITS-1:0] remap_col_addr;

    // repair mux enable
    logic repair_active;

    // debug mapping arrays (TB-only)
    logic [PHYS_ROW_BITS-1:0] row_map [0:MAX_ROWS-1];
    logic [PHYS_COL_BITS-1:0] col_map [0:MAX_COLS-1];

    // derived logical row / col from flattened addr: flattening chosen as {row, col}
    logic [LOGICAL_ROW_BITS-1:0] logical_row;
    logic [LOGICAL_COL_BITS-1:0] logical_col;
    assign logical_col = addr[0 +: LOGICAL_COL_BITS];
    assign logical_row = addr[LOGICAL_COL_BITS +: LOGICAL_ROW_BITS];

    int r_idx; int c_idx;

    // ------------------------------------------------------------
    // Address mux - choose remapped physical address when repair is active
    // (zero-extend logical -> phys when not repaired)
    // ------------------------------------------------------------
    logic [PHYS_ROW_BITS-1:0] row_addr_to_mem;
    logic [PHYS_COL_BITS-1:0] col_addr_to_mem;

    always_comb begin
        if (repair_active) begin
            row_addr_to_mem = remap_row_addr;
            col_addr_to_mem = remap_col_addr;
        end else begin
            // zero-extend logical row/col to physical width (no repair)
            row_addr_to_mem = {{(PHYS_ROW_BITS - LOGICAL_ROW_BITS){1'b0}}, logical_row};
            col_addr_to_mem = {{(PHYS_COL_BITS - LOGICAL_COL_BITS){1'b0}}, logical_col};
        end
    end

    // ------------------------------------------------------------
    // DUT instantiation
    // - 2D physical memory
    // - fault injector works on logical addr (MBIST view)
    // - MBIST controller uses flattened logical addr
    // - BIRA driven by TB inputs (we copy MBIST outputs into these)
    // - BISR 2D remap: logical_row/logical_col -> physical row/col
    // ------------------------------------------------------------

    // 2D memory: takes physical addresses (PHYS_ROW_BITS, PHYS_COL_BITS)
    memory_model_2d #(
        .ROW_ADDR_BITS(PHYS_ROW_BITS),
        .COL_ADDR_BITS(PHYS_COL_BITS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mem (
        .clk(clk),
        .rst_n(global_rst_n),
        .wr_en(wr_en),
        .row(row_addr_to_mem),
        .col(col_addr_to_mem),
        .data_in(data_in),
        .data_out(data_out_mem)
    );

    // fault injector: works on logical flattened addr (MBIST sees results)
    // --- fixed fault_injector instantiation
fault_injector #(
    .ROW_ADDR_BITS(PHYS_ROW_BITS),
    .COL_ADDR_BITS(PHYS_COL_BITS),
    .DATA_WIDTH(DATA_WIDTH)
) u_fault (
    .clk(clk),
    .wr_en(wr_en),
    .row_addr(row_addr),
    .col_addr(col_addr),
    .data_in(data_in),
    .data_out_mem(data_out_mem),
    .data_out_faulted(data_out_faulted)
);



    // MBIST controller (flattened addr)
    mbist_controller #(
    .ROW_ADDR_WIDTH(LOGICAL_ROW_BITS),   // e.g. 4
    .COL_ADDR_WIDTH(LOGICAL_COL_BITS),   // e.g. 4
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_FAULTS(MAX_FAULTS)
) u_mbist (
    .clk(clk),
    .rst_n(mbist_rst_n),
    .wr_en(wr_en),
    .row_addr(row_addr),
    .col_addr(col_addr),
    .data_in(data_in),
    .data_out(data_out_final),
    .bist_done(bist_done),
    .bist_fail(bist_fail),
    .fault_count(fault_count_mbist),
    .fault_list(fault_list_mbist)
);


    // BIRA engine - TB will write bira_fault_* before start_bira asserted
    bira_engine #(
        .MAX_ROWS(MAX_ROWS),
        .MAX_COLS(MAX_COLS),
        .MAX_FAULTS(MAX_FAULTS),
        .SPARE_ROWS(SPARE_ROWS),
        .SPARE_COLS(SPARE_COLS)
    ) u_bira (
        .clk(clk),
        .rst_n(global_rst_n),
        .start_bira(start_bira),
        .fault_count(bira_fault_count),
        .fault_list(bira_fault_list),
        .bira_done(bira_done),
        .bira_success(bira_pass),
        .row_repair_sig(row_repair_sig),
        .col_repair_sig(col_repair_sig)
    );

    // 2D BISR remap: logical row/col -> phys row/col using repair signatures
    // Note: bisr_remap module should accept LOGICAL_ROW_BITS/LOGICAL_COL_BITS versions;
    // adapt port names/params to your version if needed.
    bisr_remap #(
        .LOGICAL_ROW_BITS(LOGICAL_ROW_BITS),
        .LOGICAL_COL_BITS(LOGICAL_COL_BITS),
        .MAX_ROWS(MAX_ROWS),
        .MAX_COLS(MAX_COLS),
        .SPARE_ROWS(SPARE_ROWS),
        .SPARE_COLS(SPARE_COLS)
    ) u_bisr (
        .row_in(logical_row),
        .col_in(logical_col),
        .row_repair_sig(row_repair_sig),
        .col_repair_sig(col_repair_sig),
        .row_out(remap_row_addr),
        .col_out(remap_col_addr)
    );

    // MBIST sees injector output
    assign data_out_final = data_out_faulted;

    // ------------------------------------------------------------
    // TB helpers
    // ------------------------------------------------------------
    // copy MBIST faults into TB-driven BIRA inputs (avoid driving MBIST outputs)
    // --- improved copy task with debug prints
task automatic copy_mbist_to_bira();
begin
    // clear
    bira_fault_count = 0;
    for (int i = 0; i < MAX_FAULTS; i++) begin
        bira_fault_list[i].row = 0;
        bira_fault_list[i].col = 0;
        bira_fault_list[i].fault_type = 0;
    end

    $display("\n[TB] MBIST reported fault_count = %0d", fault_count_mbist);
    for (int i = 0; i < fault_count_mbist; i++) begin
        $display("[TB] MBIST fault %0d -> row=%0d col=%0d type=%0b",
                 i, fault_list_mbist[i].row, fault_list_mbist[i].col, fault_list_mbist[i].fault_type);
    end

    if (fault_count_mbist != 0) begin
        bira_fault_count = fault_count_mbist;
        for (int i = 0; i < MAX_FAULTS; i++) begin
            bira_fault_list[i] = fault_list_mbist[i];
        end
        $display("[TB] Using MBIST-detected faults: count=%0d", bira_fault_count);
        for (int i = 0; i < bira_fault_count; i++)
            $display("[TB] -> copied to BIRA %0d: row=%0d col=%0d", i, bira_fault_list[i].row, bira_fault_list[i].col);
    end else begin
        // generate random faults for demo
        bira_fault_count = $urandom_range(2, 4);
        for (int i = 0; i < bira_fault_count; i++) begin
            bira_fault_list[i].row = $urandom_range(0, MAX_ROWS-1);
            bira_fault_list[i].col = $urandom_range(0, MAX_COLS-1);
            bira_fault_list[i].fault_type = $urandom_range(0, 3);
            $display("[TB] Injected BIRA Fault %0d -> row=%0d col=%0d type=%0b",
                     i, bira_fault_list[i].row, bira_fault_list[i].col, bira_fault_list[i].fault_type);
        end
    end
end
endtask


    // waveform dump
    initial begin
        $display("Dumping waves to waves.vcd");
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_mbist_2d_final);
    end

    // ------------------------------------------------------------
    // Main test flow:
    //   MBIST #1 -> copy MBIST faults to BIRA -> start BIRA ->
    //   enable repair_active (BISR used) -> rerun MBIST #2 on repaired memory
    // ------------------------------------------------------------
    initial begin
        // default
        repair_active = 0;
        start_bira = 0;
        // Wait for MBIST to start and run
        wait (mbist_rst_n == 1);
        #5;

        // MBIST #1 with timeout
        fork
            begin
                wait (bist_done);
                $display("\n[TB] MBIST #1 complete. bist_fail=%0d", bist_fail);
            end
            begin
                #2000 $display("ERROR: MBIST #1 timeout");
                $display ( bist_done);$finish;
            end
        join_any

        // Copy MBIST outputs to BIRA inputs (TB-driven)
        copy_mbist_to_bira();

        // Start BIRA
        #5;
        start_bira = 1;
        #10;
        start_bira = 0;

        // Wait for BIRA done w/ timeout
        fork
            begin
                wait (bira_done);
                $display("[TB] BIRA done. pass=%0d", bira_pass);
            end
            begin
                #2000 $display("ERROR: BIRA timeout"); $finish;
            end
        join_any

        // Show repair signatures
        $display("Row Repair Sig = %b", row_repair_sig);
        $display("Col Repair Sig = %b", col_repair_sig);

        // Build TB mapping (for print / verification)
        r_idx = 0;
        c_idx = 0;
        for (int i = 0; i < MAX_ROWS; i++) begin
            if (row_repair_sig[i]) begin
                row_map[i] = MAX_ROWS + r_idx;
                r_idx++;
            end else row_map[i] = i;
        end
        for (int j = 0; j < MAX_COLS; j++) begin
            if (col_repair_sig[j]) begin
                col_map[j] = MAX_COLS + c_idx;
                c_idx++;
            end else col_map[j] = j;
        end

        $display("\n=== LOGICAL -> PHYSICAL (ROWS) ===");
        for (int i = 0; i < MAX_ROWS; i++) $display("logical row %0d -> phys %0d", i, row_map[i]);
        $display("\n=== LOGICAL -> PHYSICAL (COLS) ===");
        for (int j = 0; j < MAX_COLS; j++) $display("logical col %0d -> phys %0d", j, col_map[j]);

        // Enable repair mux so memory now uses remapped addresses
        repair_active = 1;
        $display("\n[TB] repair_active = 1 -> memory will use BISR outputs (remap_row_addr/remap_col_addr)");

        // Rerun MBIST on repaired memory:
        // pulse MBIST reset to force controller to start again
        #5;
        mbist_rst_n = 0; #4; mbist_rst_n = 1;

        // MBIST #2 with timeout
        fork
            begin
                wait (bist_done);
                $display("\n[TB] MBIST #2 complete. bist_fail=%0d", bist_fail);
            end
            begin
                #2000 $display("ERROR: MBIST #2 timeout"); $finish;
            end
        join_any

        // Final summary
        $display("\n=== FINAL SUMMARY ===");
        $display("BIRA pass = %0d, MBIST final fail = %0d", bira_pass, bist_fail);

        #100;
        $finish;
    end

endmodule