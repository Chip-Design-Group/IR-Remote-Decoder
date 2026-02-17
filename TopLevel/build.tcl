# Build script for Arty A7-100T (root TopLevel integration)
set project_name "ir_recorder_replay_top"
set part_name "xc7a100tcsg324-1"

create_project -force $project_name ./vivado_project -part $part_name

# Add source files
add_files [glob ./src/*.sv]
add_files [glob ../IRDecoder/EdgeDetector/src/*.sv]
add_files [glob ../IRDecoder/PulseTimer/src/*.sv]
add_files [glob ../IRDecoder/NECDecoder/src/*.sv]
add_files [glob ../IRDecoder/OutputFormatter/src/*.sv]
add_files [glob ../IRDecoder/UART_TX/src/*.sv]
add_files [glob ../IRRecorder_Replay/Types_PKG/src/*.sv]
add_files [glob ../IRRecorder_Replay/Recorder/src/*.sv]
add_files [glob ../IRRecorder_Replay/STORAGE_BRAM/src/*.sv]
add_files [glob ../IRRecorder_Replay/Replay_FSM/src/*.sv]
add_files [glob ../IRRecorder_Replay/nec_encoder/src/*.sv]
add_files [glob ../IRRecorder_Replay/TX/src/*.sv]

set_property source_mgmt_mode None [current_project]

# Constraints
add_files -fileset constrs_1 ./constraints/arty_a7_100t_top.xdc

# Top module
update_compile_order -fileset sources_1
set_property top ir_recorder_replay_arty_top [current_fileset]
update_compile_order -fileset sources_1

# Synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "ERROR: Synthesis failed."
  exit 1
}

# Implementation + bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "ERROR: Implementation/bitstream failed."
  exit 1
}

puts "Bitstream generation complete."

