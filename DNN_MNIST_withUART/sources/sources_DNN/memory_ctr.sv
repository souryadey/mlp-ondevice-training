`timescale 1ns/100ps
 
//Main bug during pipelining: act_coll_we
//Other signals like act_coll_in and act_coll_addr match between ideal (non-pipelined) and pipelined versions

module address_decoder #(
	parameter p  = 16,
	parameter z  = 8,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input [$clog2(p)*z-1:0] memory_index_package, //Neuron from where I should get activation = output of interleaver
	output [log_pbyz*z-1:0] addr_package, //1 address for each AMp and DMp, total of z. Addresses are log(p/z) bits since AMp and DMp have that many elements
	output [log_z*z-1:0] muxsel_package //control signals for AMp, DMp MUXes
);

	logic [$clog2(p)-1:0] memory_index[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: address_decoder
		assign memory_index[gv_i] = memory_index_package[$clog2(p)*(gv_i+1)-1:$clog2(p)*gv_i]; //Unpacking
		if (z==1)
			assign muxsel_package[log_z*(gv_i+1)-1 : log_z*gv_i] = '0;
		else
			assign muxsel_package[log_z*(gv_i+1)-1 : log_z*gv_i] =  gv_i; //assign mux selects in natural order, i.e. 0 for the 0th mux, then 1, and so on
		if (p==z)
			assign addr_package[log_pbyz*(gv_i+1)-1 : log_pbyz*gv_i] = '0;
		else
			assign addr_package[log_pbyz*(gv_i+1)-1 : log_pbyz*gv_i] = memory_index[gv_i][$clog2(p)-1:$clog2(z)]; //The MSB log(p)-log(z) bits denote the row number of the actmem (side note: the LSB log(z) bits denote the mem number)
	end
	endgenerate
endmodule


//Controller for weight and bias memories which are simple dual port
// where port A is used exclusively for writing, port B exclusively for reading
module wb_mem_ctr #(
	parameter p = 16,
	parameter z = 10,
	parameter fo = 2,
	parameter cpc = p*fo/z + 12
)(
	input clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input reset,
	output [z-1:0] weA,
	output [$clog2(p*fo/z)*z-1:0] r_addr, //Address is a = log(p*fo/z) = log(cpc-2) bits, since there are p*fo/z cells in each weight memory
	output [$clog2(p*fo/z)*z-1:0] w_addr //Lump all the addresses together. Since there are z memories, there are z a-bit addresses
);

	genvar gv_i;
    generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1) //This loop packs the WEs and read address for all z memories into big 1D vectors
    begin: ctr_generate
        assign weA[gv_i] = (cycle_index>`PROCTIME && cycle_index<= cpc-2)? ~reset : 0; //If cycle_index has a valid value and reset is OFF, then all weA = 1
        assign r_addr[$clog2(p*fo/z)*(gv_i+1)-1:$clog2(p*fo/z)*gv_i] = cycle_index[$clog2(p*fo/z)-1:0]; //All read addresses = cycle_index, since we read the same entry from all memories
        //Note that when p*fo/z is a power of 2, the RHS above is all the bits of cycle_index except for the MSB
        //This is because the MSB simply accounts for the pipeline delay, the real cycle_index is 2nd MSB to LSB
    end
    endgenerate

	//Whatever entry we read from all the weight mems, same entries are updated after (1+`PROCTIME) cycles
	//1 to account for the reading cycle and `PROCTIME to account for the processing arithmetic delay
	shift_reg #(
		.width(z*$clog2(p*fo/z)),
		.depth(1+`PROCTIME)
	) dff_memaddr (
		.clk,
		.reset,
		.d(r_addr),
		.q(w_addr)
	); 
endmodule


module act_adot_ctr #(
	parameter fo = 2,
	parameter p  = 16,
	parameter z  = 8,
	parameter L = 3,
	parameter h = 1,
	parameter cpc = p*fo/z + 12,
	parameter width = 16,
	localparam collection = 2*(L-h)-1,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z)
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input [log_pbyz*z-1:0] r_addr_decoded, //output of address decoder
	
	//Next 2 inputs are from FF processor of previous layer. Total no. of clocks = p*fo/z. Total act and adot to be inputted = p. So no. of values reqd in each clk = p / p*fo/z = z/fo
	// z/fo memories together is defined as a part. So act_in and adot_in hold all the data for 1 cell of all z/fo memories in a part
	input [width*z/fo-1:0] act_in,
	input [width*z/fo-1:0] adot_in,

	// Next 4 signals are for AMp
	output [collection*z*log_pbyz-1:0] act_coll_addr,
	output [collection*z-1:0] act_coll_we,
	output [collection*z*width-1:0] act_coll_in, // All data to be written into AM and adot mem in 1 clock. 1 clock writes 1 cell in all memories of each collection
	output [collection*z*width-1:0] adot_coll_in,
	
	// Next 5 signals are for DMp
	output [2*z*log_pbyz-1:0] del_coll_addrA,
	output [2*z-1:0] del_coll_weA,
	output [2*z*log_pbyz-1:0] del_coll_addrB,
	output [2*z-1:0] del_coll_weB,
	output [2*z*width-1:0] del_coll_partial_inB,
	
	output [$clog2(collection)-1:0] act_coll_rFF_pt, //AM collection from which FF is computed for next layer
	output [$clog2(collection)-1:0] act_coll_rUP_pt,	//AM collection used for UP. IMPORTANT: Also collection which provides adot values for current layer BP
	output del_coll_rBP_pt,	//DM collection from which BP is computed for previous layer
	output [$clog2(cpc)-1:0] cycle_index_delay1	//1 cycle delay of cycle_index, will be used in layer_block
);

	//logic [$clog2(cpc)-1:0] cycle_index_delay2; //Used for writing to AM
	logic [$clog2(cpc)-1:0] cycle_index_delay_proc1;
	logic [$clog2(cpc)-1:0] cycle_index_delay_proc2;
	logic [$clog2(collection)-1:0] act_coll_wFF_pt; //AM collection whose FF is being computed in current layer. IMPORTANT: Also ADM collection currently being written into
	logic [log_pbyz*z-1:0] wFF_addr; //write the FF values coming from previous layer into memory
	
	logic [log_pbyz*z-1:0] act_mem_addr [collection-1:0]; //unpacked AMp addresses
	logic [z-1:0] act_mem_we [collection-1:0]; //unpacked AMp write enables
	
	logic [log_pbyz*z-1:0] del_mem_addrA[1:0], del_mem_addrB[1:0]; //unpacked DMp addresses. [1:0] is used because there are 2 collections
	logic [log_pbyz*z-1:0] del_r_addr, del_r_addr_delay_proc1; //see below
	logic [log_pbyz*z-1:0] r_addr_decoded_delay_proc1;

	genvar gv_i, gv_j, gv_k;
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: act_mem_addr_collection
		assign act_mem_addr[gv_i] = (gv_i == act_coll_wFF_pt)? wFF_addr : r_addr_decoded; //basically if you are not writing to a collection, you can read from it. Read is not destructive
	end
	endgenerate
	
	// Pack write enables into 1D layer for outputting to hidden layer memories
	// The memories can be written into during any set of cycles in the block cycle, it doesn't really matter since they won't be read till the next junction cycle
	//the z parallel memory will be divided into (fo) parts. all parts will be loaded in sequence (z/fo) times.
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1) //choose collection out of collection collections
	begin: act_mem_we_collections
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1) //choose part out of fo parts in a collection
		begin: act_mem_we_one_collection
			for (gv_k = 0; gv_k<(z/fo); gv_k = gv_k + 1) //choose memory out of z/fo memories in a part
			begin: act_mem_we_one_cycle
				if (fo>1)
					assign act_mem_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay_proc2 < p*fo/z) && //check that there are clocks left in cycle
						(gv_j==cycle_index_delay_proc2[$clog2(fo)-1:0]) && //check that current clock is referencing correct part
						(gv_i==act_coll_wFF_pt))? ~reset : 0; //check that correct collection is selected and reset is off
				else
					assign act_mem_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay_proc2 < p*fo/z) && //check that there are clocks left in cycle
						//part has to match because fo=1, so there's only 1 part
						(gv_i==act_coll_wFF_pt))? ~reset : 0; //check that correct collection is selected and reset is off	
			end
		end
	end
	endgenerate
	
	// This is for unpacking 'collection' AM collections
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: package_collection
		if (p==z)
			assign act_coll_addr[z*log_pbyz*(gv_i+1)-1:z*log_pbyz*gv_i] = '0;
		else
			assign act_coll_addr[z*log_pbyz*(gv_i+1)-1:z*log_pbyz*gv_i] = act_mem_addr[gv_i];
		assign act_coll_we[z*(gv_i+1)-1:z*gv_i] = act_mem_we[gv_i];
	end
	endgenerate

 /* Pack act and adot input data from previous layer into 1D array for outputting to hidden layer memories
	in one clock, (z/fo) [Eg=32] activations will be loaded to activation memory
	memory parallelism is z [Eg=128], and clocks per cycle is (p/z*fo) [Eg=32]
	the z [Eg=128] parallel memories will be divided into fo [Eg=4] parts. Each part will load a value, i.e. 32 values total
	each memory should be loaded p/z [Eg=8] times */
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: data_collections
		 for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1)
		begin: data_one_collection
			assign act_coll_in[(z*gv_i + z/fo*(gv_j+1)) * width -1:(z*gv_i+z/fo*gv_j)*width] = act_in;
			// z*gv_i sweeps collections. There are fo parts, each part having z/fo memories. z/fo*gv_j sweeps parts.
			// act_in contains all entries for 1 cell in a part, i.e. z/fo memories * width data
			// Same for adot_in below
			assign adot_coll_in[(z*gv_i+z/fo*(gv_j+1))*width-1:(z*gv_i+z/fo*gv_j)*width] = adot_in;
		end
	end
	endgenerate
	
	//this generate block assigns the raw write address by cycle index. z DMp addresses, each = log(p/z) bits
    //raw write address means the address is the write address for selected collection memory
    generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
    begin: raw_addr_generator
        if (p==z) begin //each mem has just 1 element, so all addresses are always 0
            assign wFF_addr[log_pbyz*(gv_i+1)-1:log_pbyz*gv_i] = '0;
            assign del_r_addr[log_pbyz*(gv_i+1)-1:log_pbyz*gv_i] = '0;
        end else begin
            assign wFF_addr[log_pbyz*(gv_i+1)-1:log_pbyz*gv_i] 
                = cycle_index_delay_proc2[$clog2(p/z*fo)-1:$clog2(fo)]; //Take all MSB of cycle_index_delay_proc2 except for log(fo) LSB. This is the cell address for writing
                /* [Eg: If p = 1024, z = 128, fo=4, then 1 AMp collection has fo=4 parts, each part has z/fo=32 memories, each memory has p/z=8 entries.
                   cpc = 32. So in 1st cycle, write cell 0 of 1st 32 memories, then cell 0 of next 32 memories in next cycle and so on.
                   So cell number remains constant for 4 cycles, so we discard log(fo)=2 LSB]. Same thing for BP */
            assign del_r_addr[log_pbyz*(gv_i+1)-1:log_pbyz*gv_i] 
                = cycle_index[$clog2(p/z*fo)-1:$clog2(fo)];
        end
    end
    endgenerate

	
/*  Delta memory working:
    There are 2 collections, each has ports A and B, each can read and write, and so each port has separate write enables and addresses
    But remember that each memory just has a single location for each address, so if addrA=addrB, they access the same value
    #locations in each mem = p/z
    
    Now assume del_coll_rBP_pt = 0, so collection 0 is being read to compute BP for previous layer, while collection 1 is doing read-modify-write for BP of current layer
    Port A of coll 0 will always be read:
        So all its weA = 0.
        Since it is read in natural order, addrA will be 0 for (p*fo/z)/(p/z)=fo cycles, then 1, and so on up to p/z-1. This will leave 2+`PROCTIME cycles at end which are garbage for reading
    Port B of coll 0 must be used for writing. We should write 0 here because this will be the R-M-W collection for the next cycle_clk and will accumulate partial_d, so must start from 0
        So weB will be 1 after `PROCTIME+1 delay. The delay ensures that reading for each location is first completed before overwriting the value by writing 0
            There are z mems with p/z locations each, and p*fo/z cycles. Thus, #mems for which weB should be 1 at the same time = (z*p/z)/(p*fo/z) = z/fo
        Since it is written in natural order, addrB will be 0 for (p*fo/z)/(p/z)=fo cycles starting from 1+`PROCTIME, then 1, and so on up to p/z-1. This will leave (2+`PROCTIME)-(1+`PROCTIME)=1 cycle at the end, which is garbage for writing
    
    Coll1 is more tricky since it's doing R-M-W, and we must ensure that writes don't destroy reads. A good way to do this is to make write addresses be equal to read addresses after 1 cycle delay (similar to how the weights are read and updated)
    Port B of coll 1 will always be read for the R in R-M-W:
        So its weB = 0
        Note that 0 will be attempted to be written to port B of both collections, but will only succeed for coll 0 because weB of coll 1 = 0
        addrB will start from all 0, then all 1, and move up to all p/z-1, then reset to all 0 and so on. This will leave 2+`PROCTIME cycles at end which are garbage for reading
    Port A of coll 1 must be used for the W in R-M-W:
        So all its weA will be 1 after `PROCTIME+1 delay.
        Just like addrB, addrA will start from all 0 at cycle `PROCTIME+1, then all 1, and move up to all p/z-1, then reset to all 0 and so on. This will leave (2+`PROCTIME)-(1+`PROCTIME)=1 cycle at the end, which is garbage for writing
        IMPORTANT: We must take care so that addrA is never equal to addrB. Design `PROCTIME accordingly
            For example, if p/z=2 (i.e. #locs=2 in each mem), and `PROCTIME is odd, then 1+`PROCTIME is even, so addrA and addrB will be identical including the period when we=1. This could destroy values
*/
	
	// This is for unpacking 2 DM collections
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: package_delta
		if (p==z) begin
			assign del_coll_addrA[(gv_i+1)*z*log_pbyz-1:z*log_pbyz*gv_i] = '0;
			assign del_coll_addrB[(gv_i+1)*z*log_pbyz-1:z*log_pbyz*gv_i] = '0;
		end else begin
			assign del_coll_addrA[(gv_i+1)*z*log_pbyz-1:z*log_pbyz*gv_i] = del_mem_addrA[gv_i];
			assign del_coll_addrB[(gv_i+1)*z*log_pbyz-1:z*log_pbyz*gv_i] = del_mem_addrB[gv_i];
		end
		for (gv_j = 0; gv_j<z; gv_j = gv_j + 1)
		begin: package_delta_data
			assign del_coll_partial_inB[width*(gv_i*z+gv_j+1)-1:width*(gv_i*z+gv_j)] = 0; //Attempt to write 0 to port B of both collections
		end
	end
	endgenerate

	// DM weA
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: d_control
		for (gv_j = 0; gv_j<z; gv_j = gv_j + 1)
		begin: d_control_one_collection
			assign del_coll_weA[gv_i*z+gv_j] = 
			((gv_i == del_coll_rBP_pt)||(cycle_index < `PROCTIME+1)||(cycle_index>=cpc-1)) ? 0 : 1;
			//From the example in comments, weA of rBP_pt collection = 0 and weA of ~rBP_pt collection = 1, unless it's the initial `PROCTIME clocks or the final clock
			//Eg: If p*fo/z = 32, `PROCTIME = 10, then cpc=44, so cycle_index goes from 0-43. Then, weA of ~rBP_pt collection will be 1 from cycles 11 to 42
		end
	end
	endgenerate

	// DM weB
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1) //choose part out of fo parts in a collection
			for (gv_k = 0; gv_k<(z/fo); gv_k = gv_k + 1) //choose memory out of z/fo memories in a part
				if (fo>1)
					assign del_coll_weB[gv_i*z+gv_j*(z/fo)+gv_k] = 
						((cycle_index_delay_proc1 < p*fo/z) &&
						(gv_j==cycle_index_delay_proc1[$clog2(fo)-1:0]) && //check for part match
						(gv_i==del_coll_rBP_pt))? 1: 0;
				else
					assign del_coll_weB[gv_i*z+gv_j*(z/fo)+gv_k] = 
						((cycle_index_delay_proc1 < p*fo/z) &&
						//part has to match since fo=1
						(gv_i==del_coll_rBP_pt))? 1: 0;
				// From the example in comments, weB of ~rBP_pt will be 0
				// weB of rBP_pt will be 1 only after `PROCTIME+1 clock delay, that is why we use cycle_index_delay_proc1 in the comparison, and not cycle_index
				// (cycle_index can be used of course, but that would lead to the additional condition of it needing to be greater than 0)
				// Writing 0 is done part by part, so we need to check for part match and write for exactly p*fo/z cycles, otherwise no. of parts will overshoot
	endgenerate

	// DM Addresses
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: d_addr
		assign del_mem_addrA[gv_i] = (gv_i == del_coll_rBP_pt)? del_r_addr : r_addr_decoded_delay_proc1;
		assign del_mem_addrB[gv_i] = (gv_i == del_coll_rBP_pt)? del_r_addr_delay_proc1: r_addr_decoded;
		/*  For rBP_pt coll, port A (read) address is the one sequentially computed from cycle index, i.e. the one that goes part by part.
				This is because we read DM in sequence for previous layer BP
			For the other (i.e. R-M-W) coll, port A (write) address is as generated from the interleaver, delayed by 1+`PROCTIME
			For rBP_pt coll, port B (write 0) address = Same as its port A (read) address, delayed by 1+`PROCTIME
			For the other (i.e. R-M-W) coll, port B (read) address is as generated from the interleaver */
	end
	endgenerate

	// Set pointers for AM and DM collections:
	counter #(.max(collection), 
		.ini(0)) act_rFF
		(cycle_clk, reset, act_coll_rFF_pt); //AM collection read pointer for next layer FF. Starts from 0, cycles through all collections

	counter #(.max(collection), 
		.ini(1)) act_wFF
		(cycle_clk, reset, act_coll_wFF_pt); //AM collection write pointer for FF being computed from previous layer. Always the coll after rFF

	counter #(.max(collection), 
		.ini(2)) act_rUP
		(cycle_clk, reset, act_coll_rUP_pt); //AM collection read pointer for UP (also gives adot for current layer BP). Always the coll 2 after FF

	counter #(.max(2), 
		.ini(0)) delta_r
		(cycle_clk, reset, del_coll_rBP_pt); //DM collection read pointer for previous layer BP

	shift_reg #(
	   .width(log_pbyz*z),
	   .depth(1+`PROCTIME)
	) sr_r_addr_decoded_delay_proc1 (
	   .clk(clk),
	   .reset(reset),
	   .d(r_addr_decoded),
	   .q(r_addr_decoded_delay_proc1)
	);
	
	shift_reg #(
	   .width(log_pbyz*z),
	   .depth(1+`PROCTIME)
	) sr_del_r_addr_delay_proc1 (
	   .clk(clk),
	   .reset(reset),
	   .d(del_r_addr),
	   .q(del_r_addr_delay_proc1)
	);
	
	DFF #(
       .width($clog2(cpc))
    ) DFF_cycle_index_delay1 (
        .clk(clk),
        .reset(reset),
        .d(cycle_index),
        .q(cycle_index_delay1)
    );
	
	shift_reg #(
       .width($clog2(cpc)),
       .depth(1+`PROCTIME)
    ) sr_cycle_index_delay_proc1 (
        .clk(clk),
        .reset(reset),
        .d(cycle_index),
        .q(cycle_index_delay_proc1)
    );
	
	DFF #(
	   .width($clog2(cpc))
    ) dff_cycle_index_delay_proc2 (
        .clk(clk),
	    .reset(reset),
	    .d(cycle_index_delay_proc1),
	    .q(cycle_index_delay_proc2)
	);
endmodule


module act_ctr #( // act_ctr is a subset of act_adot_ctr, without sigmoid prime
	parameter fo = 2,
	parameter p  = 16,
	parameter z  = 8,
	parameter L = 3,
	parameter cpc = p*fo/z + 12,
	parameter width = 1, //width of input data
	localparam collection = 2*L-1,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z)
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input [log_pbyz*z-1:0] r_addr_decoded,
	input [width*z/fo-1:0] act_in,
	output [collection*z*log_pbyz-1:0] act_coll_addr,
	output [collection*z-1:0] act_coll_we,
	output [collection*z*width-1:0] act_coll_in,
	output [$clog2(collection)-1:0] act_coll_rFF_pt,
	output [$clog2(collection)-1:0] act_coll_rUP_pt
);

	logic [$clog2(collection)-1:0] act_coll_wFF_pt;
	logic [$clog2(cpc)-1:0] cycle_index_delay2;
	logic [log_pbyz*z-1:0] wFF_addr;
	logic [log_pbyz*z-1:0] act_mem_addr[collection-1:0];
	logic [z-1:0] act_mem_we[collection-1:0];

	genvar gv_i, gv_j, gv_k;
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: package_collection
		assign act_coll_addr[z*log_pbyz*(gv_i+1)-1:z*log_pbyz*gv_i] = act_mem_addr[gv_i];
		assign act_coll_we[z*(gv_i+1)-1:z*gv_i] = act_mem_we[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: data_collections
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1)
		begin: data_one_collection
			assign act_coll_in[(z*gv_i+z/fo*(gv_j+1))*width-1:(z*gv_i+z/fo*gv_j)*width] = act_in;
		end
	end
	endgenerate

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1) //choose collection out of collection collections
	begin: act_mem_we_collections
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1) //choose part out of fo parts in a collection
		begin: act_mem_we_one_collection
			for (gv_k = 0; gv_k<(z/fo); gv_k = gv_k + 1) //choose memory out of z/fo memories in a part
			begin: act_mem_we_one_cycle
				if (fo>1)
					assign act_mem_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay2 < p*fo/z) && //check that there are clocks left in cycle
						(gv_j==cycle_index_delay2[$clog2(fo)-1:0]) && //check that current clock is referencing correct part
						(gv_i==act_coll_wFF_pt))? ~reset: 0; //check that correct collection is selected and reset is off
				else
					assign act_mem_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay2 < p*fo/z) && //check that there are clocks left in cycle
						//part has to match since fo=1
						(gv_i==act_coll_wFF_pt))? ~reset: 0; //check that correct collection is selected and reset is off
			end
		end
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: write_addr_generator
		if (p==z)
			assign wFF_addr = '0;
		else
			assign wFF_addr[log_pbyz*(gv_i+1)-1:log_pbyz*gv_i] 
				= cycle_index_delay2[$clog2(p*fo/z)-1:$clog2(fo)];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: addr_collection
		assign act_mem_addr[gv_i] = (gv_i == act_coll_wFF_pt)? wFF_addr : r_addr_decoded;
	end
	endgenerate
	

	counter #(.max(collection), 
		.ini(0)) act_r0
		(cycle_clk, reset, act_coll_rFF_pt);

	counter #(.max(collection), 
		.ini(1)) act_w
		(cycle_clk, reset, act_coll_wFF_pt);

	counter #(.max(collection), 
		.ini(2)) act_r1
		(cycle_clk, reset, act_coll_rUP_pt);
	
	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2)
	) sr_cycle_index_delay_input (
		.clk(clk),
		.reset(reset),
		.d(cycle_index),
		.q(cycle_index_delay2)
	);
endmodule


module hidden_layer_state_machine #( // This is state machine, so it will input data and output all mem data and control signals, i.e. for AMp, AMn, DMp, DMn
	parameter fo = 2,
	parameter p  = 8,
	parameter z  = 4,
	parameter L = 3,
	parameter h = 1, //Index. Layer after input has h = 1, then 2 and so on
	parameter cpc = p/z*fo + 12,
	parameter width = 16,
	localparam collection = 2*(L-h) - 1, //No. of AM and SM collections (SM means sigmoid prime memory)
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	
	input [width*z/fo-1:0] act_in, //z weights processed together and since fo weights = 1 neuron, z/fo activations processed together
	input [width*z/fo-1:0] adot_in, //Same as act
	output [collection*z*log_pbyz-1:0] act_coll_addr, //AMp collections, each has z AMs, each AM has p/z entries, so total address bits = collection*z*log(p/z)
	output [collection*z-1:0] act_coll_we, //Each AM has 1 we
	output [collection*z*width-1:0] act_coll_in, //Output data from a particular cell of all AMs
	output [collection*z*width-1:0] adot_coll_in, //Each read out datum from AM must have associated adot
	// For following DM parameters, replace collection with 2. Also, DM is dual port, so we need 2 addresses and 2 write enables
	output [2*z*log_pbyz-1:0] del_coll_addrA, //DMp collections
	output [2*z-1:0] del_coll_weA,
	output [2*z*log_pbyz-1:0] del_coll_addrB,
	output [2*z-1:0] del_coll_weB,
	output [2*z*width-1:0] del_coll_partial_inB, //Data to be written into DM port B
	
	output [log_z*z-1:0] muxsel1, //Delayed version of MUX for selecting inputs to processor sets after reading from memory (delay 1 cycle since mem needs 1 cycle to operate)
    output [log_z*z-1:0] muxsel_proc1, //Further delayed version of MUX for outputs from processor sets for writing to memory
    	
	//Reads are done for FF and UP (i.e. AMs). Following pointers are for reading 1 out of 2(L-h)-1 collections
	output [$clog2(collection)-1:0] act_coll_rFF_pt_final, //goes to FF
	output [$clog2(collection)-1:0] act_coll_rUP_pt_final, //goes to UP
	
	//Both read and write is done for BP (i.e. DMs). Following pointer is for reading/writing from 1 out of 2 collections (that's why they it's only 1 bit)
	output del_coll_rBP_pt, //choose collection from which read is done for preivous BP. Negation of this will be for write.
	output [$clog2(cpc)-1:0] cycle_index_delay1
);	

	logic [$clog2(p)*z-1:0] memory_index_package; //Output of z interleavers. Points to all z neurons in p layer from which activations are to be taken for FF
	logic [log_pbyz*z-1:0] r_addr_decoded; //z read addresses from all AMp for FF and UP
	//Note that same mem adresses are used for FF collection and UP collection, just because they are different collections, they need different del_coll_rBP_pt values
	logic [log_z*z-1:0] muxsel_initial; //z MUXes, each z-to-1, i.e. log(z) select bits
	logic [$clog2(collection)-1:0] act_coll_rFF_pt_initial, act_coll_rUP_pt_initial; //AM collections used for FF and UP

	// Set of z interleaver blocks. Takes cycle index as input, computes interleaved output
	interleaver_set #(
		.fo(fo),
	 	.p(p), 
	 	.z(z)
	) interleaver (
		.eff_cycle_index(cycle_index[$clog2(p*fo/z)-1:0]),
		.reset,
		.memory_index_package
	);

	address_decoder #(
	 	.p(p),
	 	.z(z)
	) address_decoder (
		.memory_index_package,
		.addr_package(r_addr_decoded),
		.muxsel_package(muxsel_initial)
	);

	act_adot_ctr #(
		.fo(fo),
		.p(p), 
		.z(z), 
		.L(L), 
		.h(h),
		.cpc(cpc), 
		.width(width)
	) act_adot_ctr (
		.clk,
		.reset,
		.cycle_clk,
		.cycle_index,
		.r_addr_decoded,
		.act_in,
		.adot_in,
		.act_coll_addr,
		.act_coll_we,
		.act_coll_in,
		.adot_coll_in, 
		.del_coll_addrA,
		.del_coll_weA,
		.del_coll_addrB,
		.del_coll_weB,
		.del_coll_partial_inB, 
		.act_coll_rFF_pt(act_coll_rFF_pt_initial),
		.act_coll_rUP_pt(act_coll_rUP_pt_initial),
		.del_coll_rBP_pt,
		.cycle_index_delay1
	);

	//Following signals are delayed by 1 to account for memory read time
	DFF #(
	   .width($clog2(collection))
	) DFF_act_coll_rFF_pt (
	   .clk(clk), 
	   .reset(reset), 
	   .d(act_coll_rFF_pt_initial), 
	   .q(act_coll_rFF_pt_final)
	);
        
    DFF #(
        .width($clog2(collection))
    ) DFF_act_coll_rUP_pt (
        .clk(clk),
        .reset(reset), 
        .d(act_coll_rUP_pt_initial), 
        .q(act_coll_rUP_pt_final)
    );
	
	DFF #(
	   .width(log_z*z)
	) DFF_muxsel1 (
	   .clk(clk),
	   .reset(reset),
	   .d(muxsel_initial),
	   .q(muxsel1)
	);

    //Following signals are further delayed by `PROCTIME (i.e. total 1+`PROCTIME) to account for processor set time 
    shift_reg #(
	   .width(log_z*z),
	   .depth(1+`PROCTIME)
	) sr_muxsel_proc1 (
	   .clk(clk),
	   .reset(reset),
	   .d(muxsel_initial),
	   .q(muxsel_proc1)
	);
