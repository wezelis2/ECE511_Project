
`define SIM_VERBOSE

// Example of a parametrizable class
virtual class tbutilclass #(
  parameter IdxLen = 8
  );
  // Hash PC by taking the lowest TableIdxLen bits except last 2 bits
  static function hashIdx(input logic [31:0] addr);
    assert(IdxLen < 30);
    return addr[IdxLen+1:2];
  endfunction
endclass

`resetall
`timescale 1ns/10ps
module prefetch_bop_tb ;

// Length of the branch trace used
parameter TraceLen = 50000;

// Instantiate the design under test
// *****************************************************************************
// Clock and reset
logic clk;
logic rst;

// Instantiate interface
prefetch_interface prefetch_itf();

/*

	input 	logic 	[63:0] 	up_address_i,			// upper level cache address
	input 	logic 			up_miss_i,				// upper level cache hit / miss
	input 	logic 			up_valid_i,				// upper level cache valid 	-> ((read|write))
	input 	logic 			lo_ready_i,				// lower level cache ready to take requests
	input   logic           up_prefetched_i;        // whether line has been prefetched before
    output 	logic 	[63:0]	lo_prefetch_address_o,	// lower level cache prefetch address
	output 	logic 			lo_prefetch_valid_o,	// lower level cache prefetch valid

*/

best_offset_prefetcher bop(
  .clk_i (clk ),
  .rst_ni(rst),
  // Since we have an interface, we can normally just pass the interface
  // however, to keep the top level port naming consistent, we will match
  // the ports by name instead.

  .up_address_i             (prefetch_itf.instr   ),            // upper level cache address
  .up_miss_i                (prefetch_itf.pc      ),            // upper level cache hit / miss
  .up_valid_i               (prefetch_itf.valid   ),            // upper level cache valid 	-> ((read|write))
  .lo_ready_i               (prefetch_itf.taken   ),            // lower level cache ready to take requests
  .up_prefetched_i          (prefetch_itf.up_prefetched_i),     // whether line has been prefetched before
  .lo_prefetch_address_o    (prefetch_itf.target  ),            // lower level cache prefetch address
  .lo_prefetch_valid_o      (prefetch_itf.ex_valid)             // lower level cache prefetch valid
);
// *****************************************************************************

// Useful tasks and functions
// *****************************************************************************
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
// *****************************************************************************

// Generate clock and reset
// *****************************************************************************
initial begin
  clk = 1;
  forever #1 clk = ~clk;
end

initial begin
  reset_prefetch();
end
// *****************************************************************************

// Read branch trace
// *****************************************************************************
logic [63:0] prefetch_pc_trace    [TraceLen-1:0];
// logic [63:0] prefetch_instr_trace [TraceLen-1:0];
logic        prefetch_taken_trace [TraceLen-1:0];
logic        prefetch_pred        [TraceLen-1:0];

// Read trace to arrays
initial begin
  $readmemh("pc_trace.txt",    prefetch_pc_trace   );
//   $readmemh("br_instr_trace.txt", instr_trace);
  $readmemh("taken_trace.txt", prefetch_taken_trace);
end
// *****************************************************************************

// Feed branch trace to predictor
// *****************************************************************************
int cycle_cnt;
int trace_idx;
// int total_correct;
// int total_mispred;
// real pred_accuracy;

initial begin
  cycle_cnt = 0;
  trace_idx = 0;
//   total_correct = 0;
//   total_mispred = 0;
//   pred_accuracy = 0.0;
end

// Only feed branches every 4 cycles (assume the other 3 are regular instructions)
always @(posedge clk) begin
  // Stop simulation if we reach end of trace
  if (trace_idx < TraceLen) begin
    // Skip first 8 cycles due to reset
    if ((cycle_cnt > 7) && (cycle_cnt % 2 == 0)) begin
      prefetch_itf.up_address_i     <=  prefetch_pc_trace[trace_idx];
      prefetch_itf.up_miss_i        <=  prefetch_taken_trace[trace_idx];
      prefetch_itf.up_valid_i       <=  1'b1;
      prefetch_itf.lo_ready_i       <=  1'b1;
      prefetch_itf.up_prefetched_i  <=  1'b1;

    //   prefetch_itf.lo_prefetch_address_o <= ;
    //   prefetch_itf.lo_prefetch_valid_o <= ;


    end
    else if ((cycle_cnt > 7) && (cycle_cnt % 2 == 1)) begin
      // Get prediction
      if(prefetch_itf.lo_prefetch_valid_o) begin
        prefetch_pred[trace_idx] <= prefetch_itf.lo_prefetch_address_o;
        $displayh("[INFO] %m: Prefetcher output %p at trace index %d",prefetch_itf.lo_prefetch_address_o, trace_idx);

      end
      // Assert that branch is detected
    //   assert(bp.instr_b | bp.instr_cb)
    //   else $error("[ERROR] %m: Branch instruction not detected at trace index %d", trace_idx);
    //   Check if prediction is correct
    //   if (bp_itf.taken == br_taken_trace[trace_idx]) begin
    //     total_correct <= total_correct + 1;
    //     `ifdef SIM_VERBOSE
    //       $display("[INFO] %m: Correctly predicted branch at trace index %d", trace_idx);
    //     `endif
    //   end
    //   else begin
    //     total_mispred <= total_mispred + 1;
    //     `ifdef SIM_VERBOSE
    //       $display("[INFO] %m: Incorrectly predicted branch at trace index %d", trace_idx);
    //     `endif
    //   end
    end
    // Feed branch outcome 2 cycles later
    // else if ((cycle_cnt > 7) && (cycle_cnt % 4 == 2)) begin
    //   bp_itf.pc       <= 32'b0;
    //   bp_itf.instr    <= 32'b0;
    //   bp_itf.valid    <= 1'b0;
    //   bp_itf.ex_pc    <= br_pc_trace[trace_idx];
    //   bp_itf.ex_taken <= br_taken_trace[trace_idx];
    //   bp_itf.ex_valid <= 1'b1;
    //   // Increment trace index
    //   trace_idx = trace_idx + 1;
    // end
    // else begin
    //   bp_itf.pc       <= 32'b0;
    //   bp_itf.instr    <= 32'b0;
    //   bp_itf.valid    <= 1'b0;
    //   bp_itf.ex_pc    <= 32'b0;
    //   bp_itf.ex_taken <= 1'b0;
    //   bp_itf.ex_valid <= 1'b0;
    // end
    // Increment cycle
    cycle_cnt = cycle_cnt + 1;
  end
  else begin
    // Print final statistics
    // $display("[STAT] %m: Total correct: %0d Total mispredicted: %0d", total_correct, total_mispred);
    // $display("[STAT] %m: Prediction accuracy: %f", real'(total_correct) / real'(TraceLen));
    $display("[INFO] %m: Ending simulation");
    $stop();
  end
end
// *****************************************************************************

endmodule
