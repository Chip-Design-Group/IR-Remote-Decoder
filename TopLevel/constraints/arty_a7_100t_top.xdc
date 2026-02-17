## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_PAD }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_PAD }]

## Reset (SW0, active-low run switch as used in existing project)
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { rst_n_PAD }]

## Buttons
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports { btn_record_PAD }]
set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports { btn_replay_PAD }]

## LEDs (mapped to former led[4..7] pins used by existing project)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led4_PAD }]
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led5_PAD }]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led6_PAD }]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led7_PAD }]

## USB-UART interface
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart_tx_PAD }]

## PMOD JA
## IR receiver input on JA1
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { ir_in_PAD }]
set_property PULLUP true [get_ports { ir_in_PAD }]
## IR transmitter drive on JA2
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { ir_tx_PAD }]

