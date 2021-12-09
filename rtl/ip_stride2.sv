module ip_stride2 #(parameter IP_TRACKER_COUNT = 256)
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
	output 	logic 	        pref_valid3_o
);

//Note: we hard code a prefetch degree of 3 throughout this code!

parameter ADDR_SIZE = 64;
parameter LOG2_BLOCK_SIZE = 6;
parameter LOG2_PAGE_SIZE = 12;
parameter CLA_SIZE = ADDR_SIZE - LOG2_BLOCK_SIZE;

typedef logic[ADDR_SIZE-1:0]              addr_t;
typedef logic[CLA_SIZE-1:0]               cla_t;
typedef logic signed[CLA_SIZE-1:0]        stride_t;

//trackers
addr_t ip[IP_TRACKER_COUNT];
cla_t last_cla[IP_TRACKER_COUNT];
stride_t last_stride[IP_TRACKER_COUNT];
logic lru[IP_TRACKER_COUNT];

cla_t cla;
int ip_match_idx, lru_idx;
stride_t stride;
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

//Assign intermediate values
assign cla = addr_i >> LOG2_BLOCK_SIZE;
assign stride_match = stride == last_stride[ip_match_idx] ? 1'b1 : 1'b0;
assign addr1_page_match = (pref_addr1 >> LOG2_PAGE_SIZE) == (addr_i >> LOG2_PAGE_SIZE) ? 1'b1 : 1'b0;
assign addr2_page_match = (pref_addr2 >> LOG2_PAGE_SIZE) == (addr_i >> LOG2_PAGE_SIZE) ? 1'b1 : 1'b0;
assign addr3_page_match = (pref_addr3 >> LOG2_PAGE_SIZE) == (addr_i >> LOG2_PAGE_SIZE) ? 1'b1 : 1'b0;


//Find current index of this IP
always_comb begin
	ip_match_idx = -1;
	for (int i = 0; i < IP_TRACKER_COUNT; i++) begin
		if (ip[i] == ip_i)
			ip_match_idx = i;
	end
end

//Find current LRU --> USING BIT PSEUDO-LRU
always_comb begin
	lru_idx = -1;
	for (int i = 0; i < IP_TRACKER_COUNT; i++) begin
		if (lru[i] == 1'b0) begin
			lru_idx = i;
			break;
		end
	end
end

//Calculate current stride
always_comb begin
	stride = '0;
	if (ip_match_idx != -1) begin
		if (cla > last_cla[ip_match_idx])
			stride = signed'(cla - last_cla[ip_match_idx]);
		else
			stride = -1 * signed'(last_cla[ip_match_idx] - cla);
	end
end

//Reset all trackers
function void reset();
	for (int i = 0; i < IP_TRACKER_COUNT; i++) begin
		ip[i] <= '0;
		last_cla[i] <= '0;
		last_stride[i] <= '0;
		lru[i] <= 1'b0;
	end
	pref_valid1 <= 1'b0;
	pref_valid2 <= 1'b0;
	pref_valid3 <= 1'b0;
endfunction

//Set given index as most recently used
function void set_mru(int idx);
	logic found_zero = 1'b0;
	
	lru[idx] = 1'b1;

	for (int i = 0; i < IP_TRACKER_COUNT; i++) begin
		if (lru[i] == 1'b0) begin
			found_zero = 1'b1;
			break;
		end
	end

	if (~found_zero) begin
		for (int i = 0; i < IP_TRACKER_COUNT; i++)
			lru[i] = 1'b0;
	end

	lru[idx] = 1'b1;
endfunction

//Assign the LRU tracker to the current IP
function void allocate_new_tracker();
	ip[lru_idx] <= ip_i;
	last_cla[lru_idx] <= cla;
	last_stride[lru_idx] <= '0;
	set_mru(lru_idx);	
endfunction

//Update the current IP's tracker and potentially prefetch 3 addresses
function void update_tracker();
	pref_valid1 <= stride_match & addr1_page_match;
	pref_valid2 <= stride_match & addr2_page_match;
	pref_valid3 <= stride_match & addr3_page_match;

    last_cla[ip_match_idx] <= cla;
    last_stride[ip_match_idx] <= stride;
 	set_mru(ip_match_idx);
endfunction

always_ff @(posedge clk) begin
	if (rst) begin
		reset();
	end 
	else if (ip_match_idx == -1) begin //new IP, so allocate tracker
		allocate_new_tracker();
	end 
	else if (stride != '0) begin
		update_tracker();
	end
end

endmodule // ip_stride
