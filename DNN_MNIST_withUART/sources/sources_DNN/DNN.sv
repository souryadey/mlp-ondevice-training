// Sparse interleaved neural network
// Yinan Shao, Sourya Dey

`timescale 1ns/100ps
`define PROCTIME 2 //0 for _nopipeline, 2 for _pipelinemult1, `PIPELINEMULT+`MAXLOGFI+1 for _pipelinemultadd

//[FUTURE] Add code for customizable no. of hidden layers

module DNN #( // Parameter arrays need to be [31:0] for compilation
	parameter width_in = 8, //input data width, i.e. no. of bits each input neuron can take in
	parameter width = 12, //Bit width
	parameter int_bits = 3, //no. of integer bits
	parameter L = 3, //Total no. of layers (including input and output)
	parameter [31:0] actfn [0:L-2] = '{1,0}, //Activation function for all junctions. 0 = sigmoid, 1 = relu
	parameter costfn = 1, //Cost function for output layer. 0 = quadcost, 1 = xentcost
	
	parameter [31:0] n [0:L-1] = '{1024, 64, 16}, //No. of neurons in every layer
	parameter [31:0] fo [0:L-2] = '{8, 8}, //Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{128, 32}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{512, 32}, //Degree of parallelism of all junctions. No. of junctions = L-1
	
	//parameter eta = `eta, //eta is NOT a parameter any more. See input section for details
	//parameter lamda = 1, //L2 regularization
	parameter cpc =  n[0] * fo[0] / z[0] + 12,	//clocks per cycle block = Weights/parallelism. `PROCTIME will be added. [FUTURE] Add support for different cpc
	localparam frac_bits = width-int_bits-1, //no. of fractional part bits
	localparam max_actL1_pos_width = (z[L-2]/fi[L-2]==1) ? 1 : $clog2(z[L-2]/fi[L-2]) //position of maximum neuron every clk cycle
)(
	input [width_in*z[0]/fo[0]-1:0] act0, //Load activations from outside. z[0] weights processed together in first junction => z[0]/fo[0] activations together
	input [z[L-2]/fi[L-2]-1:0] ans0, //Load ideal outputs from outside. z[L-2] weights processed together in last junction => z[L-2]/fi[L-2] ideal outputs together, each is 1b 
	input [$clog2(frac_bits+2)-1:0] etapos0, //see tb_DNN for description
	// Note that etapos is an input, so each training sample can have its own etapos. However, all the LAYERS HAVE THE SAME etapos for a particular sample
	// By making etapos an input, the problem of random weight updates after reset is solved, because each etapos is introduced with input data
	input clk,
	input reset, //active high
	
	output cycle_clk,
	output [$clog2(cpc)-1:0] cycle_index, //Bits to hold cycle number [Eg: 32 weights, z=8 means 32/8+2 = 6 cycles, so cycle_index is 3b]
	output [z[L-2]/fi[L-2]-1:0] ansL, //ideal output (ans0 after going through all layers) only for the current z neurons (UNLIKE actL_alln)
	output logic [n[L-1]-1:0] actL_alln = '0 //Actual output [Eg: 4/4=1 output neuron processed per clock] for ALL OUTPUT NEURONS
);

	/* Treating all the hidden layers as a black box, following are its I/O:
			act1, adot1 are 'inputs' from input layer to black box
			actL1, adotL1 are 'outputs' from black box to output layer
			delL1 is 'input' from output layer to black box
	`		del1 is 'output' from black box to input layer
	So these signals remain same regardless of no. of hidden layers */
	logic [width*z[0]/fi[0]-1:0] act1, adot1, del1; //z[0]/fi[0] is the no. of neurons processed in 1 cycle at the input of the black box, i.e. 1st hidden layer
	logic [width*z[L-2]/fi[L-2]-1:0] actL1, adotL1, delL1; //z[L-2]/fi[L-2] is the no. of neurons processed in 1 cycle in the last layer, i.e. output of the black box
	logic [$clog2(frac_bits+2)-1:0] etapos1, etaposL1; //etapos is same for all layers, but timestamps are different. etapos1 is a delayed version of etaposL1, see below
	
	cycle_block_counter #(
		.cpc(cpc)
	) cycle_counter (
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.count(cycle_index)
	);

	input_layer_block #(
		.p(n[0]), 
		.z(z[0]), 
		.fi(fi[0]), 
		.fo(fo[0]),
		.cpc(cpc),
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.actfn(actfn[0]),
		.L(L)
	) input_layer_block (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk), .etapos(etapos1), //input control signals
		.act_in(act0), .del_in(del1), //input data flow: act0 from outside, del1 from next layer [Eg: del1 is 16b x 2 values since 2 neurons from next layer send it. Basically deln]
		.act_out(act1), .adot_out(adot1) //output data flow: act1 and adot1 to next layer [Eg: each is 16b x 2 values,since 2 neurons in the next layer get processed at a time. Basically actn]
	);

	hidden_layer_block #(
		.p(n[1]), 
		.z(z[1]), 
		.fi(fi[1]), 
		.fo(fo[1]), 
		.cpc(cpc),
		.width(width),
		.int_bits(int_bits),
		.actfn(actfn[1]),
		.L(L), 
		.h(1) //index of hidden layer
	) hidden_layer_block_1 (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk),  .etapos(etaposL1), //input control signals
		.act_in(act1), .adot_in(adot1), .del_in(delL1), //input data flow
		.act_out(actL1), .adot_out(adotL1), .del_out(del1) //output data flow
	);
	
	output_layer_block #(
		.p(n[L-1]), 
		.zbyfi(z[L-2]/fi[L-2]),
		.cpc(cpc),
		.width(width),
		.int_bits(int_bits),
		.costfn(costfn),
		.L(L)
	) output_layer_block (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk), //input control signals
		.act_in(actL1), .adot_in(adotL1), .ans_in(ans0), 	//input data flow [Eg: 16b x 1 value (for 1 neuron).] ans0 is input entering fist layer. It goes to last layer through a shift register
		.del_out(delL1), .ans_out(ansL) //output data flow. delL1 goes to previous hidden layer, yL goes outside
	);

	// Max act logic
	logic [width-1:0] max_actL1, //local max act every cycle
					final_max_actL1, //global max act every cpc cycles
					stored_max_actL1; //current global max act in the middle of a block cycle
	logic [max_actL1_pos_width-1:0] max_actL1_pos;
	logic [$clog2(n[L-1])-1:0] stored_max_actL1_pos;
	logic max_actL1_singlepos; //compares local with global

	// max_finder_set gets local max act and its pos from z[L-2]/fi[L-2] activations after every clk cycle starting from 2+`PROCTIME and up till cpc-1
	// max_finder compares this max act with the stored global max act from previous cycles and outputs final max act after cpc cycles, i.e. max act from n[L-2] output neurons
	max_finder_set #(
		.width(width),
		.N(z[L-2]/fi[L-2])
	) mfs_actL1 (
		.in(actL1),
		.out(max_actL1),
		.pos(max_actL1_pos)
	);
	
	max_finder #(
		.width(width)
	) mf_actstored (
		.a(max_actL1),
		.b(stored_max_actL1),
		.out(final_max_actL1),
		.pos(max_actL1_singlepos)
	);
	
	always @(posedge clk) begin
		if (cycle_index == cpc-1) begin //Assign 1 output to the max position and then reset variables
			actL_alln <= 1<<stored_max_actL1_pos;
			stored_max_actL1 <= {1'b1,{(width-1){1'b0}}}; //most negative value possible
			stored_max_actL1_pos <= {$clog2(n[L-1]){1'b0}}; //reset to all 0
		end else if (cycle_index >= 2+`PROCTIME) begin //Cycles before 2+`PROCTIME are just to fill the pipeline
			stored_max_actL1 <= final_max_actL1; //This is the final_max_actL1 just generated from the new actL1 values. This line behaves like a DFF
			if (z[L-2]/fi[L-2]>1) begin //>1 output neuron computed every clk
				if (max_actL1_singlepos==0) //new value is max
					stored_max_actL1_pos <= {(cycle_index-2-`PROCTIME),max_actL1_pos};
					/* To understand this, imagine a case where n[L-1]=16, i.e. stored_max_actL1_pos is 4 bits to count neurons from 0 to 15
					Say `PROCTIME=1, and z[L-2]/fi[L-2]=4, i.e. 4 neurons are processed every cycle
					Then cpc = 4 + 2 + `PROCTIME = 7, i.e. cycle_index is 3 bits
					Say neuron 9 is the global max, then the output of max_actL1_pos will be 2'b01 (since it compares neurons 8,9,10,11 and 9 is at position 1)
					Since this is the global max, max_actL1_singlepos will be 0
					At this point, cycle_index is at 5, since cycles 0,1,2 were to fill the pipeline, then cycle 3 for neurons 0,1,2,3, cycle 4 for neurons 4,5,6,7, and cycle 5 for neurons 8,9,10,11
					Then, stored_max_actL1_pos = 4'b{(5-2-1),2'b01} = 4'b{3'b010,2'b01} = 4'b1001, which is the position for neuron 9 :-) */
				//else retain previous value of stored_max_actL1_pos
			end else begin //only 1 output neuron computed every clk
				stored_max_actL1_pos <= (max_actL1_singlepos==0) ? (cycle_index-2-`PROCTIME) : stored_max_actL1_pos;
				/* here max_actL1_pos is trivially 0 and carries no information
				since z[L-2]/fi[L-2] = 1, index of current output neuron = cycle_index-2-`PROCTIME
				if condition is true, then current neuron is max value, so store cycle_index-2-`PROCTIME
				if condition is false, retain previous value of stored_max_actL1_pos */
			end
		end
	end
	

//etapos shift register
	shift_reg #( //2nd junction gets updated first - L block cycles after input is fed
		.width($clog2(frac_bits+2)), 
		.depth(L)
	) etapos_SRL1 (
		.clk(cycle_clk), 
		.reset(reset), 
		.d(etapos0), 
		.q(etaposL1)
	);

	DFF #( //1st junction gets updated 1 block cycle after 2nd (using same etapos)
		.width($clog2(frac_bits+2))
	) etapos_DFF (
		.clk(cycle_clk),
		.reset(reset),
		.d(etaposL1),
		.q(etapos1)
	);
endmodule
