## Clock signal
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_PAD }]; #IO_L12P_T1_MRCC_35 Sch=gclk[100]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_PAD }];

## Reset (Btn0)
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { rst_n_PAD }]; #IO_L12N_T1_MRCC_16 Sch=sw[0]

## Test Button (Btn1)
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports { btn_test_PAD }]; #IO_L11P_T1_SRCC_16 Sch=btn[1]

## LEDs
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led_valid_PAD }]; #IO_L24N_T3_35 Sch=led[4]
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led_error_PAD }]; #IO_25_35 Sch=led[5]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led_active_PAD }]; #IO_L24P_T3_A01_D17_14 Sch=led[6]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led_heartbeat_PAD }]; #IO_L24N_T3_A00_D16_14 Sch=led[7]

## USB-UART Interface
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart_tx_PAD }]; #IO_L19N_T3_VREF_16 Sch=uart_txd_in

## Pmod Header JA
## IR Receiver connected to JA1 (Top row, left-most pin)
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { ir_in_PAD }]; #IO_0_15 Sch=ja[1]
set_property PULLUP true [get_ports { ir_in_PAD }];
