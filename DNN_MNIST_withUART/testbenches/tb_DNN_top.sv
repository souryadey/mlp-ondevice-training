/* Testbench for DNN_top
 * Can also simulate DNN -- search for 'to test DNN'
 * Main difference between DNN_top and DNN is that the former has ans0 logic inbuilt, hence it's not required in testbench when simulating DNN_top 
 * The other difference between DNN_top and DNN is that the former has logic for sel_network and sel_tc
 * But these signals are also required in the testbench, in fact, they have identical behavior in the testbench as in the source
 * This is code repetition, but is required since sel_tc and sel_network are required during synthesis, where only the source will be present
*/

`timescale 1ns/100ps
`define CLOCKPERIOD 10

//`define MODELSIM
`define VIVADO

`define NIN 784 //Number of inputs AS IN DATASET
`define NOUT 10 //Number of outputs AS IN DATASET
`define TC 12544 //Training cases to be considered in 1 epoch
`define TTC 10*`TC //Total training cases over all epochs
`define CHECKLAST 1000 //How many last inputs to check for accuracy

/*
`define SMALLNET
`define NIN 64 //Number of inputs AS IN DATASET
`define NOUT 4 //Number of outputs AS IN DATASET
`define TC 2000 //Training cases to be considered in 1 epoch
`define TTC 1*`TC //Total training cases over all epochs
`define CHECKLAST 1000 //How many last inputs to check for accuracy
*/

