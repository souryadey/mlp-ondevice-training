`timescale 1ns / 100ps

module tb_FF_processor_set #(
	parameter z = 32,
	parameter fi = 16,
	parameter width = 10, 
	parameter int_bits = 2, 
	parameter actfn = 0 //0 for sigmoid, 1 for ReLU
)(
);
	logic clk = 1;
	logic reset = 1;
	logic [width*z -1:0] act_in_package; //Process z input activations together, each width bits
	logic [width*z -1:0] wt_package; //Process z input weights together, each width bits
	logic [width*z/fi -1:0] bias_package; // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	logic [width*z/fi -1:0] act_out_package; //output actn values
	logic [width*z/fi -1:0] adot_out_package; //output sigmoid prime values (to be used for BP)

	FF_processor_set_pipelinemult1 #(
		.width(width),
		.z(z),
		.fi(fi),
		.int_bits(int_bits),
		.actfn(actfn)
	) FFps (
		.clk,
		.reset,
		.act_in_package,
		.wt_package,
		.bias_package,
		.act_out_package,
		.adot_out_package
	);
	
	always #5 clk=~clk;
	
	//Bigger cases
	/*initial begin
		integer i;
		act_in_package = '0;
		wt_package = '1;
		bias_package = '0;
		#20 $stop;
	end*/
	
	
	//Non-pipelined mode still needs a cycle to read act_function, so first result should come 1 cycle after reset becoming 0
    //In pipelined mode, first result should come after `MAXLOGFI+`PIPELINEMULT+1 + 1 (for act_function) cycles of reset becoming 0
	
	// For z = 32, fi = 16 
	initial begin
		act_in_package <= 320'h2000000000a0000000003000000000d800000000c000000000e00000000010000000000800000000;
		//n1: 1,0,0,0,-3,0,0,0,1.5,0,0,0,-1.25,0,0,0; n0: -2,0,0,0,-1,0,0,0,0.5,0,0,0,0.25,0,0,0
		wt_package <= 320'h200000000000000000003000000000d800000000e000000000e00000000010000000000800000000;
		//n1: 1,0,0,0,0,0,0,0,1.5,0,0,0,-1.25,0,0,0; n0: -1,0,0,0,-1,0,0,0,0.5,0,0,0,0.25,0,0,0
		bias_package <= 20'h86280;
		//n1: -(2.25+25/16); n0: -3
		//results n1: before act output = 1 = 080; sigmoid(1) = 05e, sigmoidprime(1) = 019, relu(1) = 07f, reluprime(1) = 001
		//results n0: before act output = 1/4+1/16 = 028; sigmoid() = 04a, sigmoidprime() = 01f, relu() = 028, reluprime() = 07f
		//combined: sigmoid = 1784a, sigmoidprime = 0641f, relu = 1fc28, reluprime = 0047f
		#101 reset = 0;
		#13;
		wt_package <= '0;
		bias_package <= 20'h00700;
		//n1: 1/128; n0: -2
        //results n1: before act output = 1/128 = 001; sigmoid() = 040, sigmoidprime() = 01f, relu() = 001, reluprime() = 07f
        //results n0: before act output = -2 = 300; sigmoid() = 00f, sigmoidprime() = 00d, relu() = 001, reluprime() = 001
        //combined: sigmoid = 1000f, sigmoidprime = 07c0d, relu = 00401, reluprime = 1fc01
		#23;
		bias_package <= '0;
        //both are 0
        //combined: sigmoid = 10040, sigmoidprime = 07c1f, relu = 00401, reluprime = 00401
		#105 $stop;
	end
endmodule