// This file contains a number of different types of memories
`timescale 1ns/100ps
`define PIPELINEMEM 0 //number of cycles BEYOND the normal 1 cycle to read from mem
//Set to 0 for 1 cycle latency (default behavior before pipelining)
//Set to n to have a total of n+1 cycles for mem accesses


//ideal out memory
module idealout_singleport_mem #(
	parameter depth = 12544,
	parameter width = 10,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [addrsize-1:0] address,
	input we,
	input [width-1:0] data_in,
	output [width-1:0] data_out
);

	// xpm_memory_spram: Single Port RAM
	// Xilinx Parameterized Macro, Version 2017.4
	xpm_memory_spram # (
	  
	  // Common module parameters
	  .MEMORY_SIZE             (width*depth),     //positive integer
	  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
	  .MEMORY_INIT_FILE        ("train_idealout_HEX.mem"),          //string; "none" or "<filename>.mem" 
	  .MEMORY_INIT_PARAM       (""    ),          //string;
	  .USE_MEM_INIT            (1),               //integer; 0,1
	  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
	  .MESSAGE_CONTROL         (0),               //integer; 0,1
	  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
	
	  // Port A module parameters
	  .WRITE_DATA_WIDTH_A      (width),              //positive integer
	  .READ_DATA_WIDTH_A       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
	  .ADDR_WIDTH_A            (addrsize),               //positive integer
	  .READ_RESET_VALUE_A      ("0"),             //string
	  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
	  .AUTO_SLEEP_TIME         (0),               //Do not Change
	  .READ_LATENCY_A          (1+`PIPELINEMEM),               //non-negative integer
	  .WRITE_MODE_A            ("read_first")     //string; "write_first", "read_first", "no_change" 
	
	) singleportmem (
	
	  // Common module ports
	  .sleep                   (1'b0),
	
	  // Port A module ports
	  .clka                    (clk),
	  .rsta                    (reset),
	  .ena                     (1'b1),
	  .regcea                  (1'b1),
	  .wea                     (we),
	  .addra                   (address),
	  .dina                    (data_in),
	  .injectsbiterra          (1'b0),
	  .injectdbiterra          (1'b0),
	  .douta                   (data_out),
	  .sbiterra                (),
	  .dbiterra                ()
	);
endmodule


//basic single port memory module
module singleport_mem #(
	parameter depth = 2, //No. of cells
	parameter width = 16, //No. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [addrsize-1:0] address,
	input we, //write enable
	input [width-1:0] data_in,
	output [width-1:0] data_out
);
	
	// xpm_memory_spram: Single Port RAM
	// Xilinx Parameterized Macro, Version 2017.4
	xpm_memory_spram # (
	  
	  // Common module parameters
	  .MEMORY_SIZE             (width*depth),     //positive integer
	  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
	  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
	  .MEMORY_INIT_PARAM       (""    ),          //string;
	  .USE_MEM_INIT            (1),               //integer; 0,1
	  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
	  .MESSAGE_CONTROL         (0),               //integer; 0,1
	  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
	
	  // Port A module parameters
	  .WRITE_DATA_WIDTH_A      (width),              //positive integer
	  .READ_DATA_WIDTH_A       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
	  .ADDR_WIDTH_A            (addrsize),               //positive integer
	  .READ_RESET_VALUE_A      ("0"),             //string
	  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
	  .AUTO_SLEEP_TIME         (0),               //Do not Change
	  .READ_LATENCY_A          (1+`PIPELINEMEM),               //non-negative integer
	  .WRITE_MODE_A            ("read_first")     //string; "write_first", "read_first", "no_change" 
	
	) singleportmem (
	
	  // Common module ports
	  .sleep                   (1'b0),
	
	  // Port A module ports
	  .clka                    (clk),
	  .rsta                    (reset),
	  .ena                     (1'b1),
	  .regcea                  (1'b1),
	  .wea                     (we),
	  .addra                   (address),
	  .dina                    (data_in),
	  .injectsbiterra          (1'b0),
	  .injectdbiterra          (1'b0),
	  .douta                   (data_out),
	  .sbiterra                (),
	  .dbiterra                ()
	);
endmodule


module parallel_singleport_mem #(
	parameter z = 8, //no. of mems, each having depth cells, each cell has width bits
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input reset,
	input [addrsize*z-1:0] address_package,
	input [z-1:0] we,
	input [width*z-1:0] data_in_package,
	output [width*z-1:0] data_out_package
);

	// Unpack
	logic [addrsize-1:0] address[z-1:0];
	logic [width-1:0] data_in[z-1:0];
	logic [width-1:0] data_out[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_in[gv_i] = data_in_package[width*(gv_i+1)-1:width*gv_i];
		assign data_out_package[width*(gv_i+1)-1:width*gv_i] = data_out[gv_i];
		assign address[gv_i] = address_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
	end
	endgenerate
	// Done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_singleport_mem
		singleport_mem #(
			.depth(depth),
			.width(width)
		) singleport_mem (
			.clk,
			.reset,
			.address(address[gv_i]),
			.we(we[gv_i]),
			.data_in(data_in[gv_i]),
			.data_out(data_out[gv_i])
		);
	end
	endgenerate
endmodule


module collection_singleport_mem #(
	parameter collection = 5, //no. of collections
	parameter z = 8, //no. of mems in each collection
	parameter depth = 2, //no. of cells in each mem
	parameter width = 16, //no. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [collection*z-1:0] we_package,
	input [collection*z*addrsize-1:0] addr_package,
	input [collection*z*width-1:0] data_in_package,
	output [collection*z*width-1:0] data_out_package
);

	// unpack
	logic [z-1:0] we [collection-1:0];
	logic [addrsize*z-1:0] addr[collection-1:0];
	logic [width*z-1:0] data_in[collection-1:0];
	logic [width*z-1:0] data_out[collection-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : package_collection
		assign we[gv_i] = we_package[z*(gv_i+1)-1:z*gv_i];
		assign addr[gv_i] = addr_package[z*addrsize*(gv_i+1)-1:z*addrsize*gv_i];
		assign data_in[gv_i] = data_in_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_out_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_out[gv_i];
	end
	endgenerate
	// done unpack
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : collection_singleport_mem
		parallel_singleport_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) parallel_singleport_mem (
			.clk,
			.reset,
			.address_package(addr[gv_i]),
			.we(we[gv_i]),
			.data_in_package(data_in[gv_i]),
			.data_out_package(data_out[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module simple_dualport_mem #( //port A used exclusively for writing, port B exclusively for reading
	parameter purpose = 1, //1 for junction 1, 2 for junction 2, ...
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input weA,
	input [addrsize-1:0] addressA,
	input [addrsize-1:0] addressB,
	input [width-1:0] data_inA,
	output [width-1:0] data_outB
);

	generate if (purpose==1) begin: input_wbmem_gen
	
		// xpm_memory_sdpram: Simple Dual Port RAM
		// Xilinx Parameterized Macro, Version 2017.4
		xpm_memory_sdpram # (
		
		  // Common module parameters
		  .MEMORY_SIZE             (depth*width),            //positive integer
		  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
		  .CLOCKING_MODE           ("common_clock"),  //string; "common_clock", "independent_clock" 
		  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
		  
		  //// 8b (1+2+5) cases: ////
		  //.MEMORY_INIT_PARAM	   ("0A,00,FC,FA,0C,0C,08,FC,02,F4,00,01,03,FE,FE,02,00,FF,F8,FD,FD,04,FE,F6,FD,04,01,FC,FE,06,FC,04"), //FPGAconfig64_32, cpc=32+2=34
		  
		  //// 10b (1+3+6) cases: ////
		  //.MEMORY_INIT_PARAM	   ("3FE,3F5,3FC,3ED,012,001,3FD,001,3FC,004,3E7,3FB,3EF,007,01C,00C,3FC,3EF,005,3F3,012,003,3FE,3FA,00D,3F2,00D,003,3F9,001,000,3FF"), //FPGAconfig64_32, cpc=32+2=34
		  
		  //// 10b (1+2+7) cases: ////
		  //.MEMORY_INIT_PARAM     ("3DA,002,3FD,3FB,016,00E,004,3E8,007,00D,3E9,3F4,002,3FF,008,00E"), //original config, cpc=16+...
		  .MEMORY_INIT_PARAM	   ("3D0,001,3E1,023,3F5,029,3F6,020,3E9,3F5,00C,3F2,3EE,3F8,3F7,3F3,3E8,3FB,3EF,001,00D,3E3,3FC,3F4,3F3,01A,3D2,3CF,3E3,3D6,001,025"),	//FPGAconfig, cpc=32+...
		  //.MEMORY_INIT_PARAM	   ("3F4,3F7,3F7,3FA,3F7,00C,00C,006,00A,3E7,3EC,3F3,3DA,3FB,01C,3E9,3F8,01E,002,3E2,3F1,3FE,011,3FB,006,001,3FD,00C,3EC,3F4,3E4,004,012,003,004,3F5,005,005,004,01C,3DD,023,3F3,025,3F7,01A,00F,3F9,00A,3F6,3F9,3ED,3F6,002,3E7,3F4,3FA,3FA,006,014,00C,3FF,3FD,00E"),	//cpc=64+...
		  
		  //// 12b (1+3+8) cases: ////
		  //.MEMORY_INIT_PARAM	   ("FDD,FD0,037,FBA,FD6,FD5,FD6,001,FDD,02C,00F,018,FEC,017,FE1,FF2,FC5,FD7,FB8,003,032,01A,FAC,FE9,FE9,000,FED,FC3,023,00E,021,01C"),	//FPGAconfig64_32, cpc=32+...
		  
		  //// 16b (1+4+11) cases: ////
		  //.MEMORY_INIT_PARAM	   ("FD17,01F4,00EB,FEEF,FFCC,FD08,FF99,02F4,FD04,0114,FFF3,00FE,005B,02B1,0088,FE77,FFF4,0053,00CD,0083,01FC,FFC8,FE4A,0015,FEC8,FED9,FDBE,FE8A,00A9,FE64,0259,02B6"), //FPGAconfig64_32, cpc=32+2=34
		  
		  .USE_MEM_INIT            (1),               //integer; 0,1
		  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
		  .MESSAGE_CONTROL         (0),               //integer; 0,1
		  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
		  .AUTO_SLEEP_TIME         (0),               //Do not Change
		  .USE_EMBEDDED_CONSTRAINT (0),               //integer: 0,1
		  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
		
		  // Port A module parameters
		  .WRITE_DATA_WIDTH_A      (width),              //positive integer
		  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
		  .ADDR_WIDTH_A            (addrsize),               //positive integer
		
		  // Port B module parameters
		  .READ_DATA_WIDTH_B       (width),              //positive integer
		  .ADDR_WIDTH_B            (addrsize),               //positive integer
		  .READ_RESET_VALUE_B      ("0"),             //string
		  .READ_LATENCY_B          (1+`PIPELINEMEM),               //non-negative integer
		  .WRITE_MODE_B            ("read_first")      //string; "write_first", "read_first", "no_change" 
		
		) simpledualport_input_wbmem (
		
		  // Common module ports
		  .sleep                   (1'b0),
		
		  // Port A module ports
		  .clka                    (clk),
		  .ena                     (1'b1),
		  .wea                     (weA),
		  .addra                   (addressA),
		  .dina                    (data_inA),
		  .injectsbiterra          (1'b0),
		  .injectdbiterra          (1'b0),
		
		  // Port B module ports
		  .clkb                    (1'b0),
		  .rstb                    (reset),
		  .enb                     (1'b1),
		  .regceb                  (1'b1),
		  .addrb                   (addressB),
		  .doutb                   (data_outB),
		  .sbiterrb                (),
		  .dbiterrb                ()
		
		);
		
	end else if (purpose==2) begin: hidden_wbmem_gen
			
		// xpm_memory_sdpram: Simple Dual Port RAM
		// Xilinx Parameterized Macro, Version 2017.4
		xpm_memory_sdpram # (
		
		  // Common module parameters
		  .MEMORY_SIZE             (depth*width),            //positive integer
		  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
		  .CLOCKING_MODE           ("common_clock"),  //string; "common_clock", "independent_clock" 
		  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
		  
		  //// 8b (1+2+5) cases: ////
		  //.MEMORY_INIT_PARAM	   ("FB,FC,0B,FE,02,05,04,FC,04,07,FD,05,F5,FF,FD,FF,FC,01,F4,FF,FA,F9,FD,FC,04,08,F8,FF,07,04,03,FD"), //FPGAconfig64_32, cpc=32+2=34
		  
		  //// 10b (1+3+6) cases: ////
		  //.MEMORY_INIT_PARAM	   ("3EC,3ED,3E8,3EF,3F7,3FD,00A,3FE,009,004,3F5,3F5,003,3FF,01B,004,3EE,3FA,00C,001,000,001,00E,006,3E2,011,013,006,3F9,3FE,3FC,007"), //FPGAconfig64_32, cpc=32+2=34
		  
		  //// 10b (1+2+7) cases: ////
		  //.MEMORY_INIT_PARAM     ("3D2,3E2,008,030,3F9,3E8,020,3FD,043,048,003,008,017,3F9,3DC,009"), //original_config, cpc=16+...
		  .MEMORY_INIT_PARAM	   ("01C,019,004,3EF,004,3E4,3EF,3E6,3FC,3FD,3F8,3CA,3FE,011,034,3D8,3FF,00E,3D6,00F,3F8,025,3FE,003,00E,041,3FF,018,00B,3F9,01A,3C8"),	//FPGAconfig, cpc=32+...
		  //.MEMORY_INIT_PARAM	   ("000,03F,02F,002,3C5,03F,3CF,3EF,01E,003,3FC,38C,002,026,3B0,008,039,05E,3C0,053,06D,038,038,3BE,01D,3AF,3F9,028,025,39E,021,004,011,058,3A7,030,014,3CD,051,02D,065,026,3EC,3F6,030,015,02C,04A,3A4,3EA,058,00E,094,01F,3CB,002,061,3A3,3E2,3F8,01A,3BE,391,3B5"),	//cpc=64+...
		  
		  //// 12b (1+3+8) cases: ////
		  //.MEMORY_INIT_PARAM	   ("065,022,023,062,FC6,02A,FD5,FF2,01C,FDF,015,FE0,FFF,FB0,FC9,007,FB6,FFD,00D,FE2,01C,053,0A0,F82,074,025,F92,FCC,FDE,006,FE5,00A"),	//FPGAconfig, cpc=32+...
		  
		  //// 16b (1+4+11) cases: ////
		  //.MEMORY_INIT_PARAM	   ("018F,001D,0228,019B,FF18,FFAD,FD05,FE17,FEF1,02CB,02C7,00B5,FDF6,FD2E,FF20,02D2,005C,0184,0111,019D,FF40,00EB,029E,0047,FF77,FF12,FE86,FEFB,FD57,FE93,FF35,FD33"), //FPGAconfig64_32, cpc=32+2=34
		  
		  .USE_MEM_INIT            (1),               //integer; 0,1
		  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
		  .MESSAGE_CONTROL         (0),               //integer; 0,1
		  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
		  .AUTO_SLEEP_TIME         (0),               //Do not Change
		  .USE_EMBEDDED_CONSTRAINT (0),               //integer: 0,1
		  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
		
		  // Port A module parameters
		  .WRITE_DATA_WIDTH_A      (width),              //positive integer
		  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
		  .ADDR_WIDTH_A            (addrsize),               //positive integer
		
		  // Port B module parameters
		  .READ_DATA_WIDTH_B       (width),              //positive integer
		  .ADDR_WIDTH_B            (addrsize),               //positive integer
		  .READ_RESET_VALUE_B      ("0"),             //string
		  .READ_LATENCY_B          (1+`PIPELINEMEM),               //non-negative integer
		  .WRITE_MODE_B            ("read_first")      //string; "write_first", "read_first", "no_change" 
		
		) simpledualport_hidden_wbmem (
		
		  // Common module ports
		  .sleep                   (1'b0),
		
		  // Port A module ports
		  .clka                    (clk),
		  .ena                     (1'b1),
		  .wea                     (weA),
		  .addra                   (addressA),
		  .dina                    (data_inA),
		  .injectsbiterra          (1'b0),
		  .injectdbiterra          (1'b0),
		
		  // Port B module ports
		  .clkb                    (1'b0),
		  .rstb                    (reset),
		  .enb                     (1'b1),
		  .regceb                  (1'b1),
		  .addrb                   (addressB),
		  .doutb                   (data_outB),
		  .sbiterrb                (),
		  .dbiterrb                ()
		
		);
		
	end
	endgenerate
endmodule


module parallel_simple_dualport_mem #(
	parameter purpose = 1,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input reset,
	input [z-1:0] weA_package,
	input [addrsize*z-1:0] addressA_package,
	input [addrsize*z-1:0] addressB_package,
	input [width*z-1:0] data_inA_package,
	output [width*z-1:0] data_outB_package
);

	// unpack
	logic [addrsize-1:0] addressA[z-1:0], addressB[z-1:0];
	logic [width-1:0] data_inA[z-1:0], data_inB[z-1:0];
	logic [width-1:0] data_outA[z-1:0], data_outB[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_inA[gv_i] = data_inA_package[width*(gv_i+1)-1:width*gv_i];
		assign addressA[gv_i] = addressA_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
		assign data_outB_package[width*(gv_i+1)-1:width*gv_i] = data_outB[gv_i];
		assign addressB[gv_i] = addressB_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
	end
	endgenerate
	// done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_simple_dualport_mem
		simple_dualport_mem #(
			.purpose(purpose),
			.depth(depth),
			.width(width)
		) simple_dualport_mem (
			.clk,
			.reset,
			.weA(weA_package[gv_i]),
			.addressA(addressA[gv_i]),
			.addressB(addressB[gv_i]),
			.data_inA(data_inA[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module true_dualport_mem #(
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input weA,
	input weB,
	input [addrsize-1:0] addressA,
	input [addrsize-1:0] addressB,
	input [width-1:0] data_inA,
	input [width-1:0] data_inB,
	output [width-1:0] data_outA,
	output [width-1:0] data_outB
);

	// xpm_memory_tdpram: True Dual Port RAM
	// Xilinx Parameterized Macro, Version 2017.4
	xpm_memory_tdpram # (
	
	  // Common module parameters
	  .MEMORY_SIZE             (depth*width),            //positive integer
	  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
	  .CLOCKING_MODE           ("common_clock"),  //string; "common_clock", "independent_clock" 
	  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
	  .MEMORY_INIT_PARAM       (""    ),          //string;
	  .USE_MEM_INIT            (1),               //integer; 0,1
	  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
	  .MESSAGE_CONTROL         (0),               //integer; 0,1
	  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
	  .AUTO_SLEEP_TIME         (0),               //Do not Change
	  .USE_EMBEDDED_CONSTRAINT (0),               //integer: 0,1
	  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
	
	  // Port A module parameters
	  .WRITE_DATA_WIDTH_A      (width),              //positive integer
	  .READ_DATA_WIDTH_A       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
	  .ADDR_WIDTH_A            (addrsize),               //positive integer
	  .READ_RESET_VALUE_A      ("0"),             //string
	  .READ_LATENCY_A          (1+`PIPELINEMEM),               //non-negative integer
	  .WRITE_MODE_A            ("read_first"),     //string; "write_first", "read_first", "no_change" 
	
	  // Port B module parameters
	  .WRITE_DATA_WIDTH_B      (width),              //positive integer
	  .READ_DATA_WIDTH_B       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_B      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
	  .ADDR_WIDTH_B            (addrsize),               //positive integer
	  .READ_RESET_VALUE_B      ("0"),             //vector of READ_DATA_WIDTH_B bits
	  .READ_LATENCY_B          (1+`PIPELINEMEM),               //non-negative integer
	  .WRITE_MODE_B            ("read_first")      //string; "write_first", "read_first", "no_change" 
	
	) truedualportmem_hidden_DMp (
	
	  // Common module ports
	  .sleep                   (1'b0),
	
	  // Port A module ports
	  .clka                    (clk),
	  .rsta                    (reset),
	  .ena                     (1'b1),
	  .regcea                  (1'b1),
	  .wea                     (weA),
	  .addra                   (addressA),
	  .dina                    (data_inA),
	  .injectsbiterra          (1'b0),
	  .injectdbiterra          (1'b0),
	  .douta                   (data_outA),
	  .sbiterra                (),
	  .dbiterra                (),
	
	  // Port B module ports
	  .clkb                    (1'b0),
	  .rstb                    (reset),
	  .enb                     (1'b1),
	  .regceb                  (1'b1),
	  .web                     (weB),
	  .addrb                   (addressB),
	  .dinb                    (data_inB),
	  .injectsbiterrb          (1'b0),
	  .injectdbiterrb          (1'b0),
	  .doutb                   (data_outB),
	  .sbiterrb                (),
	  .dbiterrb                ()
	
	);
endmodule


module parallel_true_dualport_mem #(
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input reset,
	input [z-1:0] weA,
	input [z-1:0] weB,
	input [addrsize*z-1:0] addressA_package,
	input [addrsize*z-1:0] addressB_package,
	input [width*z-1:0] data_inA_package,
	input [width*z-1:0] data_inB_package,
	output [width*z-1:0] data_outA_package,
	output [width*z-1:0] data_outB_package
);

	// unpack
	logic [addrsize-1:0] addressA[z-1:0], addressB[z-1:0];
	logic [width-1:0] data_inA[z-1:0], data_inB[z-1:0];
	logic [width-1:0] data_outA[z-1:0], data_outB[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_inA[gv_i] = data_inA_package[width*(gv_i+1)-1:width*gv_i];
		assign data_outA_package[width*(gv_i+1)-1:width*gv_i] = data_outA[gv_i];
		assign addressA[gv_i] = addressA_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
		assign data_inB[gv_i] = data_inB_package[width*(gv_i+1)-1:width*gv_i];
		assign data_outB_package[width*(gv_i+1)-1:width*gv_i] = data_outB[gv_i];
		assign addressB[gv_i] = addressB_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
	end
	endgenerate
	// done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_true_dualport_mem
		true_dualport_mem #(
			.depth(depth),
			.width(width)
		) true_dualport_mem (
			.clk,
			.reset,
			.addressA(addressA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA(data_inA[gv_i]),
			.data_outA(data_outA[gv_i]),
			.addressB(addressB[gv_i]),
			.weB(weB[gv_i]),
			.data_inB(data_inB[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule


module collection_true_dualport_mem #(	
	parameter collection = 5,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [collection*z-1:0] weA_package,
	input [collection*z-1:0] weB_package,
	input [collection*z*addrsize-1:0] addrA_package,
	input [collection*z*addrsize-1:0] addrB_package,
	input [collection*z*width-1:0] data_inA_package,
	input [collection*z*width-1:0] data_inB_package,
	output [collection*z*width-1:0] data_outA_package,
	output [collection*z*width-1:0] data_outB_package
);

	// unpack
	logic [z-1:0] weA[collection-1:0], weB[collection-1:0];
	logic [addrsize*z-1:0] addrA[collection-1:0], addrB[collection-1:0];
	logic [width*z-1:0] data_inA[collection-1:0], data_inB[collection-1:0];
	logic [width*z-1:0] data_outA[collection-1:0], data_outB[collection-1:0];	
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : package_collection
		assign weA[gv_i] = weA_package[z*(gv_i+1)-1:z*gv_i];
		assign addrA[gv_i] = addrA_package[z*addrsize*(gv_i+1)-1:z*addrsize*gv_i];
		assign data_inA[gv_i] = data_inA_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_outA_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_outA[gv_i];
		assign weB[gv_i] = weB_package[z*(gv_i+1)-1:z*gv_i];
		assign addrB[gv_i] = addrB_package[z*addrsize*(gv_i+1)-1:z*addrsize*gv_i];
		assign data_inB[gv_i] = data_inB_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_outB_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_outB[gv_i];
	end
	endgenerate
	// done unpack
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : collection_true_dualport_mem
		parallel_true_dualport_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) parallel_true_dualport_mem (
			.clk,
			.reset,
			.addressA_package(addrA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA_package(data_inA[gv_i]),
			.data_outA_package(data_outA[gv_i]),
			.addressB_package(addrB[gv_i]),
			.weB(weB[gv_i]),
			.data_inB_package(data_inB[gv_i]),
			.data_outB_package(data_outB[gv_i])
		);
	end
	endgenerate
endmodule
