`timescale 1ns / 1ps


module tb_multiplier #(
    parameter mode = 2,
    parameter width = 10,
    parameter int_bits = 2
)(
);

logic clk = 1;
logic reset = 1;
logic signed [width-1:0] a;
logic signed [width-1:0] b;
logic signed [width-1:0] p;

multiplier #(
    .width(width),
    .mode(mode),
    .int_bits(int_bits)
) mult_test (
    .clk,
    .reset,
    .a,
    .b,
    .p
);

always #5 clk = ~clk;

initial begin
    a <= 10'b0111111111; //max pos value
    b <= 10'b0110000000; //3
    #51 reset = 0;
    // positive overflow, output should be 1ff
    #12;
    b <= 10'b1100000000; //-2
    // negative overflow, output should be 200
    #12;
    b <= 10'b1110000000; //-1
    // output should be 201 in comb mode
    #2;
    a <= 10'b1010101010;
    // output should be 156
    #11;
    b <= 10'b0010000000; //1
    // output should be 2aa
    #55 $stop; 
end

endmodule
