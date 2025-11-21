`timescale 1ns/1ps
import bira_pkg::*;

module mbist_controller #(
    parameter int ROW_ADDR_WIDTH = 4,
    parameter int COL_ADDR_WIDTH = 4,
    parameter int DATA_WIDTH     = 8,
    parameter int MAX_FAULTS     = 8
)(
    input  logic                           clk,
    input  logic                           rst_n,

    output logic                           wr_en,
    output logic [ROW_ADDR_WIDTH-1:0]      row_addr,
    output logic [COL_ADDR_WIDTH-1:0]      col_addr,
    output logic [DATA_WIDTH-1:0]          data_in,
    input  logic [DATA_WIDTH-1:0]          data_out,

    output logic                           bist_done,
    output logic                           bist_fail,

    output logic [$clog2(MAX_FAULTS+1)-1:0] fault_count,
    output fault_rec_t                     fault_list [MAX_FAULTS]
);

    typedef enum logic [2:0] {
        IDLE,
        WRITE_0,
        READ_0_WRITE_1,
        READ_1_WRITE_0,
        DONE
    } mbist_state_e;

    mbist_state_e state;

    logic [ROW_ADDR_WIDTH-1:0] row_cnt;
    logic [COL_ADDR_WIDTH-1:0] col_cnt;

    logic [DATA_WIDTH-1:0] expected_data;

    logic detected_fault;
    logic [$clog2(MAX_FAULTS+1)-1:0] f_index;

    assign row_addr = row_cnt;
    assign col_addr = col_cnt;

    // =========================================================
    // SINGLE always_ff (legal driver) – ALL registers written here
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            state       <= IDLE;
            row_cnt     <= '0;
            col_cnt     <= '0;
            wr_en       <= 0;
            data_in     <= '0;

            bist_done   <= 0;
            bist_fail   <= 0;

            f_index     <= 0;
            fault_count <= 0;

            // RESET FAULT LIST PROPERLY
            for (int i = 0; i < MAX_FAULTS; i++) begin
                fault_list[i].row        <= '0;
                fault_list[i].col        <= '0;
                fault_list[i].fault_type <= '0;
            end

        end else begin
            // per-cycle defaults
            wr_en <= 0;
            data_in <= '0;
            detected_fault <= 0;

            case (state)

                IDLE: begin
                    // start the algorithm immediately on release from reset
                    row_cnt     <= '0;
                    col_cnt     <= '0;
                    f_index     <= 0;
                    fault_count <= 0;
                    bist_fail   <= 0;
                    bist_done   <= 0;

                    state <= WRITE_0;
                end

                // -------------------------------------------------
                // WRITE_0: write 0 to every cell (row-major)
                // -------------------------------------------------
                WRITE_0: begin
                    wr_en <= 1;
                    data_in <= '0;
                    expected_data <= '0;

                    // normal advance: col inner, then row
                    if (col_cnt == {COL_ADDR_WIDTH{1'b1}}) begin
                        col_cnt <= '0;
                        if (row_cnt == {ROW_ADDR_WIDTH{1'b1}}) begin
                            // finished last cell: move to read phase and start at 0,0
                            row_cnt <= '0;
                            col_cnt <= '0;
                            
                        end else begin
                            row_cnt <= row_cnt + 1;
                        end
                    end else begin
                        col_cnt <= col_cnt + 1;
                    end
                    state <= READ_0_WRITE_1;
                     //$display("write 0");
                end

                // -------------------------------------------------
                // READ_0_WRITE_1: read expecting 0, write 1
                // -------------------------------------------------
                READ_0_WRITE_1: begin
                    expected_data <= '0;

                    // check read result for current address
                    if (data_out !== expected_data) begin
                        detected_fault <= 1;
                        bist_fail <= 1;
                        if (f_index < MAX_FAULTS) begin
                            fault_list[f_index].row        <= row_cnt;
                            fault_list[f_index].col        <= col_cnt;
                            fault_list[f_index].fault_type <= 2'b00;
                            f_index     <= f_index + 1;
                            fault_count <= fault_count + 1;
                        end
                    end

                    // write 1 back
                    wr_en <= 1;
                    data_in <= '1;

                    // advance, same addressing scheme
                    if (col_cnt == {COL_ADDR_WIDTH{1'b1}}) begin
                        col_cnt <= '0;
                        if (row_cnt == {ROW_ADDR_WIDTH{1'b1}}) begin
                            // finished this pass -> start next read phase from 0,0
                            row_cnt <= '0;
                            col_cnt <= '0;
                            
                        end else begin
                            row_cnt <= row_cnt + 1;
                        end
                    end else begin
                        col_cnt <= col_cnt + 1;
                    end
                    state <= READ_1_WRITE_0;
                     //$display("read 0 write 1");
                end

                // -------------------------------------------------
                // READ_1_WRITE_0: read expecting 1, write 0
                // -------------------------------------------------
                READ_1_WRITE_0: begin
                    expected_data <= '1;

                    if (data_out !== expected_data) begin
                        detected_fault <= 1;
                        bist_fail <= 1;

                        if (f_index < MAX_FAULTS) begin
                            fault_list[f_index].row        <= row_cnt;
                            fault_list[f_index].col        <= col_cnt;
                            fault_list[f_index].fault_type <= 2'b00;
                            f_index     <= f_index + 1;
                            fault_count <= fault_count + 1;
                        end
                    end

                    // write 0 back
                    wr_en  <= 1;
                    data_in <= '0;

                    if (col_cnt == {COL_ADDR_WIDTH{1'b1}}) begin
                        col_cnt <= '0;
                        if (row_cnt == {ROW_ADDR_WIDTH{1'b1}}) begin
                            // finished last cell -> go DONE
                            row_cnt <= '0;
                            col_cnt <= '0;
                           
                        end else begin
                            row_cnt <= row_cnt + 1;
                        end
                    end else begin
                        col_cnt <= col_cnt + 1;
                    end
                     state <= DONE;
                   // $display("read 1 write 0");
                end

                // -------------------------------------------------
                // DONE: assert bist_done and stay here until reset
                // -------------------------------------------------
                DONE: begin
                    bist_done <= 1;
                    //$display("DONE state");
                    // remain in DONE; TB should pulse mbist_rst_n to run again
                    state <= DONE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
