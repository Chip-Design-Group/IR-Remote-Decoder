###############################################################################
# Created by write_sdc
###############################################################################
current_design ir_recorder_replay_chip_top
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 100.0000 [get_ports {clk}]
set_clock_transition 0.1500 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ir_in}]
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {record_req}]
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {replay_req}]
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {rst_n}]
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {slot_sel[0]}]
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {slot_sel[1]}]
set_input_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {slot_sel[2]}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {busy}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {error}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ir_tx_npn_drive}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld0}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld1}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld2}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld3}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld4}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld5}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld6}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ld7}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {rec_done}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {rep_done}]
set_output_delay 20.0000 -clock [get_clocks {clk}] -add_delay [get_ports {uart_tx}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0060 [get_ports {busy}]
set_load -pin_load 0.0060 [get_ports {error}]
set_load -pin_load 0.0060 [get_ports {ir_tx_npn_drive}]
set_load -pin_load 0.0060 [get_ports {ld0}]
set_load -pin_load 0.0060 [get_ports {ld1}]
set_load -pin_load 0.0060 [get_ports {ld2}]
set_load -pin_load 0.0060 [get_ports {ld3}]
set_load -pin_load 0.0060 [get_ports {ld4}]
set_load -pin_load 0.0060 [get_ports {ld5}]
set_load -pin_load 0.0060 [get_ports {ld6}]
set_load -pin_load 0.0060 [get_ports {ld7}]
set_load -pin_load 0.0060 [get_ports {rec_done}]
set_load -pin_load 0.0060 [get_ports {rep_done}]
set_load -pin_load 0.0060 [get_ports {uart_tx}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {clk}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {ir_in}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {record_req}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {replay_req}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {rst_n}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {slot_sel[2]}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {slot_sel[1]}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {slot_sel[0]}]
###############################################################################
# Design Rules
###############################################################################
set_max_fanout 10.0000 [current_design]
