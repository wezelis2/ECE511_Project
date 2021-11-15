// ECE511 Final Project Fall 2021
// Interface to Prefetcher.

`resetall
`timescale 1ns/10ps
interface prefetch_interface;

    logic 	[63:0] 	up_address_i;			// upper level cache address
    logic 			up_miss_i;				// upper level cache hit / miss
    logic 			up_valid_i;				// upper level cache valid 	-> ((read|write))
    logic 			lo_ready_i;				// lower level cache ready to take requests
    logic           up_prefetched_i;        // whether line has been prefetched before
    logic 	[63:0]	lo_prefetch_address_o;	// lower level cache prefetch address
    logic 			lo_prefetch_valid_o;	// lower level cache prefetch valid

endinterface
