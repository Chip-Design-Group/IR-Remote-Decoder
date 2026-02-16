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

# Remove the wrapper which confuses Vivado top module selection
remove_files [get_files *edge_pulse_wrapper.sv]

# Disable auto-update of top module
set_property source_mgmt_mode None [current_project]

# Add constraints
add_files -fileset constrs_1 ./constraints/arty_a7_100t.xdc

# Set top module
update_compile_order -fileset sources_1
set_property top ir_decoder_top [current_fileset]
update_compile_order -fileset sources_1

# Run Synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check if synthesis succeeded
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed. Check the log file."
    exit 1
}

# Run Implementation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check if implementation succeeded
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation/Bitstream generation failed. Check the log file."
    exit 1
}

puts "Bitstream generation complete."