endmodule


module input_layer_state_machine #( // first_layer_state_machine is a subset of hidden_layer_state_machine, without DMs
	parameter fo = 2,
	parameter p  = 16,
	parameter z  = 8,
	parameter L = 3,
	parameter cpc = p*fo/z + 12,
	parameter width = 1, //width of input data
	localparam collection = 2*L - 1,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input [width*z/fo-1:0] act_in,
	output [collection*z*log_pbyz-1:0] act_coll_addr,
	output [collection*z-1:0] act_coll_we,
	output [log_z*z-1:0] muxsel1,
	output [collection*z*width-1:0] act_coll_in,
	output [$clog2(collection)-1:0] act_coll_rFF_pt_final,
	output [$clog2(collection)-1:0] act_coll_rUP_pt_final
);

	logic [$clog2(p)*z-1:0] memory_index_package;
	logic [log_pbyz*z-1:0] act_mem_addr;
	logic [log_pbyz*z-1:0] r_addr_decoded;
	logic [log_z*z-1:0] muxsel_initial;
	logic [$clog2(collection)-1:0] act_coll_rFF_pt_initial, act_coll_rUP_pt_initial;

	interleaver_set #(
		.fo(fo),
	 	.p(p),
	 	.z(z)
	) interleaver (
		.eff_cycle_index(cycle_index[$clog2(p*fo/z)-1:0]),
		.reset(reset),
		.memory_index_package
	);

	address_decoder #(
	 	.p(p),
	 	.z(z)
	) address_decoder (
		.memory_index_package,
		.addr_package(r_addr_decoded),
		.muxsel_package(muxsel_initial)
	); 

	act_ctr	 #(
		.fo(fo), 
		.p(p), 
		.z(z), 
		.L(L), 
		.cpc(cpc), 
		.width(width)
	) act_ctr (
		.clk,
		.reset,
		.cycle_clk,
		.cycle_index,
		.r_addr_decoded,
		.act_in, 
		.act_coll_addr,
		.act_coll_we,
		.act_coll_in, 
		.act_coll_rFF_pt(act_coll_rFF_pt_initial),
		.act_coll_rUP_pt(act_coll_rUP_pt_initial)
	);

	//Following signals are delayed by 1 to account for memory read time
	DFF #(
	   .width($clog2(collection))
	) DFF_act_coll_rFF_pt (
	   .clk(clk), 
	   .reset(reset), 
	   .d(act_coll_rFF_pt_initial), 
	   .q(act_coll_rFF_pt_final)
	);
        
    DFF #(
        .width($clog2(collection))
    ) DFF_act_coll_rUP_pt (
        .clk(clk),
        .reset(reset), 
        .d(act_coll_rUP_pt_initial), 
        .q(act_coll_rUP_pt_final)
    );
	
	DFF #(
	   .width(log_z*z)
	) DFF_muxsel1 (
	   .clk(clk),
	   .reset(reset),
	   .d(muxsel_initial),
	   .q(muxsel1)
	);
