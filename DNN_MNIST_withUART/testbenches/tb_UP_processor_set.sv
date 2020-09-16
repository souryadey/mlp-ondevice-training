`timescale 1ns / 1ps


module tb_UP_processor_set #(
    parameter z = 32,
    parameter fi = 16,
    parameter width = 10,
    parameter int_bits = 2,
    localparam frac_bits = width - int_bits -1
)(
);

    logic clk = 1;
	logic reset = 1;
	logic [$clog2(frac_bits+2)-1:0] etapos = 0;
	
	logic [width*z-1:0] wt_package = '0;
	logic [width*z/fi-1:0] bias_package = '0;
	
	logic [width*z-1:0] act_in_package;
	logic [width*z/fi-1:0] del_in_package;
	
	logic [width*z-1:0] wt_UP_package;
	logic [width*z/fi-1:0] bias_UP_package;
	
	UP_processor_set_pipelinemult1 #(
	   .z(z),
	   .fi(fi),
	   .width(width),
	   .int_bits(int_bits)
    ) UPps (
        .clk,
        .reset,
        .etapos,
        .del_in_package,
        .wt_package,
        .bias_package,
        .act_in_package,
        .wt_UP_package,
        .bias_UP_package
    );
    
    always #5 clk = ~clk;
    
    //Non-pipelined mode is combinational, first result should come as soon as reset is 0 and etapos is non-zero
    //In pipelined mode, first result should come after `MAXLOGFI+`PIPELINEMULT+1 cycles of reset becoming 0 and etapos becoming non-zero
    
    // For z = 32, fi = 16 
    initial begin
        del_in_package <= 20'h40180;
        //n1 = 2, n0 = 3
        act_in_package <= 320'h20080200802008020080200802008020080200808020080200802008020080200802008020080200;
        //all n1 = 1, all n0 = -4
        #91 reset = 0;
        #20 etapos = 2; //eta = 1/2
        //delta_bias = -1, -1.5, so bias_UP = -1, -1.5, so bias_UP_package = e0340
        //delta_wt = all n1 is -1, all n0 is 6 (i.e. overflow), so 3.99...
        //so wt_UP_package = e0380e0380e0380e0380e0380e0380e0380e03807fdff7fdff7fdff7fdff7fdff7fdff7fdff7fdff
        #13;
        etapos <= 1; //eta = 1
        act_in_package <= 320'he0380e0380e0380e0380e0380e0380e0380e03800000000000000000000000000000000000000000;
        //all n1 = -1, all n0 = 0
        //delta_bias = -2, -3, so bias_UP = -2, -3, so bias_UP_package = c0280
        //delta_wt = all n1 is 2, all n0 is 0
        //so wt_UP_package = 4010040100401004010040100401004010040100 0000000000000000000000000000000000000000
        #23;
        wt_package <= 320'h20080200802008020080200802008020080200800123456789abcdef0123456789abcdef01234567;
        //all n1 1, so wt_UP for n1 is all 3; wt_UP for n0 is same as wt for n0
        //so wt_UP_package = 60180601806018060180601806018060180601800123456789abcdef0123456789abcdef01234567
        bias_package <= 20'b00100000000111111111;
        //n1 is 1, n0 is max pos value, so bias_UP for n1 is -1, n0 is max fractional positive value
        //bias_UP_package = e007f
        #95 $stop;
    end

endmodule
