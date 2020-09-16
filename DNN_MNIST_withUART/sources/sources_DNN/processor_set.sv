/* This file contains all processor sets - feedforward, backpropagation, update - for 3 cases:
 * If neither `PIPELINEMULT nor `MAXLOGFI is defined:
    _nopipeline: Entirely combinational, output comes on same cycle (i.e. `PROCTIME=0)
 * If `PIPELINEMULT is defined to be 1 and `MAXLOGFI is not defined:
    _pipelinemult1: Only multipliers are pipelined to take 1 extra cycle, output comes after `PROCTIME=2 cycles (since BP has 2 multipliers)
 * If both `PIPELINEMULT and `MAXLOGFI are defined:
    _pipelinemultadd: Multipliers are pipelined to take `PIPELINEMULT extra cycles, adders are pipelined to take 1 cycle after each add, output comes after `PROCTIME=`PIPELINEMULT+~MAXLOGFI+1 cycles 
 */


/* Detailed explanation of _pipelinemult1 case
 
 * FF pipelining:
 ** `PIPELINEMULT=1 cycles to multiply and get actwt
 ** So delay bias by `PIPELINEMULT=1 cycles before passing to act_function module
 ** Tree adder output is delayed by 1 cycle
 ** So delay bias inside act_function by further 1 cycle
 ** Total delay = 2 cycles
 
 * BP pipelining:
 ** `PIPELINEMULT=1 cycles to multiply and get delta_act
 ** So need to delay weights by `PIPELINEMULT=1 cycles
 ** Another `PIPELINEMULT=1 cycles to multiply and get delta_wt
 ** So delay partial_del_out by 2*`PIPELINEMULT = 2 cycles
 ** Total delay = 2 cycles
 
 * UP pipelining:
 ** bias_UP comes out at beginning
 ** Need to delay bias_UP by 2 cycles
 ** `PIPELINEMULT=1 cycles to multiply and get delta_wt
 ** So need to delay wt by 1 cycle
 ** wt_UP comes out in the same cycle, so need to delay it by 1 cycle
 ** Total delay = 2 cycles
*/


/* Detailed explanation of _pipelinemultadd case, and why `PROCTIME = `MAXLOGFI + `PIPELINEMULT + 1
 
 * FF pipelining:
 ** `PIPELINEMULT cycles to multiply and get actwt
 ** So delay bias by `PIPELINEMULT cycles before passing to act_function module
 ** `MAXLOGFI cycles to do tree adder
 ** So delay bias inside act_function by further `MAXLOGFI cycles
 ** Finally, 1 more cycle to add bias
 
 * BP pipelining:
 ** `PIPELINEMULT cycles to multiply and get delta_act
 ** So need to delay weights by `PIPELINEMULT cycles
 ** Another `PIPELINEMULT cycles to multiply and get delta_wt
 ** So delay partial_del_out by 2*`PIPELINEMULT cycles
 ** 1 more cycle to add and get del_out
 ** Total cycles so far = 2*`PIPELINEMULT + 1
 ** So need to insert (`MAXLOGFI+`PIPELINEMULT+1)-(2*`PIPELINEMULT+1) = (`MAXLOGFI-`PIPELINEMULT) delay stages for del_out
 
 * UP pipelining:
 ** 1 cycle to add and get bias_UP
 ** So need to delay bias_UP by (`PIPELINEMULT+`MAXLOGFI+1)-1 = (`PIPELINEMULT+`MAXLOGFI) cycles
 ** `PIPELINEMULT cycles to multiply and then 1 cycle to add and get wt_UP
 ** So need to delay wt_UP by (`PIPELINEMULT+`MAXLOGFI+1)-(`PIPELINEMULT+1) = `MAXLOGFI cycles
*/

