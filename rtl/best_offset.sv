module best_offset_prefetcher #(
	parameter 	WIDTH 			= 64,
	parameter 	UP_NUM_SET 		= 8,
	parameter 	UP_NUM_ASSO 	= 0
) (
	input   	logic 					clk,
	input   	logic 					rst,
	input 		logic 	[WIDTH - 1:0] 	up_address_i,			// upper level cache address
	input 		logic 					up_miss_i,				// upper level cache hit / miss
	input 		logic 					up_valid_i,				// upper level cache valid 	-> ((read|write))
	input 		logic 					lo_ready_i,				// lower level cache ready to take requests
		
	output 		logic 	[WIDTH - 1:0]	lo_prefetch_address_o,	// lower level cache prefetch address
	output 		logic 					lo_prefetch_valid_o,	// lower level cache prefetch valid
);

	localparam 	int 	NOFFSETS 			=  	46;
	localparam 	int 	DEFAULT_OFFSET 		=  	1;
	localparam 	int 	SCORE_MAX 			=  	31;
	localparam 	int 	ROUND_MAX 			=  	100;
	localparam 	int 	RRINDEX 			=  	6;
	localparam 	int 	RRTAG 				=  	12;
	localparam 	int 	DELAYQSIZE 			=  	15;
	localparam 	int 	DELAY 				=  	60;
	localparam 	int 	TIME_BITS 			=  	12;
	localparam 	int 	LLC_RATE_MAX 		=  	255;
	localparam 	int 	GAUGE_MAX 			=  	8191;
	localparam 	int 	MSHR_THRESHOLD_MAX 	=  	L2_MSHR_COUNT - 4;
	localparam 	int 	MSHR_THRESHOLD_MIN 	=  	2;
	localparam 	int 	LOW_SCORE 			=  	20;
	localparam 	int 	BAD_SCORE 			=  	(knob_small_llc)	? 10 : 1;
	localparam 	int 	BANDWIDTH 			=  	(knob_low_bandwidth)? 64 : 16;
	localparam 	int 	OFFSET_MAX 			= 	40;
	localparam 	int 	LINE_SIZE 			= 	256;

	localparam 	int 	OFFSET[NOFFSETS-1:0]= 	{	1,		-1,		2,		-2,		
													3,		-3,		4,		-4,		
													5,		-5,		6,		-6,		
													7,		-7,		8,		-8,		
													9,		-9,		10,		-10,	
													11,		-11,	12,		-12,	
													13,		-13,	14,		-14,	
													15,		-15,	16,		-16,	
													18,		-18,	20,		-20,	
													24,		-24,	30,		-30,	
													32,		-32,	36,		-36,	
													OFFSET_MAX,		-OFFSET_MAX};

	//######################################################################################
	//										LOGIC DECLARATION
	//######################################################################################

	logic 	signed 	[$clog2(OFFSET_MAX) - 1:0] 		prefetch_offset;
	logic 			[$clog2(SCORE_MAX) 	- 1:0]	 	prefetch_score;
	// logic 		 	[RRTAG - 1:0]					rr_table 			[1:0] [1<<RRINDEX - 1:0];
	logic 											prefetched_table 	[UP_NUM_SET] [UP_NUM_ASSO];
	logic 			[$clog2(SCORE_MAX) - 1:0] 		score 				[NOFFSETS - 1:0];
	logic 			[$clog2(SCORE_MAX) - 1:0] 		curr_max_score, next_max_score;
	logic 			[$clog2(NOFFSETS)  - 1:0] 		best_offset_idx, next_best_offset_idx;
	logic 			[$clog2(ROUND_MAX) - 1:0]		curr_round;
	logic 			[$clog2(NOFFSETS)  - 1:0]		curr_offset_idx;	// p in original c code


	// recent requests table signals
	logic 											read_left, 	read_right;
	logic 											write_left, write_right;
	logic 			[WIDTH - 1:0] 					data_left, 	data_right;
	logic 											hit_left, 	hit_right;
	logic 											data_left, 	data_right;
	logic 											valid_left, valid_right;

	//######################################################################################
	//										LOGIC ASSIGNMENTS
	//######################################################################################
	assign 			next_max_score 			= 	score[curr_offset_idx] + 1 >= curr_max_score ? score[curr_offset_idx] + 1 : curr_max_score;
	assign 			next_best_offset_idx	= 	score[curr_offset_idx] + 1 >= curr_max_score ? curr_offset_idx : best_offset_idx;

	//######################################################################################
	//										MODULE DECLARATION
	//######################################################################################
	bank rr_table_left #(WIDTH, RRTAG, RRINDEX, 1 << RRINDEX, 0) (
		.read_i(read_left),
		.write_i(write_left),
		.data_i(data_left),
		.hit_o(hit_left),
		.data_o(data_left),
		.valid_o(valid_left),
		.*
	);

	bank rr_table_right #(WIDTH, RRTAG, RRINDEX, 1 << RRINDEX, 1) (
		.read_i(read_right),
		.write_i(write_right),
		.data_i(data_right),
		.hit_o(hit_right),
		.data_o(data_right),
		.valid_o(valid_right),
		.*
	);

	//######################################################################################
	//										INITIALIZATION
	//######################################################################################

	task reset();
		reset_offset_score();
		reset_prefetched_table();

		prefetch_offset <= '0;
		prefetch_score 	<= '0;
	endtask

	task reset_offset_score();
		for(int i = 0; i < NOFFSETS; i++) begin 
			score[i] 	<= '0;
		end 

		curr_max_score	<= '0;
		best_offset_idx	<= '0;
		curr_round		<= '0;
		curr_offset_idx	<= '0;
	endtask

	task reset_prefetched_table();
		for(int i = 0; i < UP_NUM_SET; i++) begin 
			for(int j = 0; j < UP_NUM_ASSO; j++) begin 
				prefetched_table <= '0;
			end 
		end 
	endtask

	function void set_defaults();
		read_left	= '0;
		read_right	= '0;
		write_left	= '0;
		write_right	= '0;
		data_left	= '0;
		data_right	= '0;
	endfunction

	//######################################################################################
	//									LEARNING TASKS
	//######################################################################################

	task learn_best_offset(logic [WIDTH - 1:0] address);
		logic 	signed 	[$clog2(OFFSET_MAX) - 1:0] 	test_offset = OFFSET[curr_offset_idx];
		logic 			[WIDTH - 1:0] 				test_addr 	= address - test_offset; 

		if (rr_check_hit(test_addr)) begin 
			score[curr_offset_idx] 	<= score[curr_offset_idx] + 1 == SCORE_MAX ? SCORE_MAX : score[curr_offset_idx] + 1;
			curr_max_score 			<= next_max_score;
			best_offset_idx 		<= next_best_offset_idx;
		end 

		if (curr_offset_idx == (NOFFSETS - 1)) begin
			curr_round 				<= curr_round + 1;

			if(next_max_score == SCORE_MAX || (curr_round + 1) == ROUND_MAX) begin 
				prefetch_offset 	<= OFFSET[next_best_offset_idx] != 0 ? OFFSET[next_best_offset_idx] : DEFAULT_OFFSET;
				prefetch_score 		<= next_max_score;

				if (next_max_score 	<= BAD_SCORE)
					prefetch_offset <= 0;

				reset_offset_score();
			end 
		end 

		curr_offset_idx 			<= curr_offset_idx == NOFFSETS - 1 ? 0 : curr_offset_idx + 1;
	endtask

	task up_fill_cache(logic [WIDTH - 1:0] address, logic hit);	// not done implementing
		logic 	[$clog2(UP_NUM_SET)  - 1:0] set 		= get_up_set(address);
		logic 	[$clog2(UP_NUM_ASSO) - 1:0] way 		= get_up_way(address);
		logic 								prefetched 	= 0;

		if (hit) begin 
			prefetched 									= prefetched_table[set][way];
			prefetched_table[set][way] 					= 0;
		end

		if (~hit | prefetched) begin 
			learn_best_offset(address);
		end 
	endtask


	//######################################################################################
	//									FUNCTIONS
	//######################################################################################

	function logic [$clog2(UP_NUM_SET) - 1:0] get_up_set(logic [WIDTH - 1:0] address);
		return (address >> $clog2(LINE_SIZE)) & ((1 << $clog2(UP_NUM_SET)) - 1);
	endfunction

	function logic [$clog2(UP_NUM_ASSO) - 1:0] get_up_way(logic [WIDTH - 1:0] address);
		return 0;
	endfunction

	function logic rr_check_hit (logic [WIDTH - 1:0] address);
		read_left 	= 1;
		read_right	= 1;
		data_left	= address;
		data_right	= address;

		return hit_left | hit_right;
	endfunction

endmodule
