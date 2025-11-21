//===========================================================
// Package for Common BIRA/MBIST Types
//===========================================================
package bira_pkg;

    typedef struct packed {
        logic [$bits(int)-1:0] row;
        logic [$bits(int)-1:0] col;
        logic [1:0] fault_type;  // 00: SA0, 01: SA1, 10: TF, 11: etc.
    } fault_rec_t;

endpackage