`timescale 1ns/100ps


//This module computes actn, i.e. z activations for the succeeding layer
//Multiplication aw = act*wt happens here, the remaining additions and looking up activation function is done in the submodule act_function

// CASE 1: _nopipeline
module FF_processor_set_nopipeline #(
	parameter fi = 4,
	parameter z = 8,
	parameter width = 16, 
	parameter int_bits = 5, 
	localparam frac_bits = width-int_bits-1,
	parameter actfn = 0 //0 for sigmoid, 1 for ReLU
)(
	input clk,
	input reset,
	input [width*z -1:0] act_in_package, //Process z input activations together, each width bits
	input [width*z -1:0] wt_package, //Process z input weights together, each width bits
	input [width*z/fi -1:0] bias_package, // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	output [width*z/fi -1:0] act_out_package, //output actn values
	output [width*z/fi -1:0] adot_out_package //output sigmoid prime values (to be used for BP)
);

	// unpack
	logic [width-1:0] act_in [z-1:0]; //assume always positive (true for sigmoid and relu)
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] bias [z/fi-1:0];
	logic [width-1:0] act_out [z/fi-1:0];
	logic [width-1:0] adot_out [z/fi-1:0];
	
	logic signed [width-1:0] actwt [z-1:0]; //act*wt
	logic [width*fi-1:0] actwt_package [z/fi-1:0]; //1 actwt_package value for each output neuron (total z/fi). Each has a width-bit value for each fi, so total width*fi
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign act_in[gv_i] = act_in_package[width*(gv_i+1)-1:width*gv_i];
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
	begin : package_n
		assign act_out_package[width*(gv_i+1)-1:width*gv_i] = act_out[gv_i];
		assign adot_out_package[width*(gv_i+1)-1:width*gv_i] = adot_out[gv_i];
		assign bias[gv_i] = bias_package[width*(gv_i+1)-1:width*gv_i];
		for (gv_j = 0; gv_j < fi; gv_j = gv_j + 1)
			assign actwt_package[gv_i][width*(gv_j+1)-1:width*gv_j] = actwt[gv_i*fi+gv_j];
	end
	endgenerate
	// Finished unpacking

	// Get actwt
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : FF_multiplier
		multiplier #(
			.mode(2), 
			.width(width), 
			.int_bits(int_bits)
		) mul (
			.clk,
			.reset,
			.a(act_in[gv_i]), 
			.b(wt[gv_i]), 
			.p(actwt[gv_i]) 
		);
	end
	endgenerate
	
	//Compute activations
    generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
    begin : act_function_set
        act_function_nopipeline #(
            .fi(fi),
            .width(width),
            .int_bits(int_bits),
            .actfn(actfn)
        ) a_function (
            .clk,
            .reset,
            .actwt_package(actwt_package[gv_i]),
            .bias(bias[gv_i]),
            .act_out(act_out[gv_i]),
            .adot_out(adot_out[gv_i])
        );	
    end
    endgenerate
endmodule

// Submodule of FF processor set
module act_function_nopipeline #( //Computes act and act prime for ONE NEURON
	parameter fi = 4,
	parameter width = 16,
	parameter int_bits = 5,
	localparam width_TA = width + $clog2(fi), //width of tree adder is not compromised
	parameter actfn = 0 //see FF_processor_set for definition
)(
	input clk,
	input reset,
	// All the following parameters are for 1 neuron
	input [width*fi-1:0] actwt_package,
	input signed [width-1:0] bias,
	output [width-1:0] act_out, //actn value
	output [width-1:0] adot_out //actn' value to be used in BP
);

	/* Create fi-to-1 tree adder
	This needs fi-1 adders in log(fi) stages [Eg: 4-to-1 tree adder needs 3 2-input adders, in 2 stages -- 2 in stage 1, 1 in stage 2]
	partial_s [0:fi-1] holds the fi aw values, [Eg 4 aw values] of the neuron in question
	partial_s needs fi-1 more values to hold adder outputs
	So total size of partial_s is 2*fi-1 [Eg: 7]
	pz[4] = pz[1]+pz[0], pz[5]=pz[3]+pz[2]
	Finally pz[6] = pz[4]+pz[5] */
	
	logic signed [width_TA-1:0] partial_s [2*fi-2:0];
	logic signed [width_TA-1:0] s_raw;
	logic signed [width-1:0] s;
	genvar gv_i, gv_j;
	
	// Sign extend 'width bit' actwt to 'width_TA bit'
	generate for (gv_i = 0; gv_i<fi; gv_i = gv_i + 1)
	begin : sign_extend_actwt
		assign partial_s[gv_i] = {{$clog2(fi) {actwt_package[width*(gv_i+1)-1]}}, actwt_package[width*(gv_i+1)-1:width*gv_i]};
	end
	endgenerate
	// [Eg Now partial_s[3,2,1,0] (each 16b) = actwt_package[63:48,47:32,31:16,15:0]]

	generate
		for (gv_i = 1; gv_i < $clog2(fi)+1; gv_i = gv_i + 1) begin : tree_adder_outer //This does tree adder computation, i.e. partial_s[f1] to partial_s[2*fi-2]
			for (gv_j = 0; gv_j < (fi/(2**gv_i)); gv_j = gv_j + 1) begin : tree_adder_inner
				if (gv_i<=2)
					adder #(
						.width(width_TA)
					) adder_tree_early (
						.clk,
						.reset,
						.a(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j]),
						.b(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j + 1]),
						.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
					);
				else
					adder #(
						.width(width_TA)
					) adder_tree_late (
						.clk,
						.reset,
						.a(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j]),
						.b(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j + 1]),
						.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
					);
			end	
		end
	endgenerate
	
    adder #(
        .width(width_TA)
    ) bias_adder (
        .clk,
        .reset,
        .a(partial_s[2*fi-2]),
        .b({{$clog2(fi) {bias[width-1]}}, bias}), //sign extension of 'width bit' bias to 'width_TA bit'
        .s(s_raw) //s_raw now has an extra portion consisting of width_TA-width bits and the regular width-bit portion
    );
	
	assign s = (s_raw[width_TA-1]==0 && s_raw[width_TA-2:width-1]!=0) ? //check that s_raw is positive and greater than max positive width-bit value
					{1'b0, {(width-1){1'b1}}} : //If yes, assign s to the max positive width-bit value
					(s_raw[width_TA-1]==1 && s_raw[width_TA-2:width-1]!={(width_TA-width){1'b1}}) ? //If no, now check that s_raw is negative and less than max negative width-bit value
					{1'b1, {(width-1){1'b0}}} : //If yes, assign s to the max negative width-bit value
					s_raw[width-1:0]; //If still no, then s_raw is between the limits allowed by width bits. So just assign s to the LSB width bits of s_raw
	
	generate //Choose activation function
		if (actfn==0) begin //sigmoid
			sigmoid_all #(
				.width(width),
				.int_bits(int_bits)
			) s_table (
				.clk,
				.val(s),
				.sigmoid_out(act_out),
				.sigmoid_prime_out(adot_out)
			);
		end else if (actfn==1) begin //ReLU
			relu_all #(
				.width(width),
				.int_bits(int_bits)
			) relu_calc (
				.clk,
				.val(s),
				.relu_out(act_out),
				.relu_prime_out(adot_out)
			);
		end
	endgenerate
endmodule


// CASE 2: _pipelinemult1
module FF_processor_set_pipelinemult1 #(
	parameter fi = 4,
	parameter z = 8,
	parameter width = 16, 
	parameter int_bits = 5, 
	localparam frac_bits = width-int_bits-1,
	parameter actfn = 0 //0 for sigmoid, 1 for ReLU
)(
	input clk,
	input reset,
	input [width*z -1:0] act_in_package, //Process z input activations together, each width bits
	input [width*z -1:0] wt_package, //Process z input weights together, each width bits
	input [width*z/fi -1:0] bias_package, // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	output [width*z/fi -1:0] act_out_package, //output actn values
	output [width*z/fi -1:0] adot_out_package //output sigmoid prime values (to be used for BP)
);

	// unpack
	logic [width-1:0] act_in [z-1:0]; //assume always positive (true for sigmoid and relu)
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] bias [z/fi-1:0];
	logic [width-1:0] act_out [z/fi-1:0];
	logic [width-1:0] adot_out [z/fi-1:0];
	
	logic signed [width-1:0] actwt [z-1:0]; //act*wt
	logic [width*fi-1:0] actwt_package [z/fi-1:0]; //1 actwt_package value for each output neuron (total z/fi). Each has a width-bit value for each fi, so total width*fi
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign act_in[gv_i] = act_in_package[width*(gv_i+1)-1:width*gv_i];
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
	begin : package_n
		assign act_out_package[width*(gv_i+1)-1:width*gv_i] = act_out[gv_i];
		assign adot_out_package[width*(gv_i+1)-1:width*gv_i] = adot_out[gv_i];
		assign bias[gv_i] = bias_package[width*(gv_i+1)-1:width*gv_i];
		for (gv_j = 0; gv_j < fi; gv_j = gv_j + 1)
			assign actwt_package[gv_i][width*(gv_j+1)-1:width*gv_j] = actwt[gv_i*fi+gv_j];
	end
	endgenerate
	// Finished unpacking

	// Get actwt
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : FF_multiplier //1 cycle delay
		multiplier #(
			.mode(2), 
			.width(width), 
			.int_bits(int_bits)
		) mul (
			.clk,
			.reset,
			.a(act_in[gv_i]), 
			.b(wt[gv_i]), 
			.p(actwt[gv_i]) 
		);
	end
	endgenerate
	
	//Compute activations
	
    logic signed [width-1:0] bias_delayed [z/fi-1:0];

    generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
    begin : delay_biases_and_act_function_set
        DFF #(
            .width(width)
        ) dff_bias (
            .clk,
            .reset,
            .d(bias[gv_i]),
            .q(bias_delayed[gv_i])
        );
        act_function_pipelinemult1 #(
            .fi(fi),
            .width(width),
            .int_bits(int_bits),
            .actfn(actfn)
        ) a_function (
            .clk,
            .reset,
            .actwt_package(actwt_package[gv_i]),
            .bias(bias_delayed[gv_i]),
            .act_out(act_out[gv_i]),
            .adot_out(adot_out[gv_i])
        );	
    end
    endgenerate
endmodule

// Submodule of FF processor set
module act_function_pipelinemult1 #( //Computes act and act prime for ONE NEURON
	parameter fi = 4,
	parameter width = 16,
	parameter int_bits = 5,
	localparam width_TA = width + $clog2(fi), //width of tree adder is not compromised
	parameter actfn = 0 //see FF_processor_set for definition
)(
	input clk,
	input reset,
	// All the following parameters are for 1 neuron
	input [width*fi-1:0] actwt_package,
	input signed [width-1:0] bias,
	output [width-1:0] act_out, //actn value
	output [width-1:0] adot_out //actn' value to be used in BP
);

	/* Create fi-to-1 tree adder
	This needs fi-1 adders in log(fi) stages [Eg: 4-to-1 tree adder needs 3 2-input adders, in 2 stages -- 2 in stage 1, 1 in stage 2]
	partial_s [0:fi-1] holds the fi aw values, [Eg 4 aw values] of the neuron in question
	partial_s needs fi-1 more values to hold adder outputs
	So total size of partial_s is 2*fi-1 [Eg: 7]
	pz[4] = pz[1]+pz[0], pz[5]=pz[3]+pz[2]
	Finally pz[6] = pz[4]+pz[5] */
	
	logic signed [width_TA-1:0] partial_s [2*fi-2:0];
	logic signed [width_TA-1:0] s_raw;
	logic signed [width-1:0] s;
	genvar gv_i, gv_j;
	
	// Sign extend 'width bit' actwt to 'width_TA bit'
	generate for (gv_i = 0; gv_i<fi; gv_i = gv_i + 1)
	begin : sign_extend_actwt
		assign partial_s[gv_i] = {{$clog2(fi) {actwt_package[width*(gv_i+1)-1]}}, actwt_package[width*(gv_i+1)-1:width*gv_i]};
	end
	endgenerate
	// [Eg Now partial_s[3,2,1,0] (each 16b) = actwt_package[63:48,47:32,31:16,15:0]]

	generate
		for (gv_i = 1; gv_i < $clog2(fi)+1; gv_i = gv_i + 1) begin : tree_adder_outer //This does tree adder computation, i.e. partial_s[f1] to partial_s[2*fi-2]
			for (gv_j = 0; gv_j < (fi/(2**gv_i)); gv_j = gv_j + 1) begin : tree_adder_inner
				if (gv_i<=2)
					adder #(
						.width(width_TA)
					) adder_tree_early (
						.clk,
						.reset,
						.a(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j]),
						.b(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j + 1]),
						.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
					);
				else
					adder #(
						.width(width_TA)
					) adder_tree_late (
						.clk,
						.reset,
						.a(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j]),
						.b(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j + 1]),
						.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
					);
			end	
		end
	endgenerate
	
    logic signed [width-1:0] bias_delayed; //delay bias since tree adder has a register at end
    logic signed [width_TA-1:0] partial_s_final; //final output of tree adder after register
    
    DFF #(
        .width(width)
    ) dff_bias (
        .clk,
        .reset,
        .d(bias),
        .q(bias_delayed)
    );
    
    DFF #(
        .width(width_TA)
    ) dff_partial_s (
        .clk,
        .reset,
        .d(partial_s[2*fi-2]),
        .q(partial_s_final)
    );

    adder #(
        .width(width_TA)
    ) bias_adder (
        .clk,
        .reset,
        .a(partial_s_final),
        .b({{$clog2(fi) {bias_delayed[width-1]}}, bias_delayed}), //sign extension of 'width bit' bias_delayed to 'width_TA bit'
        .s(s_raw) //s_raw now has an extra portion consisting of width_TA-width bits and the regular width-bit portion
    );
	
	assign s = (s_raw[width_TA-1]==0 && s_raw[width_TA-2:width-1]!=0) ? //check that s_raw is positive and greater than max positive width-bit value
					{1'b0, {(width-1){1'b1}}} : //If yes, assign s to the max positive width-bit value
					(s_raw[width_TA-1]==1 && s_raw[width_TA-2:width-1]!={(width_TA-width){1'b1}}) ? //If no, now check that s_raw is negative and less than max negative width-bit value
					{1'b1, {(width-1){1'b0}}} : //If yes, assign s to the max negative width-bit value
					s_raw[width-1:0]; //If still no, then s_raw is between the limits allowed by width bits. So just assign s to the LSB width bits of s_raw
	
	generate //Choose activation function
		if (actfn==0) begin //sigmoid
			sigmoid_all #(
				.width(width),
				.int_bits(int_bits)
			) s_table (
				.clk,
				.val(s),
				.sigmoid_out(act_out),
				.sigmoid_prime_out(adot_out)
			);
		end else if (actfn==1) begin //ReLU
			relu_all #(
				.width(width),
				.int_bits(int_bits)
			) relu_calc (
				.clk,
				.val(s),
				.relu_out(act_out),
				.relu_prime_out(adot_out)
			);
		end
	endgenerate
endmodule


// CASE 3: _pipelinemultadd
module FF_processor_set_pipelinemultadd #(
	parameter fi = 4,
	parameter z = 8,
	parameter width = 16, 
	parameter int_bits = 5, 
	localparam frac_bits = width-int_bits-1,
	parameter actfn = 0 //0 for sigmoid, 1 for ReLU
)(
	input clk,
	input reset,
	input [width*z -1:0] act_in_package, //Process z input activations together, each width bits
	input [width*z -1:0] wt_package, //Process z input weights together, each width bits
	input [width*z/fi -1:0] bias_package, // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	output [width*z/fi -1:0] act_out_package, //output actn values
	output [width*z/fi -1:0] adot_out_package //output sigmoid prime values (to be used for BP)
);

	// unpack
	logic [width-1:0] act_in [z-1:0]; //assume always positive (true for sigmoid and relu)
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] bias [z/fi-1:0];
	logic [width-1:0] act_out [z/fi-1:0];
	logic [width-1:0] adot_out [z/fi-1:0];
	
	logic signed [width-1:0] actwt [z-1:0]; //act*wt
	logic [width*fi-1:0] actwt_package [z/fi-1:0]; //1 actwt_package value for each output neuron (total z/fi). Each has a width-bit value for each fi, so total width*fi
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign act_in[gv_i] = act_in_package[width*(gv_i+1)-1:width*gv_i];
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
	begin : package_n
		assign act_out_package[width*(gv_i+1)-1:width*gv_i] = act_out[gv_i];
		assign adot_out_package[width*(gv_i+1)-1:width*gv_i] = adot_out[gv_i];
		assign bias[gv_i] = bias_package[width*(gv_i+1)-1:width*gv_i];
		for (gv_j = 0; gv_j < fi; gv_j = gv_j + 1)
			assign actwt_package[gv_i][width*(gv_j+1)-1:width*gv_j] = actwt[gv_i*fi+gv_j];
	end
	endgenerate
	// Finished unpacking

	// Get actwt
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : FF_multiplier
		multiplier #(
			.mode(2), 
			.width(width), 
			.int_bits(int_bits)
		) mul (
			.clk,
			.reset,
			.a(act_in[gv_i]), 
			.b(wt[gv_i]), 
			.p(actwt[gv_i]) 
		);
	end
	endgenerate
	
	//Compute activations
	
    logic signed [width-1:0] bias_delayed [z/fi-1:0];
    
    `ifdef PIPELINEMULT
        generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
        begin : delay_biases_and_act_function_set
            shift_reg #(
                .width(width),
                .depth(`PIPELINEMULT)
            ) sr_bias (
                .clk,
                .reset,
                .d(bias[gv_i]),
                .q(bias_delayed[gv_i])
            );
            act_function_pipelinemultadd #(
                .fi(fi),
                .width(width),
                .int_bits(int_bits),
                .actfn(actfn)
            ) a_function (
                .clk,
                .reset,
                .actwt_package(actwt_package[gv_i]),
                .bias(bias_delayed[gv_i]),
                .act_out(act_out[gv_i]),
                .adot_out(adot_out[gv_i])
            );	
        end
        endgenerate
    `endif
endmodule

// Submodule of FF processor set
module act_function_pipelinemultadd #( //Computes act and act prime for ONE NEURON
	parameter fi = 4,
	parameter width = 16,
	parameter int_bits = 5,
	localparam width_TA = width + $clog2(fi), //width of tree adder is not compromised
	parameter actfn = 0 //see FF_processor_set for definition
)(
	input clk,
	input reset,
	// All the following parameters are for 1 neuron
	input [width*fi-1:0] actwt_package,
	input signed [width-1:0] bias,
	output [width-1:0] act_out, //actn value
	output [width-1:0] adot_out //actn' value to be used in BP
);

	/* Create fi-to-1 tree adder
	This needs fi-1 adders in log(fi) stages [Eg: 4-to-1 tree adder needs 3 2-input adders, in 2 stages -- 2 in stage 1, 1 in stage 2]
	partial_s [0:fi-1] holds the fi aw values, [Eg 4 aw values] of the neuron in question
	partial_s needs fi-1 more values to hold adder outputs
	So total size of partial_s is 2*fi-1 [Eg: 7]
	pz[4] = pz[1]+pz[0], pz[5]=pz[3]+pz[2]
	Finally pz[6] = pz[4]+pz[5] */
	
	logic signed [width_TA-1:0] partial_s [2*fi-2:0];
	logic signed [width_TA-1:0] s_raw;
	logic signed [width-1:0] s;
	genvar gv_i, gv_j;
	
	// Sign extend 'width bit' actwt to 'width_TA bit'
	generate for (gv_i = 0; gv_i<fi; gv_i = gv_i + 1)
	begin : sign_extend_actwt
		assign partial_s[gv_i] = {{$clog2(fi) {actwt_package[width*(gv_i+1)-1]}}, actwt_package[width*(gv_i+1)-1:width*gv_i]};
	end
	endgenerate
	// [Eg Now partial_s[3,2,1,0] (each 16b) = actwt_package[63:48,47:32,31:16,15:0]]

	generate
		for (gv_i = 1; gv_i < $clog2(fi)+1; gv_i = gv_i + 1) begin : tree_adder_outer //This does tree adder computation, i.e. partial_s[f1] to partial_s[2*fi-2]
			for (gv_j = 0; gv_j < (fi/(2**gv_i)); gv_j = gv_j + 1) begin : tree_adder_inner
				if (gv_i<=2)
					adder #(
						.width(width_TA)
					) adder_tree_early (
						.clk,
						.reset,
						.a(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j]),
						.b(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j + 1]),
						.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
					);
				else
					adder #(
						.width(width_TA)
					) adder_tree_late (
						.clk,
						.reset,
						.a(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j]),
						.b(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j + 1]),
						.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
					);
			end	
		end
	endgenerate
	
    logic signed [width-1:0] bias_delayed; //delay bias since tree adder is now pipelined
    logic signed [width_TA-1:0] partial_s_final; //accounts for delays in tree adder path if required
    
    `ifdef MAXLOGFI
        shift_reg #(
            .width(width),
            .depth(`MAXLOGFI)
        ) sr_bias_big (
            .clk,
            .reset,
            .d(bias),
            .q(bias_delayed)
        );
        
        generate
            // If log(fi) is not as big as MAXLOGFI, there need to be extra delay cycles for the final tree adder output : partial_s[2*fi-2]
            // This is done to balance the tree adder pipeline stages across junctions
            if (`MAXLOGFI > $clog2(fi))
                shift_reg #(
                    .width(width_TA),
                    .depth(`MAXLOGFI-$clog2(fi))
                ) sr_partial_s_adjust (
                    .clk,
                    .reset,
                    .d(partial_s[2*fi-2]),
                    .q(partial_s_final)
                );
            else
                assign partial_s_final = partial_s[2*fi-2];
        endgenerate
    `endif

    adder #(
        .width(width_TA)
    ) bias_adder (
        .clk,
        .reset,
        .a(partial_s_final),
        .b({{$clog2(fi) {bias_delayed[width-1]}}, bias_delayed}), //sign extension of 'width bit' bias_delayed to 'width_TA bit'
        .s(s_raw) //s_raw now has an extra portion consisting of width_TA-width bits and the regular width-bit portion
    );
	
	assign s = (s_raw[width_TA-1]==0 && s_raw[width_TA-2:width-1]!=0) ? //check that s_raw is positive and greater than max positive width-bit value
					{1'b0, {(width-1){1'b1}}} : //If yes, assign s to the max positive width-bit value
					(s_raw[width_TA-1]==1 && s_raw[width_TA-2:width-1]!={(width_TA-width){1'b1}}) ? //If no, now check that s_raw is negative and less than max negative width-bit value
					{1'b1, {(width-1){1'b0}}} : //If yes, assign s to the max negative width-bit value
					s_raw[width-1:0]; //If still no, then s_raw is between the limits allowed by width bits. So just assign s to the LSB width bits of s_raw
	
	generate //Choose activation function
		if (actfn==0) begin //sigmoid
			sigmoid_all #(
				.width(width),
				.int_bits(int_bits)
			) s_table (
				.clk,
				.val(s),
				.sigmoid_out(act_out),
				.sigmoid_prime_out(adot_out)
			);
		end else if (actfn==1) begin //ReLU
			relu_all #(
				.width(width),
				.int_bits(int_bits)
			) relu_calc (
				.clk,
				.val(s),
				.relu_out(act_out),
				.relu_prime_out(adot_out)
			);
		end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

//This module computes delp, i.e. z activations for the preceding layer

// CASE 1: _nopipeline
module BP_processor_set_nopipeline #(
	parameter fi  = 4,
	parameter z  = 8,
	parameter width = 16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1
)(
	input clk,
	input reset,
	input [width*z/fi-1:0] del_in_package, //input deln values
	input [width*z -1:0] adot_out_package, //z weights can belong to z different p layer neurons, so we have z adot_out values
	input [width*z -1:0] wt_package,
	input [width*z -1:0] partial_del_out_package, //partial del values being constructed
	output [width*z -1:0] del_out_package //delp values
);

	// Unpack
	logic signed [width-1:0] del_in [z/fi-1:0];
	logic [width-1:0] adot_out [z-1:0];
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] partial_del_out [z-1:0];
	logic signed [width-1:0] del_out [z-1:0];
	
	logic signed [width-1:0] delta_act [z-1:0];
	logic signed [width-1:0] delta_wt [z-1:0];
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign adot_out[gv_i] = adot_out_package[width*(gv_i+1)-1:width*gv_i];
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
		assign partial_del_out[gv_i] = partial_del_out_package[width*(gv_i+1)-1:width*gv_i];
		assign del_out_package[width*(gv_i+1)-1:width*gv_i] = del_out[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign del_in[gv_i] = del_in_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	// Finished unpacking

    generate
    for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1) begin : delta_accumulation_set
        for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1) begin : delta_accumulation
        // [Eg for ppt example: Note that (w.d).f'(z) can be written as w0*d0*f'(z0) + w1*d0*f'(z0) + ... and then later ... w36*d2*f'(z2) ... and so on]
            multiplier #(
                .mode(2), 
                .width(width),
                .int_bits(int_bits)
            ) a_d (
                .clk,
                .reset,
                .a(del_in[gv_i]), 
                .b(adot_out[gv_i*fi+gv_j]), 
                .p(delta_act[gv_i*fi+gv_j])
            ); //delta_act = d*f'
            
            multiplier #(
                .mode(2), 
                .width(width),
                .int_bits(int_bits)
            ) w_d (
                .clk,
                .reset,
                .a(delta_act[gv_i*fi+gv_j]), 
                .b(wt[gv_i*fi+gv_j]), 
                .p(delta_wt[gv_i*fi+gv_j])
            ); //delta_wt = w*d*f'
            
            adder #(
                .width(width)
            ) acc (
                .clk,
                .reset,
                .a(delta_wt[gv_i*fi+gv_j]),
                .b(partial_del_out[gv_i*fi+gv_j]),
                .s(del_out[gv_i*fi+gv_j])
            ); //Add above to respective del value
        end
    end
    endgenerate
endmodule


// CASE 2: _pipelinemult1
module BP_processor_set_pipelinemult1 #(
	parameter fi  = 4,
	parameter z  = 8,
	parameter width = 16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1
)(
	input clk,
	input reset,
	input [width*z/fi-1:0] del_in_package, //input deln values
	input [width*z -1:0] adot_out_package, //z weights can belong to z different p layer neurons, so we have z adot_out values
	input [width*z -1:0] wt_package,
	input [width*z -1:0] partial_del_out_package, //partial del values being constructed
	output [width*z -1:0] del_out_package //delp values
);

	// Unpack
	logic signed [width-1:0] del_in [z/fi-1:0];
	logic [width-1:0] adot_out [z-1:0];
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] partial_del_out [z-1:0];
	logic signed [width-1:0] del_out [z-1:0];
	
	logic signed [width-1:0] delta_act [z-1:0];
	logic signed [width-1:0] delta_wt [z-1:0];
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign adot_out[gv_i] = adot_out_package[width*(gv_i+1)-1:width*gv_i];
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
		assign partial_del_out[gv_i] = partial_del_out_package[width*(gv_i+1)-1:width*gv_i];
		assign del_out_package[width*(gv_i+1)-1:width*gv_i] = del_out[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign del_in[gv_i] = del_in_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	// Finished unpacking
		
    logic signed [width-1:0] wt_delayed [z-1:0];
    logic signed [width-1:0] partial_del_out_delayed [z-1:0];
    
    generate
    for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1) begin : delta_accumulation_set
        for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1) begin : delta_accumulation
        // [Eg for ppt example: Note that (w.d).f'(z) can be written as w0*d0*f'(z0) + w1*d0*f'(z0) + ... and then later ... w36*d2*f'(z2) ... and so on]
            multiplier #( //1 cycle delay
                .mode(2), 
                .width(width),
                .int_bits(int_bits)
            ) a_d (
                .clk,
                .reset,
                .a(del_in[gv_i]), 
                .b(adot_out[gv_i*fi+gv_j]), 
                .p(delta_act[gv_i*fi+gv_j])
            ); //delta_act = d*f'
            
            // Delay weights to sync them with delta_act
            DFF #(
                .width(width)
            ) dff_wts (
                .clk,
                .reset,
                .d(wt[gv_i*fi+gv_j]),
                .q(wt_delayed[gv_i*fi+gv_j])
            );
            
            multiplier #( //1 cycle
                .mode(2), 
                .width(width),
                .int_bits(int_bits)
            ) w_d (
                .clk,
                .reset,
                .a(delta_act[gv_i*fi+gv_j]), 
                .b(wt_delayed[gv_i*fi+gv_j]), 
                .p(delta_wt[gv_i*fi+gv_j])
            ); //delta_wt = w*d*f'
            
            // Delay partial_del_outs to sync them with delta_wt
            shift_reg #(
                .width(width),
                .depth(2)
            ) sr_partial_del_outs (
                .clk,
                .reset,
                .d(partial_del_out[gv_i*fi+gv_j]),
                .q(partial_del_out_delayed[gv_i*fi+gv_j])
            );
            
            adder #(
                .width(width)
            ) acc (
                .clk,
                .reset,
                .a(delta_wt[gv_i*fi+gv_j]),
                .b(partial_del_out_delayed[gv_i*fi+gv_j]),
                .s(del_out[gv_i*fi+gv_j])
            ); //Add above to respective del value
        end
    end
    endgenerate
endmodule


// CASE 3: _pipelinemultadd
module BP_processor_set_pipelinemultadd #(
	parameter fi  = 4,
	parameter z  = 8,
	parameter width = 16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1
)(
	input clk,
	input reset,
	input [width*z/fi-1:0] del_in_package, //input deln values
	input [width*z -1:0] adot_out_package, //z weights can belong to z different p layer neurons, so we have z adot_out values
	input [width*z -1:0] wt_package,
	input [width*z -1:0] partial_del_out_package, //partial del values being constructed
	output [width*z -1:0] del_out_package //delp values
);

	// Unpack
	logic signed [width-1:0] del_in [z/fi-1:0];
	logic [width-1:0] adot_out [z-1:0];
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] partial_del_out [z-1:0];
	logic signed [width-1:0] del_out [z-1:0];
	
	logic signed [width-1:0] delta_act [z-1:0];
	logic signed [width-1:0] delta_wt [z-1:0];
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign adot_out[gv_i] = adot_out_package[width*(gv_i+1)-1:width*gv_i];
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
		assign partial_del_out[gv_i] = partial_del_out_package[width*(gv_i+1)-1:width*gv_i];
		assign del_out_package[width*(gv_i+1)-1:width*gv_i] = del_out[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign del_in[gv_i] = del_in_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	// Finished unpacking

    logic signed [width-1:0] wt_delayed [z-1:0];
    logic signed [width-1:0] partial_del_out_delayed [z-1:0];
    logic signed [width-1:0] del_out_undelayed [z-1:0];
    
    `ifdef PIPELINEMULT
    `ifdef MAXLOGFI
        generate
        for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1) begin : delta_accumulation_set
            for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1) begin : delta_accumulation
            // [Eg for ppt example: Note that (w.d).f'(z) can be written as w0*d0*f'(z0) + w1*d0*f'(z0) + ... and then later ... w36*d2*f'(z2) ... and so on]
                multiplier #(
                    .mode(2), 
                    .width(width),
                    .int_bits(int_bits)
                ) a_d (
                    .clk,
                    .reset,
                    .a(del_in[gv_i]), 
                    .b(adot_out[gv_i*fi+gv_j]), 
                    .p(delta_act[gv_i*fi+gv_j])
                ); //delta_act = d*f'
                
                // Delay weights to sync them with delta_act
                shift_reg #(
                    .width(width),
                    .depth(`PIPELINEMULT)
                ) sr_wts (
                    .clk,
                    .reset,
                    .d(wt[gv_i*fi+gv_j]),
                    .q(wt_delayed[gv_i*fi+gv_j])
                );
                
                multiplier #(
                    .mode(2), 
                    .width(width),
                    .int_bits(int_bits)
                ) w_d (
                    .clk,
                    .reset,
                    .a(delta_act[gv_i*fi+gv_j]), 
                    .b(wt_delayed[gv_i*fi+gv_j]), 
                    .p(delta_wt[gv_i*fi+gv_j])
                ); //delta_wt = w*d*f'
                
                // Delay partial_del_outs to sync them with delta_wt
                shift_reg #(
                    .width(width),
                    .depth(2*`PIPELINEMULT)
                ) sr_partial_del_outs (
                    .clk,
                    .reset,
                    .d(partial_del_out[gv_i*fi+gv_j]),
                    .q(partial_del_out_delayed[gv_i*fi+gv_j])
                );
                
                adder #(
                    .width(width)
                ) acc (
                    .clk,
                    .reset,
                    .a(delta_wt[gv_i*fi+gv_j]),
                    .b(partial_del_out_delayed[gv_i*fi+gv_j]),
                    .s(del_out_undelayed[gv_i*fi+gv_j])
                ); //Add above to respective del value
                
                // Get final del_outs after delaying, so that BP takes same #cycles as other ops
                shift_reg #(
                    .width(width),
                    .depth(`MAXLOGFI-`PIPELINEMULT) //(`PIPELINEMULT+`MAXLOGFI+1) - (2*'PIPELINEMULT+1) = `MAXLOGFI-`PIPELINEMULT
                ) sr_final_del_outs (
                    .clk,
                    .reset,
                    .d(del_out_undelayed[gv_i*fi+gv_j]),
                    .q(del_out[gv_i*fi+gv_j])
                );
            end
        end
        endgenerate
    `endif
    `endif
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

// This module computes updates to z weights and z/fi biases

// CASE 1: _nopipeline
module UP_processor_set_nopipeline #(
	parameter fi  = 4,
	parameter z  = 4,
	parameter width = 16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1 //No. of bits in fractional part
	//parameter eta = 0.05
)(
	input clk,
	input reset,
	// Note that updates are done for z weights in a junction and n neurons in succeeding layer
	input [$clog2(frac_bits+2)-1:0] etapos,
	input [width*z/fi-1:0] del_in_package, //deln
	input [width*z-1:0] wt_package, //Existing weights whose values will be updated
	input [width*z/fi-1:0] bias_package, //Existing bias of n neurons whose values will be updated
	input [width*z-1:0] act_in_package, //actp
	output [width*z-1:0] wt_UP_package, //Output weights after update
	output [width*z/fi-1:0] bias_UP_package //Output biases after update
);

	//reg [width-1:0] Eta = -eta*2**frac_bits;
	
	// Unpack
	logic [width-1:0] act_in [z-1:0];
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] bias [z/fi-1:0];
	logic signed [width-1:0] del_in [z/fi-1:0];
	logic signed [width-1:0] del_in_neg [z/fi-1:0]; //Stores negative values of deltas
	
	logic signed [width-1:0] delta_bias [z/fi-1:0];
	logic signed [width-1:0] delta_bias_temp [z/fi-1:0]; //Temporarily stores values of delta_bias
	logic signed [width-1:0] bias_UP [z/fi-1:0];
	
	logic signed [width-1:0] delta_wt [z-1:0];
	logic signed [width-1:0] wt_UP [z-1:0];

	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
		assign act_in[gv_i] = act_in_package[width*(gv_i+1)-1:width*gv_i];
		assign wt_UP_package[width*(gv_i+1)-1:width*gv_i] = wt_UP[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign del_in[gv_i] = del_in_package[width*(gv_i+1)-1:width*gv_i];
		assign bias[gv_i] = bias_package[width*(gv_i+1)-1:width*gv_i];
		assign bias_UP_package[width*(gv_i+1)-1:width*gv_i] = bias_UP[gv_i];
	end
	endgenerate
	// Finished unpacking

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : get_delta_biases
		//`ifdef ETA2POWER	
		assign del_in_neg[gv_i] = (del_in[gv_i] == {1'b1,{(width-1){1'b0}}}) ? {1'b0,{(width-1){1'b1}}} : -del_in[gv_i]; //If del_in is neg max, then we need to explicitly specify that its negative is pos max
		assign delta_bias_temp[gv_i] = (etapos==0) ? 0 : //If etapos=0, operation hasn't started
				del_in_neg[gv_i]>>>(etapos-1); //Otherwise usual case: delta_bias_temp = -del_in*eta
		assign delta_bias[gv_i] = (etapos<=1) ? delta_bias_temp[gv_i] : // If etapos=1, the actual Eta=1, so there is no shift, and hence no rounding
				delta_bias_temp[gv_i] + del_in_neg[gv_i][etapos-2]; //Otherwise round, i.e. add 1 if MSB of shifted out portion = 1	
		/*`else //if eta is not a power of 2
			multiplier #(
				.mode(1),
				.width(width),
				.int_bits(int_bits)
			) mul_eta (
				.clk,
				.reset,
				.a(del_in[gv_i]),
				.b(eta),
				.p(delta_bias[gv_i])
			);
		`endif*/
	end
	endgenerate
	
    generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
    begin : updates_outer	
        adder #(
            .width(width)
        ) update_b (
            .clk,
            .reset,
            .a(bias[gv_i]),
            .b(delta_bias[gv_i]),
            .s(bias_UP[gv_i])
        );
        
        for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1)
        begin : updates_inner
            multiplier #(
                .mode(1),
                .width(width),
                .int_bits(int_bits)
            ) mul_act_del (
                .clk,
                .reset,
                .a(delta_bias[gv_i]), 
                .b(act_in[gv_i*fi+gv_j]), 
                .p(delta_wt[gv_i*fi+gv_j])
            );
            
            adder #(
                .width(width)
            ) update_wt (
                .clk,
                .reset,
                .a(wt[gv_i*fi+gv_j]),
                .b(delta_wt[gv_i*fi+gv_j]),
                .s(wt_UP[gv_i*fi+gv_j])
            );
        end
    end
    endgenerate
