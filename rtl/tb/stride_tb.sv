//`define SIM_VERBOSE
`define IP_TRACKER_COUNT 64

`resetall
`timescale 1ns/10ps
module stride_tb;

logic clk;
logic rst;
logic pref_valid1;
logic pref_valid2;
logic pref_valid3;
logic [63:0] addr;
logic [63:0] ip;
logic [63:0] pref_addr1;
logic [63:0] pref_addr2;
logic [63:0] pref_addr3;
logic found1;
logic found2;
logic found3;
int cycle_cnt;

task reset_prefetch();
  $display("[INFO] %m: Resetting prefetcher at t = %0t", $time);
  @(posedge clk) rst = 1'b1;
  `ifdef SIM_VERBOSE
    $display("[INFO] %m: Reset is asserted at t = %0t", $time);
  `endif
  @(posedge clk) rst = 1'b0;
  `ifdef SIM_VERBOSE
    $display("[INFO] %m: Reset is de-asserted at t = %0t", $time);
  `endif
endtask

initial begin
  clk = 1;
  forever #1 clk = ~clk;
end

initial begin
  reset_prefetch();
end

ip_stride #(`IP_TRACKER_COUNT) dut (
  .clk(clk),
  .rst(rst),
  .addr_i(addr),
  .ip_i(ip),
  .pref_addr1_o(pref_addr1),
  .pref_valid1_o(pref_valid1),
  .pref_addr2_o(pref_addr2),
  .pref_valid2_o(pref_valid2),
  .pref_addr3_o(pref_addr3),
  .pref_valid3_o(pref_valid3)
);

initial begin
  addr = '0;
  ip = '0;
  cycle_cnt = 0;
  found1 = 1'b0;
  found2 = 1'b0;
  found3 = 1'b0;
end

always @(posedge clk) begin
  if (cycle_cnt == 10000) begin
    if (found1 & found2 & found3)
      $display("SUCCESS: FOUND ALL");
    else
      $display("ERROR: f1 %b / f2 %b / f3 %b", found1, found2, found3);
    $finish;
  end

  if (cycle_cnt < 20) begin
    if (pref_valid1)
      $display("Cycle %d: Prefetched (slot 1) addr %u", cycle_cnt, pref_addr1);
    if (pref_valid2)
      $display("Cycle %d: Prefetched (slot 2) addr %u", cycle_cnt, pref_addr2);
    if (pref_valid3)
      $display("Cycle %d: Prefetched (slot 3) addr %u", cycle_cnt, pref_addr3);
  end

  if (pref_valid1)
    found1 = 1'b1;
  if (pref_valid2)
    found2 = 1'b1;
  if (pref_valid3)
    found3 = 1'b1;

  addr = addr + 57;
  ip <= cycle_cnt % 10;
  cycle_cnt = cycle_count + 1;
end

endmodule
