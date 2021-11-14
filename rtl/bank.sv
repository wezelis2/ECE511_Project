module bank #(
	parameter 	WIDTH 		= 64,
	parameter 	TAG_WIDTH 	= 12,
	parameter 	INDEX_WIDTH = 6,
	parameter 	SIZE 		= 1 << INDEX_WIDTH,
	parameter 	SIDE 		= 1 				// 0 for left, 1 for right
)(
	input 		logic 					clk,
	input		logic 					rst,
				
	input 		logic 					read_i,
	input 		logic 					write_i,
	input 		logic 	[WIDTH - 1:0] 	data_i,

	output 		logic 					hit_o,				
	output	 	logic 					data_o,
	output 		logic 					valid_o
);

	logic 	[TAG_WIDTH - 1:0] bank_data [SIZE - 1:0];

	task reset_bank();
		for(int i = 0; i < SIZE; i++) begin 
			bank_data[i] 	<= '0;
		end 
	endtask

	task insert(logic [WIDTH - 1:0] data);
		bank_data[get_index(data)] <= get_tag(data);
	endtask

	function logic [WIDTH - 1:0] TRUNCATE(logic	[WIDTH - 1:0] x, int nbits);
		return x & ((1 << nbits) - 1);
	endfunction

	function logic [TAG_WIDTH - 1:0] get_tag(logic [WIDTH - 1:0] data);
		return TRUNCATE(data >> INDEX_WIDTH, TAG_WIDTH);
	endfunction

	function logic [INDEX_WIDTH - 1:0] get_index(logic [WIDTH - 1:0] data);
		return TRUNCATE(data ^ (data >> (INDEX_WIDTH << SIDE)), INDEX_WIDTH);
	endfunction

	assign hit 		= read_i & bank_data[get_index(data_i)] == get_tag(data_i);
	assign data_o 	= bank_data[get_index(data_i)];
	assign valid_o 	= read_i;

	always_ff @(posedge clk) begin
		if(rst) begin
			reset_bank();
		end else begin
			if(write_i)
				insert(data_i);
		end
	end

endmodule