endmodule



// CASE 2: _pipelinemult1
module UP_processor_set_pipelinemult1 #(
	parameter fi  = 4,
	parameter z  = 4,
	parameter width =16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1 //No. of bits in fractional part
	//parameter eta = 0.05
)(
	input clk,
	input reset,
	// Note that updates are done for z weights in a junction and n neurons in succeeding layer
	input [$clog2(frac_bits+2)-1:0] etapos,
	input [width*z/fi-1:0] del_in_package, //deln
	input [width*z-1:0] wt_package, //Existing weights whose values will be updated
	input [width*z/fi-1:0] bias_package, //Existing bias of n neurons whose values will be updated
	input [width*z-1:0] act_in_package, //actp
	output [width*z-1:0] wt_UP_package, //Output weights after update
	output [width*z/fi-1:0] bias_UP_package //Output biases after update
);

	//reg [width-1:0] Eta = -eta*2**frac_bits;
	
	// Unpack
	logic [width-1:0] act_in [z-1:0];
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] bias [z/fi-1:0];
	logic signed [width-1:0] del_in [z/fi-1:0];
	logic signed [width-1:0] del_in_neg [z/fi-1:0]; //Stores negative values of deltas
	
	logic signed [width-1:0] delta_bias [z/fi-1:0];
	logic signed [width-1:0] delta_bias_temp [z/fi-1:0]; //Temporarily stores values of delta_bias
	logic signed [width-1:0] bias_UP [z/fi-1:0];
	
	logic signed [width-1:0] delta_wt [z-1:0];
	logic signed [width-1:0] wt_UP [z-1:0];

	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
		assign act_in[gv_i] = act_in_package[width*(gv_i+1)-1:width*gv_i];
		assign wt_UP_package[width*(gv_i+1)-1:width*gv_i] = wt_UP[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign del_in[gv_i] = del_in_package[width*(gv_i+1)-1:width*gv_i];
		assign bias[gv_i] = bias_package[width*(gv_i+1)-1:width*gv_i];
		assign bias_UP_package[width*(gv_i+1)-1:width*gv_i] = bias_UP[gv_i];
	end
	endgenerate
	// Finished unpacking

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : get_delta_biases
		//`ifdef ETA2POWER	
		assign del_in_neg[gv_i] = (del_in[gv_i] == {1'b1,{(width-1){1'b0}}}) ? {1'b0,{(width-1){1'b1}}} : -del_in[gv_i]; //If del_in is neg max, then we need to explicitly specify that its negative is pos max
		assign delta_bias_temp[gv_i] = (etapos==0) ? 0 : //If etapos=0, operation hasn't started
				del_in_neg[gv_i]>>>(etapos-1); //Otherwise usual case: delta_bias_temp = -del_in*eta
		assign delta_bias[gv_i] = (etapos<=1) ? delta_bias_temp[gv_i] : // If etapos=1, the actual Eta=1, so there is no shift, and hence no rounding
				delta_bias_temp[gv_i] + del_in_neg[gv_i][etapos-2]; //Otherwise round, i.e. add 1 if MSB of shifted out portion = 1	
		/*`else //if eta is not a power of 2
			multiplier #(
				.mode(1),
				.width(width),
				.int_bits(int_bits)
			) mul_eta (
				.clk,
				.reset,
				.a(del_in[gv_i]),
				.b(eta),
				.p(delta_bias[gv_i])
			);
		`endif*/
	end
	endgenerate
	
    logic signed [width-1:0] wt_delayed [z-1:0];
    logic signed [width-1:0] wt_UP_undelayed [z-1:0];
    logic signed [width-1:0] bias_UP_undelayed [z/fi-1:0];
    
    generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
    begin : updates_outer
        adder #(
            .width(width)
        ) update_b (
            .clk,
            .reset,
            .a(bias[gv_i]),
            .b(delta_bias[gv_i]),
            .s(bias_UP_undelayed[gv_i])
        );
        
        shift_reg #(
            .width(width),
            .depth(2)
        ) sr_final_bias_UP (
            .clk,
            .reset,
            .d(bias_UP_undelayed[gv_i]),
            .q(bias_UP[gv_i])
        );
        
        for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1)
        begin : updates_inner
            multiplier #( //1 cycle
                .mode(1),
                .width(width),
                .int_bits(int_bits)
            ) mul_act_del (
                .clk,
                .reset,
                .a(delta_bias[gv_i]), 
                .b(act_in[gv_i*fi+gv_j]), 
                .p(delta_wt[gv_i*fi+gv_j])
            );
            
            DFF #(
                .width(width)
            ) dff_delay_wts_forUP (
                .clk,
                .reset,
                .d(wt[gv_i*fi+gv_j]),
                .q(wt_delayed[gv_i*fi+gv_j])
            );
            
            adder #(
                .width(width)
            ) update_wt (
                .clk,
                .reset,
                .a(wt_delayed[gv_i*fi+gv_j]),
                .b(delta_wt[gv_i*fi+gv_j]),
                .s(wt_UP_undelayed[gv_i*fi+gv_j])
            );
            
            DFF #(
                .width(width)
            ) dff_final_wt_UP (
                .clk,
                .reset,
                .d(wt_UP_undelayed[gv_i*fi+gv_j]),
                .q(wt_UP[gv_i*fi+gv_j])
            );
        end
    end
    endgenerate
