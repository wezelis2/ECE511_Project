`define NOFFSETS 			46
`define OFFSET_MAX			40

module best_offset_prefetcher #(
	parameter 	WIDTH 			= 64,
	parameter 	TAG_WIDTH 		= 12,
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
	output 		logic 					lo_prefetch_valid_o	// lower level cache prefetch valid
);
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
	localparam 	int 	LINE_SIZE 			= 	256;
	localparam 	int 	LOGLINE				= 	6;

	//######################################################################################
	//										ENUMS AND STRUCTS
	//######################################################################################
	typedef enum 	logic	{LEFT, RIGHT} 			rr_side;


	//######################################################################################
	//										LOGIC DECLARATION
	//######################################################################################

	logic 	signed 	[$clog2(`OFFSET_MAX) - 1:0] 	prefetch_offset;
	logic 			[$clog2(SCORE_MAX) 	- 1:0]	 	prefetch_score;
	// logic 		 	[RRTAG - 1:0]					rr_table 			[1:0] [1<<RRINDEX - 1:0];
	logic 											prefetched_table 	[UP_NUM_SET];
	logic 			[$clog2(SCORE_MAX) - 1:0] 		score 				[`NOFFSETS - 1:0];
	logic 			[$clog2(SCORE_MAX) - 1:0] 		curr_max_score, next_max_score;
	logic 			[$clog2(`NOFFSETS)  - 1:0] 		best_offset_idx, next_best_offset_idx;
	logic 			[$clog2(ROUND_MAX) - 1:0]		curr_round;
	logic 			[$clog2(`NOFFSETS)  - 1:0]		curr_offset_idx;	// p in original c code
	int 											OFFSET[`NOFFSETS-1:0];

	// recent requests table signals
	logic 											read_left, 			read_right;
	logic 											write_left, 		write_right;
	logic 			[TAG_WIDTH - 1:0] 				data_left, 			data_right;
	logic 											hit_left, 			hit_right;
	logic 											data_left_out, 		data_right_out;
	logic 											valid_left, 		valid_right;
	logic 											rr_hit;
	logic 			[TAG_WIDTH - 1:0]				read_address_left, 	read_address_right;		

	// delay queue signals
	logic 											delay_queue_enq;
	logic 			[TAG_WIDTH - 1:0]				delay_queue_in;
	logic 											delay_queue_empty;
	logic 											delay_queue_full;
	logic 											delay_queue_ready;
	logic 			[TAG_WIDTH - 1:0]				delay_queue_out;

	//######################################################################################
	//										LOGIC ASSIGNMENTS
	//######################################################################################
	assign 			next_max_score 			= 	score[curr_offset_idx] + 1 >= curr_max_score ? score[curr_offset_idx] + 1 : curr_max_score;
	assign 			next_best_offset_idx	= 	score[curr_offset_idx] + 1 >= curr_max_score ? curr_offset_idx : best_offset_idx;
	assign 			OFFSET 					= 	'{	1,		-1,		2,		-2,		
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
													`OFFSET_MAX,	-`OFFSET_MAX};

	//######################################################################################
	//										MODULE DECLARATION
	//######################################################################################
	bank #(TAG_WIDTH, RRTAG, RRINDEX, 1 << RRINDEX, LEFT) rr_table_left (
		.read_i(read_left),
		.write_i(write_left),
		.data_i(data_left),
		.read_address_i(read_address_left),
		.hit_o(hit_left),
		.data_o(data_left_out),
		.valid_o(valid_left),
		.*
	);

	bank #(TAG_WIDTH, RRTAG, RRINDEX, 1 << RRINDEX, RIGHT) rr_table_right (
		.read_i(read_right),
		.write_i(write_right),
		.data_i(data_right),
		.read_address_i(read_address_right),
		.hit_o(hit_right),
		.data_o(data_right_out),
		.valid_o(valid_right),
		.*
	);

	circular_queue #(TAG_WIDTH, DELAY) delay_queue (
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
		for(int i = 0; i < `NOFFSETS; i++) begin 
			score[i] 	<= '0;
		end 

		curr_max_score	<= '0;
		best_offset_idx	<= '0;
		curr_round		<= '0;
		curr_offset_idx	<= '0;
	endtask

	task reset_prefetched_table();
<<<<<<< HEAD
		for(int i = 0; i < UP_NUM_SET; i++) begin
				prefetched_table[i] <= '0;
=======
		for(int i = 0; i < UP_NUM_SET; i++) begin 
			for(int j = 0; j < UP_NUM_ASSO; j++) begin 
				prefetched_table [i][j] <= '0;
			end 
>>>>>>> 8cca2f49d8aade6e5f16ae40b30ddfc812a92c07
		end 
	endtask

	function void set_defaults();
		read_left			= '0;
		read_right			= '0;
		write_left			= '0;
		write_right			= '0;
		data_left			= '0;
		data_right			= '0;
		// delay_queue_enq		= '0;
		// delay_queue_in		= '0;
	endfunction

	//######################################################################################
	//									RR AND DQ TASKS
	//######################################################################################

	function void rr_table_insert(logic [TAG_WIDTH - 1:0] data, rr_side side);
		unique case(side)
			LEFT: 	begin 
				write_right	= 0;
				write_left	= 1'b1;
				data_left	= data;
			end 

			RIGHT:	begin 
				write_right	= 1'b1;
				write_left	= 0;
				data_right	= data;
			end 
		endcase
	endfunction

	task delay_queue_push(logic [TAG_WIDTH - 1:0] data);
		delay_queue_enq 	<= 1'b1;
		delay_queue_in 		<= data;
	endtask

	function void dq_pop_rr_left_insert();
		if(delay_queue_ready) begin 
			rr_table_insert(delay_queue_out, LEFT);
		end else begin
			write_right	= 0;
			write_left	= 0;
			data_right	= '0;
		end
	endfunction

	//######################################################################################
	//									MISC TASKS
	//######################################################################################

	task learn_best_offset(logic [TAG_WIDTH - 1:0] address);
		if (rr_hit) begin 
			score[curr_offset_idx] 	<= score[curr_offset_idx] + 1 == SCORE_MAX ? SCORE_MAX : score[curr_offset_idx] + 1;
			curr_max_score 			<= next_max_score;
			best_offset_idx 		<= next_best_offset_idx;
		end 

		if (curr_offset_idx == unsigned'(`NOFFSETS - 1)) begin
			curr_round 				<= curr_round + 1;

			if(next_max_score == SCORE_MAX || (curr_round + 1) == ROUND_MAX) begin 
				prefetch_offset 	<= OFFSET[next_best_offset_idx] != 0 ? OFFSET[next_best_offset_idx] : DEFAULT_OFFSET;
				prefetch_score 		<= next_max_score;

				if (next_max_score 	<= BAD_SCORE)
					prefetch_offset <= 0;

				reset_offset_score();
			end 
		end 

		curr_offset_idx 			<= curr_offset_idx == unsigned'(`NOFFSETS - 1) ? 0 : curr_offset_idx + 1;
	endtask

	task issue_prefetch(logic [TAG_WIDTH - 1:0] address, logic [$clog2(`OFFSET_MAX) - 1:0] offset);
		delay_queue_push(address);
		if(offset != 0 && lo_ready_i) begin 
			lo_prefetch_address_o	<= address + offset;
			lo_prefetch_valid_o		<= 1;
		end 
	endtask

	task prefetcher_operate(logic [TAG_WIDTH - 1:0] address, logic hit);	// not done implementing
		if (hit) begin
			prefetched_table[get_up_set(address)] <= 0;
		end

		if (~hit | (hit & prefetched_table[get_up_set(address)])) begin 
			learn_best_offset(address);
			issue_prefetch(address, prefetch_offset);
			// if (prefetch_offset != 0 && lo_ready_i)
				// something goes here?
		end 
	endtask

	task fill_cache(logic [WIDTH - 1:0] address, logic prefetch_bit);
		prefetched_table[get_up_set(address)] <= prefetch_bit;
	endtask

	//######################################################################################
	//									FUNCTIONS
	//######################################################################################

<<<<<<< HEAD
	function logic [$clog2(UP_NUM_SET) - 1:0] get_up_set(logic [WIDTH - 1:0] address);
		return (address >> $clog2(LINE_SIZE)) & unsigned'(1 << ($clog2(UP_NUM_SET) - 1));
=======
	function logic [$clog2(UP_NUM_SET) - 1:0] get_up_set(logic [TAG_WIDTH - 1:0] address);
		return (address >> $clog2(LINE_SIZE)) & ((1 << $clog2(UP_NUM_SET)) - 1);
>>>>>>> 8cca2f49d8aade6e5f16ae40b30ddfc812a92c07
	endfunction

	function logic [$clog2(UP_NUM_ASSO) - 1:0] get_up_way(logic [TAG_WIDTH - 1:0] address);
		return 0;
	endfunction

	function void rr_check_hit (logic [TAG_WIDTH - 1:0] address, logic valid);
		read_left 			= valid;
		read_right			= valid;
		read_address_left	= address;
		read_address_right	= address;
		
		rr_hit 		= valid & (hit_left | hit_right);
	endfunction

	//######################################################################################
	//									ALWAYS BLOCKS
	//######################################################################################


	always_ff @(posedge clk) begin
		if (rst) begin
			reset();
		end else begin
			prefetcher_operate(up_address_i[WIDTH - 1 -: TAG_WIDTH], ~up_miss_i & up_valid_i);
			if (~up_miss_i & up_valid_i) begin 
				fill_cache(up_address_i[WIDTH - 1 -: TAG_WIDTH], up_prefetched_i & up_valid_i);
			end 
		end
	end

	always_comb begin 
		set_defaults();
<<<<<<< HEAD
		if (OFFSET[curr_offset_idx] < 0)
			rr_check_hit(up_address_i + unsigned'(~OFFSET[curr_offset_idx] + 1), up_valid_i);
		else
			rr_check_hit(up_address_i - unsigned'(OFFSET[curr_offset_idx]), up_valid_i);
		// rr_check_hit(up_address_i + (~(signed'(OFFSET[curr_offset_idx])) + 1), up_valid_i);
		dq_pop_rr_left_insert();
		if (up_prefetched_i || prefetch_offset == 0) begin 
			if (prefetch_offset < 0)
				rr_table_insert(up_address_i + unsigned'(~prefetch_offset + 1), RIGHT);
			else
				rr_table_insert(up_address_i - unsigned'(prefetch_offset), RIGHT);
=======
		rr_check_hit((up_address_i - signed'(OFFSET[curr_offset_idx])) >> (WIDTH - TAG_WID), up_valid_i);
		dq_pop_rr_left_insert();
		if (up_prefetched_i || prefetch_offset == 0) begin 
			rr_table_insert((up_address_i - prefetch_offset) >> (WIDTH - TAG_WID), RIGHT);
>>>>>>> 8cca2f49d8aade6e5f16ae40b30ddfc812a92c07
		end 
	end

endmodule

