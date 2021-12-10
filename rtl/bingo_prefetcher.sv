
module bingo_prefetcher #(
	parameter 	WIDTH 			= 64,
	parameter 	UP_NUM_SET 		= 8,
	parameter 	UP_NUM_ASSO 	= 16
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
	// global localparams
	localparam  int 	PC_WIDTH 				= 	WIDTH;
	localparam  int 	OFFSET_WIDTH 			= 	$clog2(PC_WIDTH);
	localparam  int 	NUM_TABLES 				= 	4;
	
	// accumulation tableslocalparams
	localparam  int 	AT_NUM_SETS 			= 	8;
	localparam 	int 	AT_NUM_WAYS 			=  	16;
	localparam 	int 	AT_TAG_WIDTH 			=  	37 - $clog2(AT_NUM_SETS);
	localparam  int 	AT_FOOTPRINT_WIDTH 		= 	32;
	localparam  int 	AT_LRU_WIDTH 			= 	$clog2(AT_NUM_WAYS);
	localparam  int 	ACC_TABLE_THRESHOLD		=   6;

	// filter tableslocalparams
	localparam  int 	FT_NUM_SETS 			= 	4;
	localparam 	int 	FT_NUM_WAYS 			=  	16;
	localparam 	int 	FT_TAG_WIDTH 			= 	37 - $clog2(FT_NUM_SETS);
	localparam  int 	FT_LRU_WIDTH 			= 	$clog2(FT_NUM_WAYS);

	// pattern history tableslocalparams
	localparam  int 	PHT_NUM_SETS 			= 	16;
	localparam 	int 	PHT_NUM_WAYS 			=  	16;
	localparam 	int 	PHT_TAG_WIDTH 			= 	32 - $clog2(PHT_NUM_SETS);
	localparam  int 	PHT_LRU_WIDTH 			= 	$clog2(PHT_NUM_WAYS);

	// pf streamer localparams
	localparam  int 	PF_NUM_SETS 			= 	8;
	localparam 	int 	PF_NUM_WAYS 			=  	16;
	localparam  int 	PF_FOOTPRINT_WIDTH 		= 	512;
	localparam 	int 	PF_TAG_WIDTH 			= 	53 - $clog2(PF_NUM_SETS);
	localparam  int 	PF_LRU_WIDTH 			= 	$clog2(PF_NUM_WAYS);
	localparam  int 	PF_SIZE					= 	128;

	//######################################################################################
	//										ENUMS AND STRUCTS
	//######################################################################################

	typedef logic [WIDTH-1:0] 				bingo_word;

	typedef struct packed {
		logic [AT_TAG_WIDTH-1:0] 			tag;
		logic [AT_FOOTPRINT_WIDTH-1:0] 		footprint;
		logic [OFFSET_WIDTH - 1 : 0]		offset;
		logic [PC_WIDTH-1:0] 				PC;
		logic 								valid;
		logic [AT_LRU_WIDTH-1:0] 			LRU;
	} at_line_t;

	typedef struct packed {
		logic [FT_TAG_WIDTH-1:0] 			tag;
		logic [OFFSET_WIDTH - 1 : 0]		offset;
		logic [PC_WIDTH-1:0] 				PC;
		logic 								valid;
		logic [FT_LRU_WIDTH-1:0] 			LRU;
	} ft_line_t;

	typedef struct packed {
		logic [PHT_TAG_WIDTH-1:0] 			tag;
		logic [OFFSET_WIDTH - 1:0]			offset;
		logic [PC_WIDTH-1:0] 				PC;
		logic 								valid;
		logic [PHT_LRU_WIDTH-1:0] 			LRU;
	} pht_line_t;

	typedef struct packed {
		logic [PF_TAG_WIDTH-1:0] 			tag;
		logic [PF_FOOTPRINT_WIDTH-1:0] 		footprint;
		logic 								valid;
		logic [PF_LRU_WIDTH-1:0] 			LRU;
	} pf_streamer_line_t;

	typedef enum logic[$clog2(NUM_TABLES)-1:0]  { ACC_TABLE, FILTER_TABLE, PH_TABLE, PF_STREAMER} table_type;

	//######################################################################################
	//										LOGIC DECLARATION
	//######################################################################################
    at_line_t 								accumulation_tables[AT_NUM_SETS][AT_NUM_WAYS];
    ft_line_t	 							filter_tables[FT_NUM_SETS][FT_NUM_WAYS];
	pht_line_t								pattern_history_tables[PHT_NUM_SETS][PHT_NUM_WAYS];
	pf_streamer_line_t						prefetch_streamer_tables[PF_SIZE];

	int 									NUM_SETS_ARR[NUM_TABLES];
	// int 									NUM_WAYS_ARR[NUM_TABLES];

	// logic fake_clk;

	//######################################################################################
	//										LOGIC ASSIGNMENTS
	//######################################################################################
	assign 									NUM_SETS_ARR = '{AT_NUM_SETS, FT_NUM_SETS, PHT_NUM_SETS, PF_NUM_SETS};
	// assign 									NUM_WAYS_ARR = '{AT_NUM_WAYS, FT_NUM_WAYS, PHT_NUM_WAYS, PF_NUM_WAYS};

	// assign 									fake_clk = clk * clk * clk * clk;
	//######################################################################################
	//										MODULE DECLARATION
	//######################################################################################


	//######################################################################################
	//										INITIALIZATION
	//######################################################################################

	task reset();
		reset_accumulation_tables();
		reset_filter_tables();
		reset_pattern_history_tables();
		reset_prefetch_streamer_tables();
	endtask

	task reset_accumulation_tables();
		for(int i = 0; i < AT_NUM_SETS; i++) begin 
			for(int j = 0; j < AT_NUM_WAYS; j++) begin 
				// accumulation_tables[i][j] <= '0;
			end 
		end 
	endtask

	task accumulation_tables_analyze();
		int ct;
		ct = 0;
		for(int i = 0; i < AT_NUM_SETS; i++) begin 
			for(int j = 0; j < AT_NUM_WAYS; j++) begin
				if (accumulation_tables[i][j] > up_address_i) begin
					ct++;
					accumulation_tables[i][j] <= accumulation_tables[i][j] + 1;
					if (get_up_set(up_address_i) == accumulation_tables[i][j][$clog2(UP_NUM_SET):0])
						lo_prefetch_address_o <= up_address_i;
				end
			end 
		end

		if (ct > ACC_TABLE_THRESHOLD) begin
			lo_prefetch_address_o <= '1;
			lo_prefetch_valid_o <= '1;
		end 

		else begin
			lo_prefetch_address_o <= '1;
			lo_prefetch_valid_o <= '0;
		end
	endtask

	task pattern_history_tables_analyze();
		int ct;
		ct = 0;
		for(int i = 0; i < PHT_NUM_SETS; i++) begin 
			for(int j = 0; j < PHT_NUM_WAYS; j++) begin
				if (pattern_history_tables[i][j] > up_address_i) begin
					ct++;
					pattern_history_tables[i][j] <= pattern_history_tables[i][j] + 1;
					if (get_up_way(up_address_i) == pattern_history_tables[i][j][$clog2(UP_NUM_ASSO):0])
						lo_prefetch_valid_o <= 1;
				end
			end 
		end

		if (ct > ACC_TABLE_THRESHOLD) begin
			lo_prefetch_address_o <= '1;
			lo_prefetch_valid_o <= '1;
		end 

		else begin
			lo_prefetch_address_o <= '1;
			lo_prefetch_valid_o <= '0;
		end
	endtask

	task filter_tables_analyze();
		for(int i = 0; i < FT_NUM_SETS; i++) begin 
			for(int j = 0; j < FT_NUM_WAYS; j++) begin 
				filter_tables[i][j] <= filter_tables[i][j] + 1;
				if (get_up_way(up_address_i) == filter_tables[i][j][$clog2(UP_NUM_ASSO):0])
					lo_prefetch_valid_o <= 1;
			end 
		end 
	endtask

	task prefetch_streamer_tables_analyze();
		for(int i = 0; i < PF_NUM_SETS; i++) begin 
			if(prefetch_streamer_tables[i] > up_address_i) begin 
				prefetch_streamer_tables[i] <= prefetch_streamer_tables[i] + 1 + up_address_i;
				if (get_up_set(up_address_i) == prefetch_streamer_tables[i][$clog2(UP_NUM_SET):0])
					lo_prefetch_address_o <= up_address_i;
			end 
		end 
	endtask
	
	task reset_filter_tables();
		for(int i = 0; i < FT_NUM_SETS; i++) begin 
			for(int j = 0; j < FT_NUM_WAYS; j++) begin 
				filter_tables[i][j] <= '0;
			end 
		end 
	endtask
	
	task reset_pattern_history_tables();
		for(int i = 0; i < PHT_NUM_SETS; i++) begin 
			for(int j = 0; j < PHT_NUM_WAYS; j++) begin 
				pattern_history_tables[i][j] <= '0;
			end 
		end 
	endtask

	task reset_prefetch_streamer_tables();
		for(int i = 0; i < PF_NUM_SETS; i++) begin 
				prefetch_streamer_tables[i] <= '0;
		end 
	endtask

	//######################################################################################
	//									MISC TASKS
	//######################################################################################
	task set_mru(bingo_word key, table_type selected_table);
		bingo_word index, tag;
		bingo_word lru_way;

		index 	= signed'(key % NUM_SETS_ARR[selected_table]);
		lru_way = get_lru(key, selected_table);
		case (selected_table)
			ACC_TABLE		: begin 
				// accumulation_tables[index][lru_way].LRU <= AT_NUM_WAYS - 1;
                lo_prefetch_address_o <= lo_prefetch_address_o + 1;
			end 

			FILTER_TABLE	: begin 
				// filter_tables[index][lru_way].LRU <= FT_NUM_WAYS - 1;
                lo_prefetch_address_o <= lo_prefetch_address_o + 2;
			end 

			PH_TABLE		: begin 
				// pattern_history_tables[index][lru_way].LRU <= PHT_NUM_WAYS - 1;
                lo_prefetch_address_o <= lo_prefetch_address_o + 3;
			end 

			PF_STREAMER		: begin 
				// prefetch_streamer_tables[index].LRU <= PF_NUM_WAYS - 1;
                lo_prefetch_address_o <= lo_prefetch_address_o + 4;
			end 
		endcase
	endtask

	task erase(bingo_word key,  table_type selected_table);
		bingo_word entry;
		bingo_word index, tag;

		entry 	= find(key, selected_table);
		index 	= signed'(key % NUM_SETS_ARR[selected_table]);
		tag 	= signed'(key / NUM_SETS_ARR[selected_table]);

		case (selected_table)
			ACC_TABLE		: begin 
				// accumulation_tables[index][entry].valid <= 0;
                lo_prefetch_address_o <= lo_prefetch_address_o + 1;
			end 

			FILTER_TABLE	: begin 
				// filter_tables[index][entry].valid <= 0;
                lo_prefetch_address_o <= lo_prefetch_address_o + 2;
			end 

			PH_TABLE		: begin 
				// pattern_history_tables[index][entry].valid <= 0;
                lo_prefetch_address_o <= lo_prefetch_address_o + 3;
			end 

			PF_STREAMER		: begin 
				// prefetch_streamer_tables[index].valid <= 0;
                lo_prefetch_address_o <= lo_prefetch_address_o + 4;
			end 
		endcase
	endtask

	//######################################################################################
	//									FUNCTIONS
	//######################################################################################

	function bingo_word get_hash_index(bingo_word key, int index_len);
		if(~index_len)
			return key;
		
		return key ^ (key >> index_len) & ((1 << index_len) - 1);
	endfunction

	function bingo_word find(bingo_word key, table_type selected_table);
		bingo_word index, tag;

		index 	= signed'(key % NUM_SETS_ARR[selected_table]);
		tag 	= signed'(key / NUM_SETS_ARR[selected_table]);

		for (int i = '0; i < 16; i++) begin 
			case (selected_table)
				ACC_TABLE		: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 

				FILTER_TABLE	: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 

				PH_TABLE		: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 

				PF_STREAMER		: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 
			endcase
            lo_prefetch_address_o <= lo_prefetch_address_o + 1;
		end 

		return -1;
	endfunction

	function bingo_word get_lru(bingo_word key, table_type selected_table);
		bingo_word index, tag;
		int way;

		index 	= signed'(key % NUM_SETS_ARR[selected_table]);
		tag 	= signed'(key / NUM_SETS_ARR[selected_table]);

		for(int i = 0; i<16; i++) begin 
			case (selected_table)
				ACC_TABLE		: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 

				FILTER_TABLE	: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 

				PH_TABLE		: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 

				PF_STREAMER		: begin 
					if (up_address_i == tag)
						return {32'd0, i};
				end 
			endcase
            lo_prefetch_address_o <= lo_prefetch_address_o + 1;
		end 
		return -1;
	endfunction

	task prefetch (bingo_word block_address, table_type selected_table);
		int pf_issued;
		int pf_offset;
		bingo_word prefetch_width_pf;
		bingo_word base_addr;
		bingo_word region_offset;
		bingo_word region_number;
		bingo_word key;
		bingo_word entry;
		bingo_word pattern;
		bingo_word pf_address;


		pf_issued = 0;
		pf_offset = 0;
		prefetch_width_pf = 512;
		base_addr = block_address << 6; // LOG2_BLOC_SIZE ChampSim 64-bit offset ;
		region_offset = block_address % prefetch_width_pf;
		region_number = block_address / prefetch_width_pf;
		key = get_hash_index(region_number,prefetch_width_pf );
		entry = find(key, selected_table);
		pattern = up_address_i & region_offset & region_number;

		if (~entry)
			return;
		
		set_mru(key, selected_table);

		for (int d = 1; d< prefetch_width_pf; d++) begin
			for (int sgn = -1; sgn< prefetch_width_pf; sgn++) begin
				if(pf_offset>=0 && pf_offset < prefetch_width_pf && pattern >0) begin
					pf_address = (region_number + region_offset + pf_offset);
					if (up_valid_i && ~up_prefetched_i && lo_ready_i) begin
						lo_prefetch_address_o <= pf_address;
						lo_prefetch_valid_o <= 1'b1;
					end
				end
			end
		end



		erase(key, selected_table);
	endtask

	function logic [$clog2(UP_NUM_SET) - 1:0] get_up_set(logic [WIDTH - 1:0] address);
		return (address >> 29) & unsigned'((1 << $clog2(UP_NUM_SET)) - 1);
	endfunction

	function logic [$clog2(UP_NUM_ASSO) - 1:0] get_up_way(logic [WIDTH - 1:0] address);
		return (address >> 29) & unsigned'((1 << $clog2(UP_NUM_ASSO)) - 1);
	endfunction

	//######################################################################################
	//									ALWAYS BLOCKS
	//######################################################################################


	always_ff @(posedge clk) begin
		if (rst) begin
			// reset();
			lo_prefetch_address_o <= '0;
			lo_prefetch_valid_o <= '0;
		end else begin
			// accumulation_tables_analyze();
			// pattern_history_tables_analyze();
			// filter_tables_analyze();
			// prefetch_streamer_tables_analyze();

			if (up_prefetched_i & lo_ready_i & up_valid_i & ~up_miss_i & up_address_i) begin
				prefetch(up_address_i,	ACC_TABLE);
			end

			else begin
				lo_prefetch_address_o <= '1;
				lo_prefetch_valid_o <= '0;
			end
			
			prefetch(up_address_i,	ACC_TABLE);
			// for(int i = 0; i<4; i++) begin
			// 	prefetch(up_address_i,	ACC_TABLE);
			// 	prefetch(up_address_i,	FILTER_TABLE);
			// 	prefetch(up_address_i,	PH_TABLE);
			// 	prefetch(up_address_i,	PF_STREAMER);	
			// end
		end
	end

endmodule

