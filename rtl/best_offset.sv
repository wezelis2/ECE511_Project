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
	input 		logic 					up_prefetched_i,		// upper level cache line was prefetched
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
	// localparam 	int 	MSHR_THRESHOLD_MAX 	=  	L2_MSHR_COUNT - 4;
	localparam 	int 	MSHR_THRESHOLD_MIN 	=  	2;
	localparam 	int 	LOW_SCORE 			=  	20;
	localparam 	int 	BAD_SCORE 			=  	1; //(knob_small_llc)	? 10 : 1;
	// localparam 	int 	BANDWIDTH 			=  	(knob_low_bandwidth)? 64 : 16;
	localparam 	int 	OFFSET_MAX 			= 	40;
	localparam 	int 	LINE_SIZE 			= 	256;
	localparam 	int 	LOGLINE				= 	6;

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
	//										ENUMS AND STRUCTS
	//######################################################################################
	typedef enum 	logic	{LEFT, RIGHT} 			rr_side;


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
	logic 											rr_hit;

	// delay queue signals
	logic 											delay_queue_enq;
	logic 			[WIDTH - 1:0]					delay_queue_in;
	logic 											delay_queue_empty;
	logic 											delay_queue_full;
	logic 											delay_queue_ready;
	logic 			[WIDTH - 1:0]					delay_queue_out;

	//######################################################################################
	//										LOGIC ASSIGNMENTS
	//######################################################################################
	assign 			next_max_score 			= 	score[curr_offset_idx] + 1 >= curr_max_score ? score[curr_offset_idx] + 1 : curr_max_score;
	assign 			next_best_offset_idx	= 	score[curr_offset_idx] + 1 >= curr_max_score ? curr_offset_idx : best_offset_idx;

	//######################################################################################
	//										MODULE DECLARATION
	//######################################################################################
	bank rr_table_left #(WIDTH, RRTAG, RRINDEX, 1 << RRINDEX, LEFT) (
		.read_i(read_left),
		.write_i(write_left),
		.data_i(data_left),
		.hit_o(hit_left),
		.data_o(data_left),
		.valid_o(valid_left),
		.*
	);

	bank rr_table_right #(WIDTH, RRTAG, RRINDEX, 1 << RRINDEX, RIGHT) (
		.read_i(read_right),
		.write_i(write_right),
		.data_i(data_right),
		.hit_o(hit_right),
		.data_o(data_right),
		.valid_o(valid_right),
		.*
	);

	circular_queue delay_queue #(WIDTH, DELAY) (
		.enq(delay_queue_enq),
		.deq(1'b1),
		.in(delay_queue_in),
		.empty(delay_queue_empty),
		.full(delay_queue_full),
		.ready(delay_queue_ready),
		.out(delay_queue_out),
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
		read_left			= '0;
		read_right			= '0;
		write_left			= '0;
		write_right			= '0;
		data_left			= '0;
		data_right			= '0;
		delay_queue_enq		= '0;
		delay_queue_in		= '0;
	endfunction

	//######################################################################################
	//									RR AND DQ TASKS
	//######################################################################################

	task rr_table_insert(logic [WIDTH - 1:0] data, rr_side side);
		unique case(side)
			LEFT: 	begin 
				write_left	<= 1'b1;
				data_left	<= data;
			end 

			RIGHT:	begin 
				write_right	<= 1'b1;
				data_right	<= data;
			end 

			default:;
		endcase
	endtask

	task delay_queue_push(logic [WIDTH - 1:0] data);
		delay_queue_enq 	<= 1'b1;
		delay_queue_in 		<= data;
	endtask

	task dq_pop_rr_left_insert();
		if(delay_queue_ready) begin 
			rr_table_insert(delay_queue_out, LEFT)
		end
	endtask

	//######################################################################################
	//									MISC TASKS
	//######################################################################################

	task learn_best_offset(logic [WIDTH - 1:0] address);
		logic 	signed 	[$clog2(OFFSET_MAX) - 1:0] 	test_offset = OFFSET[curr_offset_idx];
		logic 			[WIDTH - 1:0] 				test_addr 	= address - test_offset; 

		if (rr_hit) begin 
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

	task issue_prefetch(logic [WIDTH - 1:0] address, logic [$clog2(OFFSET_MAX) - 1:0] offset);
		delay_queue_push(address);
		if(offset != 0 && lo_ready_i) begin 
			lo_prefetch_address_o	<= address + offset;
			lo_prefetch_valid_o		<= 1;
		end 
	endtask

	task prefetcher_operate(logic [WIDTH - 1:0] address, logic hit);	// not done implementing
		logic 	[$clog2(UP_NUM_SET)  - 1:0] set 			= get_up_set(address);
		logic 	[$clog2(UP_NUM_ASSO) - 1:0] way 			= get_up_way(address);
		logic 								prefetched 		= 0;
		logic 								prefetch_issued	= offset != 0 && lo_ready_i;

		if (hit) begin 
			prefetched 										<= prefetched_table[set][way];
			prefetched_table[set][way] 						<= 0;
		end

		dq_pop_rr_left_insert();

		if (~hit | prefetched_table[set][way]) begin 
			learn_best_offset(address);
			issue_prefetch(address, prefetch_offset);
			// if (prefetch_issued)
				// something goes here?
		end 
	endtask

	task fill_cache(logic [WIDTH - 1:0] address, logic prefetch_bit);
		logic 	[$clog2(UP_NUM_SET)  - 1:0] set 			= get_up_set(address);
		logic 	[$clog2(UP_NUM_ASSO) - 1:0] way 			= get_up_way(address);

		prefetched_table[set][way] 							<= prefetch_bit;

		if (prefetch_bit || prefetch_offset == 0) begin 
			rr_table_insert((address >> LOGLINE) - prefetch_offset, RIGHT);
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

	function logic rr_check_hit (logic [WIDTH - 1:0] address, logic valid);
		read_left 	= 1;
		read_right	= 1;
		data_left	= address;
		data_right	= address;

		return valid & (hit_left | hit_right);
	endfunction

	//######################################################################################
	//									ALWAYS BLOCKS
	//######################################################################################


	always_ff @(posedge clk) begin
		if (rst) begin
			reset();
		end else begin
			prefetcher_operate(up_address_i, ~up_miss_i & up_valid_i)
			if (~up_miss_i & up_valid_i) begin 
				fill_cache(up_address_i, up_prefetched_i & up_valid_i);
			end 
		end
	end

	always_comb begin 
		set_defaults();
		rr_hit = rr_check_hit(up_address_i, up_valid_i);
	end

endmodule

