set link_library ~/ece511/ECE511_Project/techlib/gscl45nm.db
set target_library ~/ece511/ECE511_Project/techlib/gscl45nm.db
set symbol_library ~/ece511/ECE511_Project/techlib/generic.sdb
read_file -format sverilog {rtl/bingo_prefetcher.sv}

create_clock -name "CLK" -period 2.000 -waveform { 1.000 2.000 } { clk }
set_input_delay 0.02 -clock CLK [all_inputs]
set_output_delay 0.02 -clock CLK [all_outputs]

compile -exact_map

report_power
report_area

#analyze -library WORK -format sverilog {bank.sv circular_queue.sv best_offset_prefetcher.sv}
#elaborate best_offset_prefetcher -architecture verilog -library DEFAULT
