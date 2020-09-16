`timescale 1ns / 1ps


module tb_BP_processor_set #(
    parameter z = 32,
    parameter fi = 16,
    parameter width = 10,
    parameter int_bits = 2
)(
);

    logic clk = 1;
    logic reset = 1;
    logic [width*z/fi-1:0] del_in_package; //input deln values
    logic [width*z -1:0] adot_out_package; //z weights can belong to z different p layer neurons, so we have z adot_out values
    logic [width*z -1:0] wt_package;
    logic [width*z -1:0] partial_del_out_package; //partial del values being constructed
    logic [width*z -1:0] del_out_package; //delp values
    
    BP_processor_set_pipelinemultadd #(
        .z(z),
        .fi(fi),
        .width(width),
        .int_bits(int_bits)
    ) BPps (
        .clk,
        .reset,
        .del_in_package,
        .adot_out_package,
        .wt_package,
        .partial_del_out_package,
        .del_out_package
    );
    
    always #5 clk = ~clk;
    
    //Non-pipelined mode is combinational, first result should come as soon as reset is 0
    //In pipelined mode, first result should come after `MAXLOGFI+`PIPELINEMULT+1 cycles of reset becoming 0
    
    // For z = 32, fi = 16 
    initial begin
        adot_out_package <= 320'h2000000000a0000000003000000000d800000000c000000000e00000000010000000000800000000;
        //n1: 1,0,0,0, -3,0,0,0, 1.5,0,0,0, -1.25,0,0,0; n0: -2,0,0,0, -1,0,0,0, 0.5,0,0,0, 0.25,0,0,0
        wt_package <= 320'h200000000000000000003000000000d800000000e000000000e00000000010000000000800000000;
        //n1: 1,0,0,0, 0,0,0,0, 1.5,0,0,0, -1.25,0,0,0; n0: -1,0,0,0, -1,0,0,0, 0.5,0,0,0, 0.25,0,0,0
        del_in_package <= 20'b00100000000010000000;
        //n1:1; n0: 1
        //mult results: n1: 1,0,0,0, 0,0,0,0, 2.25,0,0,0, 25/16,0,0,0; n0: 2,0,0,0, 1,0,0,0, 0.25,0,0,0, 1/16,0,0,0
        partial_del_out_package <= 320'he0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380;
        //n1: all -1; n0: all -1
        //results: n1 = 0,-1,-1,-1, -1,-1,-1,-1, 1.25,-1,-1,-1, 9/16,-1,-1,-1; n0 = 1,-1,-1,-1, 0,-1,-1,-1, -0.75,-1,-1,-1, -15/16,-1,-1,-1
        //combined: del_out_package = 00380e0380e0380e038028380e038012380e038020380e038000380e0380e8380e0380e2380e0380
        #91 reset = 0;
        #13;
        wt_package <= '0;
        //mult results are all 0
        partial_del_out_package <= 320'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        //combined del_out_package is the same as partial_del_out_package
        #23;
        wt_package <= 320'h20080200802008020080200802008020080200802008020080200802008020080200802008020080;
        //all weights are 1
        partial_del_out_package <= '0;
        //combined del_out_package is the same as adot_out_package
        #31;
        adot_out_package = 320'h4010040100401004010040100401004010040100c0300c0300c0300c0300c0300c0300c0300c0300;
        //all n1 = 2, all n2 = -2
        del_in_package <= 20'b01100000000110000000;
        //n1:3; n0:3
        //mult results: n1 all 6 (positive overflow), n0 all -6 (negative overflow)
        //combined del_out_package = 7fdff7fdff7fdff7fdff7fdff7fdff7fdff7fdff8020080200802008020080200802008020080200
        #95 $stop;
    end

endmodule
