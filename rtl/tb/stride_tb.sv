// ECE511 MP2 Fall 2021
// Branch predictor testbench with example code snippets.
// Note that these are only example code for your reference, not a full testbench.
// You should write your own testbench.

//`define SIM_VERBOSE
`define TABLE_SIZE 64
`define COUNTER_SIZE 4

// Use this class as a monitor (keep track of our own bimodal predictor and compare results)
class Test_Bimodal_Predictor #(
  parameter Table_size = 256,
  parameter Counter_size = 4
  );

  parameter Idx_length = $clog2(Table_size);
  parameter int Table_max = (2 ** (Counter_size - 1)) - 1;
  parameter int Table_min = (2 ** (Counter_size - 1)) * -1;

  int predictor_table[Table_size];
  int num_errors;

  function new();
    num_errors = 0;
  endfunction

  // Helper function to get the table index from a given PC
  static function logic[Idx_length-1:0] get_table_index(logic[31:0] in);
    return in[Idx_length+1:2];
  endfunction

  // Helper function to print the table from the test
  function print_table(logic signed [Counter_size-1:0] comp_table[Table_size-1:0]);
    $display("******************************");
    $display("Printing table");
    for(int i = 0; i < $size(comp_table); i++)
      $display("%d: %b", i, comp_table[i]);
    $display("******************************");
  endfunction

  // Function to compare all bimodal table entries and report errors
  function check_tables(logic signed [Counter_size-1:0] comp_table[Table_size-1:0], int trace_idx, int cycle_cnt);
    logic found_error = 0;
    for (int idx = 0; idx < Table_size; idx++) begin
      if (predictor_table[idx] != int'(comp_table[idx])) begin
        found_error = 1;
        if (num_errors < 20) begin
          $display("[ERROR]: Wrong table entry at idx %d value at trace index %d and cycle count %d: expected %d but got %b", idx, trace_idx, cycle_cnt, predictor_table[idx], comp_table[idx]);
        end
      end
    end
    if (found_error)
      num_errors++;
  endfunction

  // Function to check the correctness of the bimodal prediction
  function predict(logic [31:0] fetch_pc, logic fetch_valid, logic comp_predict, logic signed [Counter_size-1:0] comp_table[Table_size-1:0], int trace_idx);
    logic[Idx_length-1:0] table_index = get_table_index(fetch_pc);
    logic predict_bit = predictor_table[table_index] < 0 ? 0 : 1;
    if (fetch_valid) begin
      if (comp_predict !== predict_bit) begin
        num_errors++;
        if (num_errors < 20) begin
          if (comp_predict)
            $display("[ERROR]: Wrong branch taken prediction at trace index %d", trace_idx);
          else
            $display("[ERROR]: Wrong branch not taken prediction at trace index %d", trace_idx);
          $display("Predictor table value is %b, test table value is %d", comp_table[table_index], predictor_table[table_index]);
        end
      end

      `ifdef SIM_VERBOSE
        if (comp_predict === predict_bit) begin
          $display("[INFO]: Consistent branch taken prediction at trace index %d", trace_idx);
        end
      `endif
    end
  endfunction

  // Function to update our test prediction
  function update(logic [31:0] ex_pc, logic ex_taken, logic ex_valid);
    logic[Idx_length-1:0] table_index = get_table_index(ex_pc);
    if (ex_valid) begin
      if (ex_taken && predictor_table[table_index] < Table_max)
        predictor_table[table_index]++;
      else if (~ex_taken && predictor_table[table_index] > Table_min)
        predictor_table[table_index]--;
    end
  endfunction

  // Function to print test results
  function end_test();
    if (num_errors == 0)
      $display("[INFO] Test predictor concluded monitoring with 0 errors!");
    else
      $display("[ERROR] Test predictor concluded monitoring with %d errors!", num_errors);
  endfunction

  // Function to reset test prediction
  function reset(logic signed [Counter_size-1:0] comp_table[Table_size-1:0]);
    for (int i = 0; i < Table_size; i++) begin
      predictor_table[i] = signed'('0);
      if (comp_table[i] !== '0) begin
        $display("[ERROR]: Table entry %d is not 0 after reset", i);
        num_errors++;
      end
    end
  endfunction // reset

endclass

`resetall
`timescale 1ns/10ps
module bp_bimodal_tb;

// Length of the branch trace used
parameter TraceLen = 50000;

// Instantiate the design under test
// *****************************************************************************
// Clock and reset
logic clk;
logic rst;

// Instantiate test class
Test_Bimodal_Predictor #(`TABLE_SIZE, `COUNTER_SIZE) test_predictor;

// Instantiate interface
bp_interface bp_itf();

bp_bimodal #(`TABLE_SIZE, `COUNTER_SIZE) bp (
  .clk_i (clk ),
  .rst_ni(~rst),
  // Since we have an interface, we can normally just pass the interface
  // however, to keep the top level port naming consistent, we will match
  // the ports by name instead.
  // Instruction from fetch stage
  .fetch_rdata_i         (bp_itf.instr   ),
  .fetch_pc_i            (bp_itf.pc      ),
  .fetch_valid_i         (bp_itf.valid   ),
  // Prediction for supplied instruction
  .predict_branch_taken_o(bp_itf.taken   ),
  .predict_branch_pc_o   (bp_itf.target  ),
  // Prediction outcome after execution
  // (unused in this static predictor)
  .ex_br_instr_addr_i    (bp_itf.ex_pc   ),
  .ex_br_taken_i         (bp_itf.ex_taken),
  .ex_br_valid_i         (bp_itf.ex_valid)
);
// *****************************************************************************