module tb_DNN_top #(
	parameter width_in = 8,
	parameter width = 10,
	parameter int_bits = 2,
	parameter L = 3,
	parameter [31:0] actfn [0:L-2] = '{0,0}, //Activation function for all junctions. 0 = sigmoid, 1 = relu
	parameter costfn = 1, //Cost function for output layer. 0 = quadcost, 1 = xentcost
	//parameter Eta = 2.0**(-4), //Should be a power of 2. Value between 2^(-frac_bits) and 1. DO NOT WRITE THIS AS 2**x, it doesn't work without 2.0
	//parameter lamda = 0.9, //weights are capped at absolute value = lamda*2**int_bits
	
    // For MNIST IMPLEMENTED on FPGA
	parameter [31:0] n [0:L-1] = '{1024, 64, 32}, //No. of neurons in every layer
	parameter [31:0] fo [0:L-2] = '{4, 16}, //Fanout of all layers except for output
	parameter [31:0] fi [0:L-2] = '{64, 32}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2] = '{128, 32}, //Degree of parallelism of all junctions. No. of junctions = L-1
	
	// For MNIST to TEST PIPELINING
	/* parameter [31:0] n [0:L-1] = '{1024, 128, 32},
    parameter [31:0] fo [0:L-2] = '{4, 8},
    parameter [31:0] fi [0:L-2] = '{32, 32},
    parameter [31:0] z [0:L-2] = '{128, 32}, */

    // For MNIST_POWERFULDEVICE
	/* parameter [31:0] n [0:L-1] = '{1024, 64, 16},
	parameter [31:0] fo [0:L-2] = '{8, 8},
	parameter [31:0] fi [0:L-2] = '{128, 32},
	parameter [31:0] z [0:L-2] = '{512, 32}, */

    // For SMALLNET
	/* parameter [31:0] n [0:L-1] = '{64, 16, 4},
	parameter [31:0] fo [0:L-2] = '{2, 2},
	parameter [31:0] fi [0:L-2] = '{8, 8},
	parameter [31:0] z [0:L-2] = '{32, 8}, */
    
    localparam frac_bits = width-int_bits-1,
	localparam cpc =  n[0] * fo[0] / z[0] + 2 + `PROCTIME
)(
);
	
	
	////////////////////////////////////////////////////////////////////////////////////
	// define DNN_top I/O
	////////////////////////////////////////////////////////////////////////////////////
	logic clk = 1;
	logic reset = 1;
	logic cycle_clk;
	logic [$clog2(cpc)-1:0] cycle_index;
	
	logic [$clog2(frac_bits+2)-1:0] etapos; /*etapos = -log2(Eta)+1. Eg: If Eta=2^-4, etapos=5. etapos=0 is not valid
	Min allowable value of Eta = 2^(-frac_bits) => Max value of etapos = frac_bits+1, which needs log2(frac_bits+2) bits to store
	Max allowable value of Eta = 1 => Min value of etapos = 1. So etapos is never 0 */
	
	logic [width_in*z[0]/fo[0]-1:0] act0; //No. of input activations coming into input layer per clock, each having width_in bits
	//logic [z[L-2]/fi[L-2]-1:0] ans0; //No. of ideal outputs coming into input layer per clock. UNCOMMENT to test DNN
	logic [z[L-2]/fi[L-2]-1:0] ansL; //ideal output (ans0 after going through all layers)
	logic [n[L-1]-1:0] actL_alln; //Actual output [Eg: 4/4=1 output neuron processed per clock] of ALL output neurons
	////////////////////////////////////////////////////////////////////////////////////
	
	////////////////////////////////////////////////////////////////////////////////////
	// Other relevant signals for preprocessing
	////////////////////////////////////////////////////////////////////////////////////
	logic [$clog2(`TC)-1:0] sel_tc = '0; //MUX select to choose training case each block cycle
	logic [$clog2(n[0]*fo[0]/z[0])-1:0] sel_network; //MUX select to choose which input/output pair to feed to network within a block cycle
	logic [width_in*n[0]-1:0] act0_tc; //Complete 8b act input for 1 training case, i.e. No. of input neurons x 8 x 1
	//logic [n[L-1]-1:0] ans0_tc; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1
	////////////////////////////////////////////////////////////////////////////////////

	////////////////////////////////////////////////////////////////////////////////////
	// Instantiate DNN_top
	////////////////////////////////////////////////////////////////////////////////////
	DNN_top #( //Replace DNN_top with DNN to test DNN
		.width_in(width_in),
		.width(width), 
		.int_bits(int_bits),
		.L(L), 
		.actfn(actfn),
		.costfn(costfn),
		.n(n),
		.fo(fo), 
		.fi(fi), 
		.z(z)
	) DNN_top ( //Replace DNN_top with DNN to test DNN
		.act0,
		//.ans0, //UNCOMMENT to test DNN
		.etapos0(etapos), 
		.clk,
		.reset,
		.cycle_clk,
		.cycle_index,
		.ansL,
		.actL_alln
	);
	////////////////////////////////////////////////////////////////////////////////////

	////////////////////////////////////////////////////////////////////////////////////
	// Set Clock, Reset, etapos
	////////////////////////////////////////////////////////////////////////////////////
	always #(`CLOCKPERIOD/2) clk = ~clk;
	
	initial begin : reset_logic
		#(cpc*L*`CLOCKPERIOD + 1) reset = 0; //max shift reg depth is cpc*(L-1). So lower reset after even the deepest DFFs in the shift regs have time to latch 0 from previous stages
	end
	
	// Option 1: Directly set etapos (EASIER)
	initial begin : etapos_logic
		etapos = 4;
		#(cpc*`CLOCKPERIOD*25000 + 1) etapos = 5; //after about 25k inputs
		#(cpc*`CLOCKPERIOD*50000 + 1) etapos = 6; //after another 50k, i.e. total 75k inputs
		//#(cpc*`CLOCKPERIOD*50000 + 1) etapos = 7; //after another 50k, i.e. total 125k inputs
		//#(cpc*`CLOCKPERIOD*50000 + 1) etapos = 8; //after another 50k, i.e. total 175k inputs
	end
	
	// Option 2: Get etapos from Eta
	/*
	integer etaloop;
	logic found = 0;
	logic [width-1:0] eta;
	initial begin
		eta = Eta * (2 ** frac_bits); //convert the Eta to fix point
		for (etaloop=0; etaloop<=frac_bits; etaloop=etaloop+1) begin
			if (eta[frac_bits-etaloop] && !found) begin
				etapos = etaloop+1;
				found = 1;
			end
		end
	end
	*/
	////////////////////////////////////////////////////////////////////////////////////

	////////////////////////////////////////////////////////////////////////////////////
	// Training cases Pre-Processing
	////////////////////////////////////////////////////////////////////////////////////
	assign sel_network = cycle_index[$clog2(n[0]*fo[0]/z[0])-1:0] - 2; //cycle through 0 to n*fo/z-1

	mux #( //Choose the required no. of act inputs for feeding to DNN
		.width(width_in*z[0]/fo[0]), 
		.N(n[0]*fo[0]/z[0])
	) mux_actinput_feednetwork (
		act0_tc, sel_network, act0);
		
	// UNCOMMENT to test DNN
	/*
	mux #( //Choose the required no. of ideal outputs for feeding to DNN
		.width(z[L-2]/fi[L-2]), 
		.N(n[L-1]*fi[L-2]/z[L-2]) //This is basically cpc-2-`PROCTIME of the last junction
	) mux_idealoutput_feednetwork (
		ans0_tc, sel_network, ans0);
	*/
	////////////////////////////////////////////////////////////////////////////////////

	////////////////////////////////////////////////////////////////////////////////////
	// Data import block
	/* train_input.dat contains 50000 MNIST patterns. Each pattern contain 28*28 pixels which is 8 bit gray scale.
		1 line is one pattern with 784 8bit hex. Values from 784-1023 are set to 0 */
	/* train_idealout.dat is the data set for 50000 correct results of training data. There are 10 bits one-hot representing 10 numbers from 0-9.
		1 line is one pattern with 10 one-hot binary. Values from 10-31 are set to 0 */
	////////////////////////////////////////////////////////////////////////////////////
	
	/* SIMULATOR NOTES:
	*	Modelsim can read a input file with spaces and assign it in natural counting order
		Eg: The line a b c d e f g h i j when written to an input vector [9:0], will be written as [0]=a, [1]=b, ..., [9]=j
		This is opposite to the opposite counting order naturally followed in hardware, and is possible because of the spaces in the input file
	*	Vivado cannot read an input file with spaces, so when it reads a packed input file, it assigns in hardware order (i.e. opposite counting order)
		Eg: The line abcdefghij when written to an input vector [9:0], will be written as [9]=a, [8]=b, ..., [0]=j
	*	The Modelsim version was done first, it works and also shows up nicely in the output log files since counting order is natural
		So we will force the Vivado version to have natural counting order in hardware
 	*/
 	
 	/* HOME DIRECTORY NOTES:
 	Home directory . for Vivado is <Vivado projects folder>\<project_name>\<project_name.sim>\sim_1\behav\xsim\
 	For example, C:\Users\souryadey92\Desktop\Vivado\pdsNN1\pdsNN1.sim\sim_1\behav\xsim\
 	*/
	
	// For MNIST
    `ifdef MODELSIM
        logic [width_in-1:0] act_mem[`TC-1:0][`NIN-1:0]; //inputs
        //logic ans_mem[`TC-1:0][`NOUT-1:0]; //ideal outputs. UNCOMMENT to test DNN
        initial begin
            //$readmemb("./data/mnist/train_idealout_spaced.dat", ans_mem); //UNCOMMENT to test DNN
            $readmemh("./data/mnist/train_input_spaced.dat", act_mem);
        end       
    `elsif VIVADO
        logic [width_in-1:0] act_mem[`TC-1:0][0:`NIN-1]; //flipping only occurs in the 784 dimension
        //logic ans_mem[`TC-1:0][0:`NOUT-1]; //flipping only occurs in the 10 dimension. UNCOMMENT to test DNN
        initial begin
            //$readmemb("./data/mnist/train_idealout.dat", ans_mem);. UNCOMMENT to test DNN
            $readmemh("./data/mnist/train_input_ori.dat", act_mem);
        end
    `endif
	
	// For SMALLNET
    /* `ifdef MODELSIM
        logic [width_in-1:0] act_mem[`TC-1:0][`NIN-1:0]; //inputs
        //logic ans_mem[`TC-1:0][`NOUT-1:0]; //ideal outputs. UNCOMMENT to test DNN
        initial begin
            //$readmemb("./data/smallnet/train_idealout_4_spaced.dat", ans_mem); //UNCOMMENT to test DNN
            $readmemh("./data/smallnet/train_input_64_spaced.dat", act_mem);
        end       
    `elsif VIVADO
        logic [width_in-1:0] act_mem[`TC-1:0][0:`NIN-1]; //flipping only occurs in the 784 dimension
        //logic ans_mem[`TC-1:0][0:`NOUT-1]; //flipping only occurs in the 10 dimension. UNCOMMENT to test DNN
        initial begin
            //$readmemb("./data/smallnet/train_idealout_4.dat", ans_mem); //UNCOMMENT to test DNN
            $readmemh("./data/smallnet/train_input_64.dat", act_mem);
        end
    `endif */
    
    
    always @(posedge cycle_clk) begin
        if(!reset) begin
            sel_tc <= (sel_tc == `TC-1)? 0 : sel_tc + 1;
        end else begin
            sel_tc <= 0;
        end
    end

	genvar gv_i;	
	generate for (gv_i = 0; gv_i<n[0]; gv_i = gv_i + 1)
	begin: pr
		assign act0_tc[width_in*(gv_i+1)-1:width_in*gv_i] = (gv_i<`NIN)? act_mem[sel_tc][gv_i] : 0;
	end
	endgenerate

	// UNCOMMENT to test DNN
	/*
	generate for (gv_i = 0; gv_i<n[L-1]; gv_i = gv_i + 1)
	begin: pp
		assign ans0_tc[gv_i] = (gv_i<`NOUT)? ans_mem[sel_tc][gv_i]:0;
	end
	endgenerate
	*/
	////////////////////////////////////////////////////////////////////////////////////
	
	////////////////////////////////////////////////////////////////////////////////////
	// Performance Evaluation Variables
	////////////////////////////////////////////////////////////////////////////////////
	integer num_train = 0, //Number of the current training case
	        q, //loop variable
			correct, //signals whether current training case is correct or not
			recent = 0, //counts #correct in last 1000 training cases
			crt[`CHECKLAST:0], //stores last 1000 results - each result is either 1 or 0
			crt_pt = 0, //points to where current training case result will enter. Loops around on reaching 1000
			total_correct = 0, //Total number of correct accumulated over training cases
			log_file;
	real    EMS; //Expected mean square error between actL_alln and ansL of all neurons in output layer
	
	//The following variables store information about all output neurons
	real    actL_alln_calc[n[L-1]-1:0], //Actual output of network
			actans_diff_alln_calc[n[L-1]-1:0]; //act-ans
	integer ansL_alln_calc[n[L-1]-1:0]; //Ideal output ans0_tc
	
	//The following variables store information of weights and biases at some instant of time during processing
	real    wb1[z[L-2]+z[L-2]/fi[L-2]-1:0]; //pre-update weights = z[L-2] + biases = z[L-2]/fi[L-2]
	////////////////////////////////////////////////////////////////////////////////////

	////////////////////////////////////////////////////////////////////////////////////
	// Probe signals
	/* This converts any SIGNED variable x[width-1:0] from binary to decimal: x/2.0**frac_bits
		This converts any UNSIGNED variable x[width-1:0] from binary 2C to decimal: x/2.0**frac_bits - x[width-1]*2.0**(1+int_bits)  */
	// To test DNN, remove all 'DNN_top.' from the beginning of signals
	////////////////////////////////////////////////////////////////////////////////////
	always @(negedge clk) begin
		if (cycle_index == 2) begin //IMPORTANT: the number has no special significance, it is just some point in junction cycle
			for (q=0; q<z[L-2]; q=q+1) begin
				wb1[q] = DNN_top.DNN.hidden_layer_block_1.UP_processor.wt[q]/2.0**frac_bits; //get weights some point in junction cycle. wb1[q] is signed
			end
			for (q=z[L-2]; q<z[L-2]+z[L-2]/fi[L-2]; q=q+1) begin
				wb1[q] = DNN_top.DNN.hidden_layer_block_1.UP_processor.bias[q-z[L-2]]/2.0**frac_bits; //get biases at some point in junction cycle. wb1[q] is signed
			end
		end
		if (cycle_index > 1+`PROCTIME && cycle_index < 2+`PROCTIME+n[L-1]*fi[L-2]/z[L-2]) begin //this is the number of cycles it takes to process all neurons
			for (q=0; q<z[L-2]/fi[L-2]; q=q+1) begin
			    actL_alln_calc[(z[L-2]/fi[L-2])*(cycle_index-2-`PROCTIME)+q] = DNN_top.DNN.hidden_layer_block_1.FF_processor.act_out[q]/2.0**frac_bits; //get activations (always positive)
			    ansL_alln_calc[(z[L-2]/fi[L-2])*(cycle_index-2-`PROCTIME)+q] = ansL[q]; //get ideal outputs. Division is not required because it is not in bit form
			    actans_diff_alln_calc[(z[L-2]/fi[L-2])*(cycle_index-2-`PROCTIME)+q] = DNN_top.DNN.output_layer_block.costterms.costterm[q]/2.0**frac_bits; //signed
			end
		end
	end
	////////////////////////////////////////////////////////////////////////////////////
	
	////////////////////////////////////////////////////////////////////////////////////
	// Performance evaluation and display
	////////////////////////////////////////////////////////////////////////////////////
	initial begin
	    //$monitor("%h  %h",cycle_index,DNN_top.DNN.input_layer_block.jn01_wb_mem.data_outB_package);
		log_file = $fopen("results_log.dat"); //Stores a lot of info
		for(q=0;q<=`CHECKLAST;q=q+1) crt[q]=0; //initialize all 1000 places to 0
	end

	always @(posedge cycle_clk) begin
		#0; //let everything in the circuit finish before starting performance eval
		num_train = num_train + 1;
		recent = recent - crt[crt_pt]; //crt[crt_pt] is the value about to be replaced 
		correct = 1; //temporary placeholder
		for (q=0; q<n[L-1]; q=q+1) begin
			if (actL_alln[q] != ansL_alln_calc[q])
			    correct=0;
		end
		crt[crt_pt] = correct;
		recent = recent + crt[crt_pt]; //Update recent with value just stored
		crt_pt = (crt_pt==`CHECKLAST)? 0 : crt_pt+1;
		total_correct = total_correct + correct;
		
		EMS = 0;
		for (q=0; q<n[L-1]; q=q+1)
		    EMS = actans_diff_alln_calc[q]*actans_diff_alln_calc[q]*100 + EMS; //multiply by 100 to get better scale of values
		
	
		// Transcript display - basic stats
		$display("Case number = %0d, correct = %0d, recent_%0d = %0d, EMS = %5f", num_train, correct, `CHECKLAST, recent, EMS); 

		// Write to log file - Everything
		$fdisplay (log_file,"-----------------------------train: %d", num_train);
		
		$fwrite (log_file, "ideal       output:");
		for(q=0; q<n[L-1]; q=q+1)
		    $fwrite (log_file, "\t %5d", ansL_alln_calc[q]);
		$fwrite (log_file, "\n");
		
		$fwrite (log_file, "actual      output:");
		for(q=0; q<n[L-1]; q=q+1)
		    $fwrite (log_file, "\t %5d", actL_alln[q]);
		$fwrite (log_file, "\n");
		
		$fwrite (log_file, "actual real output:");
		for(q=0; q<n[L-1]; q=q+1)
		    $fwrite (log_file, "\t %1.4f", actL_alln_calc[q]);
		$fwrite (log_file, "\n");
		
		$fwrite (log_file, "actans_diff_alln_calc:            ");
		for(q=0; q<n[L-1]; q=q+1)
		    $fwrite (log_file, "\t %1.4f", actans_diff_alln_calc[q]);
		$fwrite (log_file, "\n");
		
		$fwrite (log_file, "w12:     ");
		for(q=0; q<z[L-2]; q=q+1)
		    $fwrite (log_file, "\t %1.3f", wb1[q]);
		$fwrite (log_file, "\n");
		
		$fwrite (log_file, "b2:     ");
		for(q=z[L-2]; q<z[L-2]+z[L-2]/fi[L-2]; q=q+1)
		    $fwrite (log_file, "\t %1.3f", wb1[q]);
		$fwrite (log_file, "\n");
		
		$fdisplay(log_file, "correct = %0d, recent_%4d = %3d, EMS = %5f", correct, `CHECKLAST, recent, EMS);
		
		/*if (sel_tc == 0 && !reset) begin
			$fdisplay(log_file, "\nFINISHED TRAINING EPOCH %0d", epoch);
			$fdisplay(log_file, "Total Correct = %0d\n", total_correct);
			epoch = epoch + 1;
		end*/
		
		// Stop conditions
		if (num_train==`TTC) $stop;
		//if (num_train == 10) $stop;
	end
	////////////////////////////////////////////////////////////////////////////////////
endmodule