open_hw_manager
connect_hw_server -url localhost:3121

set targets [get_hw_targets]
if { [llength $targets] == 0 } {
    puts "ERROR: No hardware targets found. Check USB connection and udev rules."
    exit 1
}
open_hw_target [lindex $targets 0]

set devices [get_hw_devices]
puts "Available devices: $devices"

set device_name "xc7a100t_0"
set current_device [get_hw_devices $device_name]
if { [llength $current_device] == 0 } {
    puts "ERROR: Device $device_name not found. Trying to find any Artix-7 device..."
    set current_device [get_hw_devices -regexp {xc7a.*}]
}
if { [llength $current_device] == 0 } {
    puts "ERROR: No compatible FPGA device found."
    exit 1
}

set target_device [lindex $current_device 0]
puts "Targeting device: $target_device"
current_hw_device $target_device
refresh_hw_device -update_hw_probes false $target_device

if { $argc > 0 } {
    set bitstream_file [lindex $argv 0]
} else {
    set bitstream_file "./vivado_project/ir_decoder.runs/impl_1/ir_decoder_top.bit"
}

set_property PROBES.FILE {} $target_device
set_property FULL_PROBES.FILE {} $target_device
set_property PROGRAM.FILE $bitstream_file $target_device
program_hw_devices $target_device
refresh_hw_device $target_device

close_hw_manager
puts "Programming Complete!"
exit
