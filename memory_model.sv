module memory_model_2d #(
    parameter ROW_ADDR_BITS,
    parameter COL_ADDR_BITS,
    parameter DATA_WIDTH
) (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic [ROW_ADDR_BITS-1:0] row,
    input logic [COL_ADDR_BITS-1:0] col,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out
);

    logic [DATA_WIDTH-1:0] mem [0:(1<<ROW_ADDR_BITS)-1][0:(1<<COL_ADDR_BITS)-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < (1<<ROW_ADDR_BITS); i++)
            for (int j = 0; j < (1<<COL_ADDR_BITS); j++)
            
                mem[i][j] <= '0; 
        end else begin
        if (wr_en)
            mem[row][col] <= data_in;

        data_out <= mem[row][col];
    end
  end
endmodule
