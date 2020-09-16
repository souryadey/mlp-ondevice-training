`timescale 1ns / 1ps


module tb_adder #(
	parameter width = 10
)(
);

logic clk = 1;
logic reset = 1;
logic signed [width-1:0] a;
logic signed [width-1:0] b;
logic signed [width-1:0] s;

adder #(
	.width(width)
) adder_test (
	.clk,
	.reset,
	.a,
	.b,
	.s
);

always #5 clk = ~clk;

initial begin
    #21 reset = 0;
	a <= 10'b0111111111;
	b <= 10'b0111111111;
	// overflow, output should be 0111111111
	#12;
	b <= 10'b1100000000; //-256
	// output should be 0011111111
	#12;
	a <= 10'b1000000000; //-512
	b <= 10'b0111111111;
	// this output shouldn't reflect in reg mode, in comb mode output will be 1111111111, i.e. -1
	#3;
	a <= 10'b1000000001; //-511
	b <= 10'b1101001001;
	// overflow, output should be 1000000000
	#20 $stop;
end

endmodule
