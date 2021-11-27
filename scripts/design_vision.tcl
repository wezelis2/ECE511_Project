set target_library ~/ece511/mp2/tech_lib/gscl45nm.db
set link_library ~/ece511/mp2/tech_lib/gscl45nm.db
set symbol_library ~/ece511/ECE511_Project/rtl/generic.sdb
read_file -format sverilog {bank.sv}
read_file -format sverilog {circular_queue.sv}
read_file -format sverilog {best_offset_prefetcher.sv}


analyze -library WORK -format sverilog {bank.sv circular_queue.sv best_offset_prefetcher.sv}
elaborate best_offset_prefetcher -architecture verilog -library DEFAULT