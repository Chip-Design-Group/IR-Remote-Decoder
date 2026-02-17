# Build Script for Arty A7-100T
set project_name "ir_decoder"
set part_name "xc7a100tcsg324-1"

# Create project
create_project -force $project_name ./vivado_project -part $part_name

# Add source files
add_files [glob ./src/*.sv]
add_files [glob ../../IRDecoder/EdgeDetector/src/*.sv]
add_files [glob ../../IRDecoder/PulseTimer/src/*.sv]
add_files [glob ../../IRDecoder/NECDecoder/src/*.sv]
add_files [glob ../../IRDecoder/OutputFormatter/src/*.sv]
add_files [glob ../../IRDecoder/UART_TX/src/*.sv]

# Remove the wrapper which confuses Vivado top module selection
remove_files [get_files *edge_pulse_wrapper.sv]

# Disable auto-update of top module
set_property source_mgmt_mode None [current_project]

# Add constraints
add_files -fileset constrs_1 ./constraints/arty_a7_100t.xdc

# Set top module
update_compile_order -fileset sources_1
set_property top ir_decoder_top [current_fileset]
# Default: real IR receiver input on hardware.
# Optional mock mode for bring-up:
#   DEBUG_NO_IR=1 vivado -mode batch -source build.tcl
set defines {}
if {[info exists ::env(DEBUG_NO_IR)] && $::env(DEBUG_NO_IR) eq "1"} {
    puts "INFO: Building with DEBUG_NO_IR mock generator enabled."
    lappend defines DEBUG_NO_IR
} else {
    puts "INFO: Building for real IR receiver input (DEBUG_NO_IR disabled)."
}
if {[info exists ::env(DEBUG_IR_INPUT)] && $::env(DEBUG_IR_INPUT) eq "1"} {
    puts "INFO: Building with DEBUG_IR_INPUT LED diagnostics enabled."
    lappend defines DEBUG_IR_INPUT
}
if {[info exists ::env(DEBUG_INPUT_ONLY)] && $::env(DEBUG_INPUT_ONLY) eq "1"} {
    puts "INFO: Building with DEBUG_INPUT_ONLY mode (decoder/UART held in reset)."
    lappend defines DEBUG_INPUT_ONLY
}
if {[llength $defines] > 0} {
    set_property verilog_define $defines [current_fileset]
}
update_compile_order -fileset sources_1

if {[info exists ::env(DEBUG_ILA)] && $::env(DEBUG_ILA) eq "1"} {
    puts "INFO: Building with DEBUG_ILA mode (inserting ILA in implementation)."
    set ila_hook [file normalize [file join [pwd] insert_ila_debug.tcl]]
    set_property STEPS.OPT_DESIGN.TCL.PRE $ila_hook [get_runs impl_1]
} else {
    set_property STEPS.OPT_DESIGN.TCL.PRE {} [get_runs impl_1]
}

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