// Useful tasks and functions
// *****************************************************************************
task reset_bp();
  $display("[INFO] %m: Resetting branch predictor at t = %0t", $time);
  @(posedge clk) rst = 1'b1;
  `ifdef SIM_VERBOSE
    $display("[INFO] %m: Reset is asserted at t = %0t", $time);
  `endif
  @(posedge clk) rst = 1'b0;
  `ifdef SIM_VERBOSE
    $display("[INFO] %m: Reset is de-asserted at t = %0t", $time);
  `endif

  test_predictor.reset(bp.ctable);
endtask
// *****************************************************************************

// Generate clock and reset
// *****************************************************************************
initial begin
  clk = 1;
  forever #1 clk = ~clk;
end

initial begin
  test_predictor = new();
  reset_bp();
end

// *****************************************************************************

// Read branch trace
// *****************************************************************************
logic [31:0] br_pc_trace    [TraceLen-1:0];
logic [31:0] br_instr_trace [TraceLen-1:0];
logic        br_taken_trace [TraceLen-1:0];
logic        br_pred        [TraceLen-1:0];

// Read trace to arrays
initial begin
  $readmemh("../trace/br_pc_trace.txt",    br_pc_trace   );
  $readmemh("../trace/br_instr_trace.txt", br_instr_trace);
  $readmemh("../trace/br_taken_trace.txt", br_taken_trace);
end
// *****************************************************************************

// Feed branch trace to predictor
// *****************************************************************************
int cycle_cnt;
int trace_idx;
int total_correct;
int total_mispred;
real pred_accuracy;

initial begin
  cycle_cnt = 0;
  trace_idx = 0;
  total_correct = 0;
  total_mispred = 0;
  pred_accuracy = 0.0;
end

// Only feed branches every 4 cycles (assume the other 3 are regular instructions)
always @(posedge clk) begin
  // Stop simulation if we reach end of trace
  if (trace_idx < TraceLen) begin
    test_predictor.check_tables(bp.ctable, trace_idx, cycle_cnt);

    // Skip first 8 cycles due to reset
    if ((cycle_cnt > 7) && (cycle_cnt % 4 == 0)) begin
      bp_itf.pc       <= br_pc_trace[trace_idx];
      bp_itf.instr    <= br_instr_trace[trace_idx];
      bp_itf.valid    <= 1'b1;
      bp_itf.ex_pc    <= 32'b0;
      bp_itf.ex_taken <= 1'b0;
      bp_itf.ex_valid <= 1'b0;
    end
    else if ((cycle_cnt > 7) && (cycle_cnt % 4 == 1)) begin
      // Get prediction
      br_pred[trace_idx] <= bp_itf.taken;
      // Assert that branch is detected
      assert(bp.instr_b | bp.instr_cb)
      else $error("[ERROR]: Branch instruction not detected at trace index %d", trace_idx);
      // Check if prediction is correct
      if (bp_itf.taken == br_taken_trace[trace_idx]) begin
        total_correct <= total_correct + 1;
        `ifdef SIM_VERBOSE
          $display("[INFO]: Correctly predicted branch at trace index %d", trace_idx);
        `endif
      end
      else begin
        total_mispred <= total_mispred + 1;
        `ifdef SIM_VERBOSE
          $display("[INFO]: Incorrectly predicted branch at trace index %d", trace_idx);
        `endif
      end
      test_predictor.predict(br_pc_trace[trace_idx], 1'b1, bp_itf.taken, bp.ctable, trace_idx);
    end
    // Feed branch outcome 2 cycles later
    else if ((cycle_cnt > 7) && (cycle_cnt % 4 == 2)) begin
      bp_itf.pc       <= 32'b0;
      bp_itf.instr    <= 32'b0;
      bp_itf.valid    <= 1'b0;
      bp_itf.ex_pc    <= br_pc_trace[trace_idx];
      bp_itf.ex_taken <= br_taken_trace[trace_idx];
      bp_itf.ex_valid <= 1'b1;
    end
    else if ((cycle_cnt > 7) && (cycle_cnt % 4 == 3)) begin
      bp_itf.pc       <= 32'b0;
      bp_itf.instr    <= 32'b0;
      bp_itf.valid    <= 1'b0;
      bp_itf.ex_pc    <= 32'b0;
      bp_itf.ex_taken <= 1'b0;
      bp_itf.ex_valid <= 1'b0;
    
      // update would normally be delayed a cycle (only writes on pos edge clk) 
      // so put test update (which happens instantly) a cycle later
      test_predictor.update(br_pc_trace[trace_idx], br_taken_trace[trace_idx], 1'b1);
      
      // Increment trace index
      trace_idx = trace_idx + 1;
    end
    else begin
      bp_itf.pc       <= 32'b0;
      bp_itf.instr    <= 32'b0;
      bp_itf.valid    <= 1'b0;
      bp_itf.ex_pc    <= 32'b0;
      bp_itf.ex_taken <= 1'b0;
      bp_itf.ex_valid <= 1'b0;
    end
    // Increment cycle
    cycle_cnt = cycle_cnt + 1;
  end
  else begin
    test_predictor.print_table(bp.ctable);
    // Print final statistics
    test_predictor.end_test();
    $display("[STAT] %m: Total correct: %0d Total mispredicted: %0d", total_correct, total_mispred);
    $display("[STAT] %m: Prediction accuracy: %f", real'(total_correct) / real'(TraceLen));
    $display("[INFO] %m: Ending simulation");
    $stop();
  end
end
// *****************************************************************************

endmodule
