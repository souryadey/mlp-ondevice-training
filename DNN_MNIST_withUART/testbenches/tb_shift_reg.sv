`timescale 1ns / 1ps

module tb_shift_reg #(
	parameter width = 8,
	parameter depth = 1
)(
);

logic clk = 1;
logic reset = 1;
logic [width-1:0] d = '0;
logic [width-1:0] q = '0;

shift_reg #(
	.width(width),
	.depth(depth)
) sr_test (
	.clk,
	.reset,
	.d,
	.q
);

always #5 clk = ~clk;

initial begin
	#51 reset = 0;
	d = 8'hab;
	#12 d = 8'h34;
	#4 d = 8'h98;
	#10 d = 8'hf5;
	#50 $stop;
end

endmodule