endmodule


// CASE 3: _pipelinemultadd
module UP_processor_set_pipelinemultadd #(
	parameter fi  = 4,
	parameter z  = 4,
	parameter width =16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1 //No. of bits in fractional part
	//parameter eta = 0.05
)(
	input clk,
	input reset,
	// Note that updates are done for z weights in a junction and n neurons in succeeding layer
	input [$clog2(frac_bits+2)-1:0] etapos,
	input [width*z/fi-1:0] del_in_package, //deln
	input [width*z-1:0] wt_package, //Existing weights whose values will be updated
	input [width*z/fi-1:0] bias_package, //Existing bias of n neurons whose values will be updated
	input [width*z-1:0] act_in_package, //actp
	output [width*z-1:0] wt_UP_package, //Output weights after update
	output [width*z/fi-1:0] bias_UP_package //Output biases after update
);

	//reg [width-1:0] Eta = -eta*2**frac_bits;
	
	// Unpack
	logic [width-1:0] act_in [z-1:0];
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] bias [z/fi-1:0];
	logic signed [width-1:0] del_in [z/fi-1:0];
	logic signed [width-1:0] del_in_neg [z/fi-1:0]; //Stores negative values of deltas
	
	logic signed [width-1:0] delta_bias [z/fi-1:0];
	logic signed [width-1:0] delta_bias_temp [z/fi-1:0]; //Temporarily stores values of delta_bias
	logic signed [width-1:0] bias_UP [z/fi-1:0];
	
	logic signed [width-1:0] delta_wt [z-1:0];
	logic signed [width-1:0] wt_UP [z-1:0];

	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign wt[gv_i] = wt_package[width*(gv_i+1)-1:width*gv_i];
		assign act_in[gv_i] = act_in_package[width*(gv_i+1)-1:width*gv_i];
		assign wt_UP_package[width*(gv_i+1)-1:width*gv_i] = wt_UP[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign del_in[gv_i] = del_in_package[width*(gv_i+1)-1:width*gv_i];
		assign bias[gv_i] = bias_package[width*(gv_i+1)-1:width*gv_i];
		assign bias_UP_package[width*(gv_i+1)-1:width*gv_i] = bias_UP[gv_i];
	end
	endgenerate
	// Finished unpacking

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : get_delta_biases
		//`ifdef ETA2POWER	
		assign del_in_neg[gv_i] = (del_in[gv_i] == {1'b1,{(width-1){1'b0}}}) ? {1'b0,{(width-1){1'b1}}} : -del_in[gv_i]; //If del_in is neg max, then we need to explicitly specify that its negative is pos max
		assign delta_bias_temp[gv_i] = (etapos==0) ? 0 : //If etapos=0, operation hasn't started
				del_in_neg[gv_i]>>>(etapos-1); //Otherwise usual case: delta_bias_temp = -del_in*eta
		assign delta_bias[gv_i] = (etapos<=1) ? delta_bias_temp[gv_i] : // If etapos=1, the actual Eta=1, so there is no shift, and hence no rounding
				delta_bias_temp[gv_i] + del_in_neg[gv_i][etapos-2]; //Otherwise round, i.e. add 1 if MSB of shifted out portion = 1	
		/*`else //if eta is not a power of 2
			multiplier #(
				.mode(1),
				.width(width),
				.int_bits(int_bits)
			) mul_eta (
				.clk,
				.reset,
				.a(del_in[gv_i]),
				.b(eta),
				.p(delta_bias[gv_i])
			);
		`endif*/
	end
	endgenerate
	
    logic signed [width-1:0] wt_delayed [z-1:0];
    logic signed [width-1:0] wt_UP_undelayed [z-1:0];
    logic signed [width-1:0] bias_UP_undelayed [z/fi-1:0];
    
    `ifdef PIPELINEMULT
    `ifdef MAXLOGFI
        generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
        begin : updates_outer	
            adder #(
                .width(width)
            ) update_b (
                .clk,
                .reset,
                .a(bias[gv_i]),
                .b(delta_bias[gv_i]),
                .s(bias_UP_undelayed[gv_i])
            );
            
            shift_reg #(
                .width(width),
                .depth(`MAXLOGFI+`PIPELINEMULT) //(`MAXLOGFI+`PIPELINEMULT+1)-1
            ) sr_final_bias_UP (
                .clk,
                .reset,
                .d(bias_UP_undelayed[gv_i]),
                .q(bias_UP[gv_i])
            );
            
            for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1)
            begin : updates_inner
                multiplier #(
                    .mode(1),
                    .width(width),
                    .int_bits(int_bits)
                ) mul_act_del (
                    .clk,
                    .reset,
                    .a(delta_bias[gv_i]), 
                    .b(act_in[gv_i*fi+gv_j]), 
                    .p(delta_wt[gv_i*fi+gv_j])
                );
                
                shift_reg #(
                    .width(width),
                    .depth(`PIPELINEMULT)
                ) sr_delay_wts_forUP (
                    .clk,
                    .reset,
                    .d(wt[gv_i*fi+gv_j]),
                    .q(wt_delayed[gv_i*fi+gv_j])
                );
                
                adder #(
                    .width(width)
                ) update_wt (
                    .clk,
                    .reset,
                    .a(wt_delayed[gv_i*fi+gv_j]),
                    .b(delta_wt[gv_i*fi+gv_j]),
                    .s(wt_UP_undelayed[gv_i*fi+gv_j])
                );
                
                shift_reg #(
                    .width(width),
                    .depth(`MAXLOGFI) //(`MAXLOGFI+`PIPELINEMULT+1)-(`PIPELINEMULT+1)
                ) sr_final_wt_UP (
                    .clk,
                    .reset,
                    .d(wt_UP_undelayed[gv_i*fi+gv_j]),
                    .q(wt_UP[gv_i*fi+gv_j])
                );
            end
        end
        endgenerate
    `endif
    `endif
endmodule