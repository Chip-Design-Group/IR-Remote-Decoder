# Build Script for Arty A7-100T
set project_name "ir_decoder"
set part_name "xc7a100tcsg324-1"

# Create project
create_project -force $project_name ./vivado_project -part $part_name

# Add source files
add_files [glob ./src/*.sv]
add_files [glob ../EdgeDetector/src/*.sv]
add_files [glob ../PulseTimer/src/*.sv]
add_files [glob ../NECDecoder/src/*.sv]
add_files [glob ../OutputFormatter/src/*.sv]
add_files [glob ../UART_TX/src/*.sv]

# Add constraints
add_files -fileset constrs_1 ./constraints/arty_a7_100t.xdc

# Set top module
set_property top ir_decoder_top [current_fileset]

# Run Synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run Implementation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream generation complete."
