module ip_stride #(parameter IP_TRACKER_COUNT = 8)
(
	input   logic 			clk,
	input   logic 			rst,
	input   logic   [63:0]  addr_i,
	input 	logic 	[63:0]	ip_i,
	output 	logic 	[63:0]	pref_addr1_o,
	output 	logic 	        pref_valid1_o,
	output 	logic 	[63:0]	pref_addr2_o,
	output 	logic 	        pref_valid2_o,
	output 	logic 	[63:0]	pref_addr3_o,
	output 	logic 	        pref_valid3_o,


	input   logic   [115:0] data_from_arr,
	input   logic           arr_hit,
	output  logic   [63:0]  addr_to_arr,
	output  logic   [115:0] data_to_arr,
	output  logic           arr_write
);

//Note: we hard code a prefetch degree of 3 throughout this code!

parameter ADDR_SIZE = 64;
parameter LOG2_BLOCK_SIZE = 6;
parameter LOG2_PAGE_SIZE = 12;
parameter CLA_SIZE = ADDR_SIZE - LOG2_BLOCK_SIZE;

typedef logic[ADDR_SIZE-1:0]              addr_t;
typedef logic[CLA_SIZE-1:0]               cla_t;
typedef logic signed[CLA_SIZE-1:0]        stride_t;

//trackers --> DELETE
// addr_t ip[IP_TRACKER_COUNT];
// cla_t last_cla[IP_TRACKER_COUNT];
// stride_t last_stride[IP_TRACKER_COUNT];


cla_t cla, last_cla;
int ip_match_idx;
stride_t stride, last_stride;
logic pref_valid1, pref_valid2, pref_valid3;
addr_t pref_addr1, pref_addr2, pref_addr3;
logic stride_match, addr1_page_match, addr2_page_match, addr3_page_match;

//Assign outputs
assign pref_valid1_o = pref_valid1;
assign pref_valid2_o = pref_valid2;
assign pref_valid3_o = pref_valid3;
assign pref_addr1_o = pref_addr1;
assign pref_addr2_o = pref_addr2;
assign pref_addr3_o = pref_addr3;

//Assign Prefetch Addresses (Degree == 3)
assign pref_addr1 = (cla + stride) << LOG2_BLOCK_SIZE;
assign pref_addr2 = (cla + (stride*2)) << LOG2_BLOCK_SIZE;
assign pref_addr3 = (cla + (stride*3)) << LOG2_BLOCK_SIZE;

//Black Box array assigns
assign addr_to_arr = ip_i;
assign data_to_arr = {cla, stride};
assign last_cla = data_from_arr[115:58];
assign last_stride = data_from_arr[57:0];

//Assign intermediate values
assign cla = addr_i >> LOG2_BLOCK_SIZE;
assign stride_match = stride == last_stride ? 1'b1 : 1'b0;
assign addr1_page_match = (pref_addr1 >> LOG2_PAGE_SIZE) == (addr_i >> LOG2_PAGE_SIZE) ? 1'b1 : 1'b0;
assign addr2_page_match = (pref_addr2 >> LOG2_PAGE_SIZE) == (addr_i >> LOG2_PAGE_SIZE) ? 1'b1 : 1'b0;
assign addr3_page_match = (pref_addr3 >> LOG2_PAGE_SIZE) == (addr_i >> LOG2_PAGE_SIZE) ? 1'b1 : 1'b0;

//Calculate current stride
always_comb begin
	stride = '0;
	if (arr_hit) begin
		if (cla > last_cla)
			stride = signed'(cla - last_cla);
		else
			stride = -1 * signed'(last_cla - cla);
	end
end

//Reset all trackers
function void reset();
	pref_valid1 <= 1'b0;
	pref_valid2 <= 1'b0;
	pref_valid3 <= 1'b0;
	arr_write <= 1'b0;
endfunction

//Assign the LRU tracker to the current IP
function void allocate_new_tracker();
	arr_write = 1'b1;
endfunction

//Update the current IP's tracker and potentially prefetch 3 addresses
function void update_tracker();
	pref_valid1 <= stride_match & addr1_page_match;
	pref_valid2 <= stride_match & addr2_page_match;
	pref_valid3 <= stride_match & addr3_page_match;

	arr_write = 1'b1;
endfunction

always_ff @(posedge clk) begin
	if (rst) begin
		reset();
	end 
	else if (~arr_hit) begin //new IP, so allocate tracker
		allocate_new_tracker();
	end 
	else if (stride != '0) begin
		update_tracker();
	end
end

endmodule // ip_stride