endmodule


module output_layer_state_machine #( //This is a state machine, so it controls last layer by giving all memory and data control signals
	parameter zbyfi = 1,
	parameter p = 4, //Number of neurons in last layer
	parameter width = 16,
	parameter cpc = p/zbyfi + 12
	//There is no param for log_pbyzbyfi because p*fi/z is always > 1 (from constraints)
	//There is no param for collection because delta memory always has 2 collections in output layer. Each collection is a bunch of z memories, each of size p*fo/z
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk, //1 cycle_clk = cpc clks
	input [width*zbyfi-1:0] del_in, //delta, after it finishes computation from cost terms
	output [2*zbyfi*$clog2(p/zbyfi)-1:0] del_coll_addr, //lump all addresses together: collections * mem/collection * addr_bits/mem
	// Note that these addresses are for AM, so they are log(p/z) bits
	output [2*zbyfi-1:0] del_coll_we,
	output [2*zbyfi*width-1:0] del_coll_in,
	output del_coll_rBP_pt //selects 1 collection. 1b because no. of DM collections is always 2
);

	logic del_coll_wBP_pt_actual, del_coll_wBP_pt_initial; //1b because no. of DM collections is always 2
	//del_coll_wBP_pt_initial is collection which will be written in this cycle_clk (cost collection). del_coll_wBP_pt_actual is same thing, delayed by a few clocks until write starts
	logic [$clog2(cpc)-1:0] cycle_index_delay_proc2; //Used for writing
	
	// Unpack all collections together 1D array into 2D array, with 1 dimension exclusively for collection
	// Note that the other dimension still packs stuff for all z memories in a collection
	logic [zbyfi-1:0] del_mem_we[1:0];
	logic [zbyfi*$clog2(p/zbyfi)-1:0] del_mem_addr [1:0];
	logic [zbyfi*width-1:0] del_mem_in[1:0];
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: package_collection
		assign del_coll_in[width*zbyfi*(gv_i+1)-1:width*zbyfi*gv_i] = del_mem_in[gv_i];
		assign del_coll_addr[$clog2(p/zbyfi)*zbyfi*(gv_i+1)-1:$clog2(p/zbyfi)*zbyfi*gv_i] = del_mem_addr[gv_i];
		assign del_coll_we[zbyfi*(gv_i+1)-1:zbyfi*gv_i] = del_mem_we[gv_i];
	end
	endgenerate
	// Done unpack

	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: data_collections
		assign del_mem_in[gv_i] = del_in; //assign input `delta data from cost terms` to memories in both collections, later mux will select 1
	end
	endgenerate

	// Generate write enables
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: enable_set
		for (gv_j = 0; gv_j<zbyfi; gv_j = gv_j + 1)
		begin: enable
			assign del_mem_we[gv_i][gv_j] = (del_coll_wBP_pt_actual==gv_i && cycle_index>1+`PROCTIME)? ~reset : 0; //Writes start after processing is finished, i.e. from cycle 2+`PROCTIME
			assign del_mem_addr[gv_i][$clog2(p/zbyfi)*(gv_j+1)-1:$clog2(p/zbyfi)*gv_j] = 
				(del_coll_wBP_pt_actual==gv_i) ? cycle_index_delay_proc2[$clog2(p/zbyfi)-1:0] : cycle_index[$clog2(p/zbyfi)-1:0];
			//If del_coll_wBP_pt_actual equals collection ID (0 or 1), then memory is being written. Write in cycles 2+`PROCTIME, 3+`PROCTIME, ..., cpc-1 (which corresponds to 0,1,... of cycle_index_delay_proc2)
			//Otherwise memory is being read. Read in cycles 0,1,...,cpc-3-`PROCTIME
			//For example, if cpc is 44 and `PROCTIME is 10, then read in cycles 0-31, start operating from 1-32, end operating at 11-42, write in 12-43 (i.e. 0-31 of cycle_index_delay_proc2)
		end
	end
	endgenerate

	counter #(.max(2), //Counter for DM collections. After every cpc clocks (i.e. 1 cycle_clk), changes from 0->1 or 1->0
			.ini(0)) delta_del_coll_rBP_pt
			(cycle_clk, reset, del_coll_wBP_pt_initial);
	// Note that counter output is del_coll_wBP_pt_initial, which initially points to collection to be written into

	shift_reg #(
		.width(1),
		.depth(1+`PROCTIME)
	) sr_BP_pointer (
		.clk(clk),
		.reset(reset),
		.d(del_coll_wBP_pt_initial),
		.q(del_coll_wBP_pt_actual)
	); //1+`PROCTIME is enough because mem remains idle. 2+`PROCTIME is also fine
	
	assign del_coll_rBP_pt = ~del_coll_wBP_pt_initial; //Read pointer points to the other collection, form where I'm reading values and computing BP for prev layer
    /* RHS of the above line should be ~del_coll_wBP_pt_actual to make perfect timing sense, since del_coll_rBP_pt is used after processor sets finish
     * But since it's an assign statement, using ~del_coll_wBP_pt_initial is better since _actual isn't defined until after several clock cycles
     * This doesn't actually matter because the pointer values stay constant for a junction cycle */
    
	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2+`PROCTIME)
	) sr_cycle_index_delay_proc2_output (
		.clk(clk),
		.reset(reset),
		.d(cycle_index),
		.q(cycle_index_delay_proc2)
	);
endmodule
