# Projektaufteilung:
```text
IR_IN (asynchron)
   ↓
[ A ] ir_input_sync + pulse_timer
   ↓   (Pulse-Events)
[ B ] nec_decoder_fsm
   ↓   (valid data)
[ C ] output_formatter
   ↓   (bytes)
[ C ] uart_tx
   ↓
UART_TX → PC

[ D ] top_level / fpga_wrapper
```


## Modul A – IR Synchronisation & Pulse Timer

### Aufgabe
- Asynchrones IR-Signal synchronisieren
- Flanken erkennen
- Pulsdauer messen (HIGH oder LOW)
- Pulse als Event ausgeben

### Modulname
ir_pulse_timer
### Inputs
| Signal | Breite | Beschreibung |
|--------|--------|--------------|
| clk    | 1      | System Clock (z. B. 10 MHz) |
| rst_n  | 1      | Active-low Reset |
| ir_in  | 1      | IR-Signal vom TSOP (asynchron, aktiv LOW) |
### Outputs
|Signal	| Breite | Beschreibung |
|-------|-------|---------------|
|pulse_done	| 1	| 1 Takt lang HIGH, wenn Puls fertig gemessen|
|pulse_width | 16	| Pulsdauer in Clock-Zyklen |
|pulse_level	| 1	| 0 = LOW-Puls, 1 = HIGH-Puls |
|timeout | 1 | Puls zu lang (>10 ms) |

### Bedeutungsregel (wichtig!)
Wenn pulse_done == 1, dann sind
pulse_width und pulse_level gültig für genau diesen Puls.

### Verilog-Signatur
```verilog
module ir_pulse_timer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ir_in,


    output wire        pulse_done,
    output wire [15:0] pulse_width,
    output wire        pulse_level,
    output wire        timeout
);
```

## Modul B – NEC Decoder FSM

### Aufgabe
- NEC-Protokoll dekodieren
- FSM steuern
- 32 Bits empfangen
- Checksum prüfen
- Gültige Daten melden

### Modulname
nec_decoder
### Inputs
|Signal	| Breite	| Beschreibung |
|-------|-----------|--------------|
|clk	| 1	| System Clock|
|rst_n	| 1	| Active-low Reset|
|pulse_done	| 1	| Puls-Event von Modul A|
|pulse_width	|16	|Pulsdauer in Clock-Zyklen|
|pulse_level	|1	|0 = LOW, 1 = HIGH|
|timeout	| 1	| Timeout-Flag von Modul A|
### Outputs
|Signal	|Breite	|Beschreibung |
|-------|-------|-------------|
|data_valid |	1	|1 Takt HIGH bei gültigem Frame|
|decode_error	|1	|Fehler erkannt|
|address	|8	|NEC Address |
|command	|8	|NEC Command |
|receiving|	1	|FSM ist aktiv (für LED)|
### Bedeutungsregel
- data_valid ist ein Puls
- address und command sind stabil, wenn data_valid == 1
- Bei Fehler → decode_error == 1, data_valid == 0

### Verilog-Signatur
```verilog
module nec_decoder (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        pulse_done,
    input  wire [15:0] pulse_width,
    input  wire        pulse_level,
    input  wire        timeout,


    output wire        data_valid,
    output wire        decode_error,
    output wire [7:0]  address,
    output wire [7:0]  command,
    output wire        receiving
);
```
## Modul C1 – Output Formatter

## Aufgabe

- Binäre Daten → ASCII-Bytes

- Sende-Sequenz erzeugen

- UART füttern

## Modulname
output_formatter
## Inputs
|Signal	|Breite	|Beschreibung |
|-------|-------|-------------|
|clk	|1	|System Clock|
|rst_n	|1	|Reset|
|data_valid |	1	|Gültige NEC-Daten|
|address	|8	|Address|
|command	|8	|Command|
|uart_ready	|1	|UART bereit für neues Byte|
## Outputs
|Signal	|Breite	|Beschreibung|
|-------|-------|------------|
|uart_send	|1	|Puls: sende Byte|
|uart_data	|8	|ASCII-Byte|
|busy	|1	|Formatter aktiv|
## Verilog-Signatur
```verilog
module output_formatter (
    input  wire       clk,
    input  wire       rst_n,


    input  wire       data_valid,
    input  wire [7:0] address,
    input  wire [7:0] command,


    input  wire       uart_ready,


    output wire       uart_send,
    output wire [7:0] uart_data,
    output wire       busy
);
```
## Modul C2 – UART Transmitter

### Aufgabe
- UART 8N1 senden
- Baudrate erzeugen
- Byte seriell ausgeben

### Modulname
uart_tx
### Inputs
|Signal	|Breite	|Beschreibung|
|-------|-------|------------|
|clk	|1	|System Clock|
|rst_n	|1	|Reset|
|send	|1	|Sende-Impuls|
|data	|8	|Byte|
### Outputs
|Signal	|Breite	|Beschreibung|
|-------|-------|------------|
|tx	|1	|UART TX Pin|
|ready	|1	|1 = bereit|
|busy	|1	|Sendet gerade|
### Verilog-Signatur
```verilog
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       send,
    input  wire [7:0] data,


    output wire       tx,
    output wire       ready,
    output wire       busy
);
```
## Modul D – Top-Level / FPGA-Wrapper

### Aufgabe
- Module verbinden
- LEDs ansteuern
- FPGA / ASIC unterscheiden

### Modulname
ir_decoder_top
### Inputs / 📤 Outputs (Top-Level)
|Signal	|Richtung	|Beschreibung|
|-------|-----------|------------|
|clk	|In	|System Clock|
|rst_n	|In	|Reset|
|ir_in	|In	|IR-Eingang|
|uart_tx	|Out	|UART TX|
|led_valid	|Out	|gültiger Frame|
|led_error	|Out	|Fehler|
|led_active	|Out	|Empfang aktiv|
