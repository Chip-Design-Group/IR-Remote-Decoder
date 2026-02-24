#import "@preview/ilm:1.4.1": *

#show: ilm.with(
  title: [IR Remote Decoder],
  author: "Unglert Maik, Sauerwein Alexander, Mittermeier Lukas, Szentmiklosy Katalin",
  date: datetime(year: 2026, month: 02, day: 24),
  abstract: [
    This document describes the design and implementation during the
    development of an Infrared remote control decoder with ESP32-C3
    Wi-Fi control with replay and record functionality. The system was developed as part of the MY_CHIP course at the
    University of Applied Sciences Munich, supervised by Prof. Stefan Wallentowitz.
    It covers the full hardware–software co-design from IR signal decoding.
    This documentation was written to capture not only the final design decisions but also the 
    problems encountered along the way and how they were resolved.
  ],
  bibliography: none,
  figure-index: (enabled: true),
  table-index: (enabled: true),
  listing-index: (enabled: true),
)

= Introduction

Infrared remote control systems are ubiquitous in consumer
electronics. The NEC protocol encodes 32-bit frames — an 8-bit address, its logical
inverse, an 8-bit command, and its inverse — using pulse-distance modulation at a
38 kHz carrier frequency.

The goal of this project was to build a complete, self-contained system that can:

+ *Decode* arbitrary NEC IR signals in real-time hardware,
+ *Store* up to 40 captured commands in named slots,
+ *Replay* any stored command wirelessly via a web browser.

The system consists of two main components: an FPGA running a pipelined VHDL decoder,
and an ESP32-C3 microcontroller exposing a Wi-Fi web interface.

= System Architecture

== Overview

The two subsystems communicate over a custom 2-pin serial interface (DATA + CLK).

#figure(
  table(
    columns: (1fr, 1fr),
    table.header([*FPGA Subsystem*], [*ESP32-C3 Subsystem*]),
    [NEC IR signal decoding], [Wi-Fi SoftAP (SSID: _IR-Remote_)],
    [BRAM slot storage],      [HTTP server at `192.168.4.1`],
    [UART debug output],      [Slot record / replay / rename UI],
    [Serial frame receiver],  [Serial frame transmitter],
  ),
  caption: [Subsystem responsibilities],
)

== ESP32–FPGA Serial Protocol

A 12-bit frame is transmitted MSB-first over two bit-banged GPIO lines at 500 Baud
(2 ms per half-period). The FPGA samples DATA on the rising CLK edge.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*Bits*], [*Field*], [*Description*]),
    [11:6], [Slot address], [6-bit index — `[5:4]` = remote ID, `[3:0]` = slot number],
    [5:3],  [Command],      [`001` = PLAY, `010` = REC],
    [2:0],  [Magic],        [`101` — discards malformed frames on FPGA side],
  ),
  caption: [12-bit serial frame layout],
) <tab-frame>

=== Challenge: Noise on the serial line

During initial testing, the FPGA occasionally received corrupted frames due to GPIO
noise on the breadboard prototype.

*Solution:* The 3-bit magic field (`101`) was introduced as a lightweight frame
validator. Frames not matching the magic value are silently discarded by the FPGA.
Additionally, CLK and DATA lines were pulled low by default (idle state) to avoid
floating inputs triggering false frames.

= FPGA Design

== EdgeDetector

Monitors the demodulated IR receiver output and produces single-cycle strobe pulses
on rising and falling edges, providing the timing reference for `PulseTimer`.

=== Challenge: Glitches from the IR demodulator

The TSOP-series demodulator occasionally produces sub-microsecond glitches that
triggered false edge detections.

*Solution:* A 2-stage synchronizer followed by a simple debounce counter (3 clock
cycles) was added before the edge detection logic, eliminating spurious pulses without
affecting timing accuracy.

== PulseTimer

Measures the duration of each IR pulse in clock cycles and outputs the width together
with a polarity flag to the `NECDecoder`.

=== Challenge: Counter overflow on missing stop bit

If no falling edge arrives after the final NEC data bit (missing stop bit), the
counter would overflow and corrupt the next frame's timing.

*Solution:* A configurable timeout was added. If the counter exceeds the maximum
expected NEC pulse width (~70 ms), it resets and signals a timeout to the decoder FSM,
which returns to its idle state.

== NECDecoder

Implements the NEC decoding FSM covering the full frame structure:

- *Leader:* 9 ms burst + 4.5 ms space (or 2.25 ms for repeat codes)
- *Data:* 32 bits, pulse-distance encoded (`562 µs` burst + `562 µs` = 0, `1687 µs` = 1)
- *Verification:* address vs. inverted address, command vs. inverted command

=== Challenge: Tolerance margins for different remotes

Different IR remotes exhibit timing deviations of up to ±15% from the NEC standard,
causing valid frames to be rejected.

*Solution:* All timing comparisons use ±20% tolerance windows instead of exact matches.
The tolerance values are defined as constants, making them easy to tune per remote brand.

=== Challenge: Repeat codes causing double-triggers

NEC repeat codes (sent while a button is held) were being interpreted as new commands,
causing unintended slot activations.

*Solution:* A `repeat` output flag was added. The top-level logic filters repeat codes
and only forwards the initial frame to the slot controller.

== OutputFormatter

Serializes decoded NEC frames (address + command) into ASCII for UART transmission,
enabling host-side logging and testbench verification.

== UART_TX

Standard 8N1 UART transmitter with a `busy` handshake signal. Used for debug output
to a host PC during development.

=== Challenge: UART timing mismatch at higher baud rates

At 115200 Baud with a 12 MHz oscillator, the baud rate divisor was not an integer,
causing framing errors.

*Solution:* The FPGA clock was switched to 100 MHz (PLL-derived), giving an exact
integer divisor for all standard baud rates.

= My Contribution (Sauerwein Alexander)

Bringing up the
physical hardware prototype on the Arty A7-35T FPGA board, designing the IR receiver
and transmitter circuits with component selection, implementing the ESP32–FPGA serial
protocol, and building the Wi-Fi web interface.

== FPGA Hardware Bring-Up (Arty A7-35T)

The implementation was verified on a Digilent Arty A7-35T board carrying a Xilinx
Artix-7 XC7A35T FPGA. The board provides a 100 MHz system oscillator.

The FPGA I/O pins were mapped as follows:

#figure(
  table(
    columns: (auto, auto),
    table.header([*Pin*], [*Function*]),
    [`JA1`], [IR receiver output (`ir_in_PAD`)],
    [`JA2`], [IR transmitter control (`ir_tx_PAD`)],
    [`JA3`], [ESP32 clock (`clk_esp32_PAD`)],
    [`JA4`], [ESP32 data (`data_esp32_PAD`)],
    [`JA5`], [Ground (GND)],
  ),
  caption: [FPGA I/O pin assignments on the Arty A7-35T],
)

Status LEDs were mapped to the four on-board RGB LEDs and used during bring-up to
verify subsystem health without an oscilloscope:

#figure(
  table(
    columns: (auto, auto),
    table.header([*LED*], [*Meaning*]),
    [`LD7`], [Heartbeat — blinks at ≈ 0.8 s to confirm clock and reset are healthy],
    [`LD6`], [IR receiving — on while `ir_in` is active (demodulator output low)],
    [`LD4`], [Decode OK — 200 ms pulse after a valid NEC frame is decoded],
    [`LD5`], [Record active — fast blink (≈ 100 ms) while a slot is being recorded],
  ),
  caption: [Debug LED assignments on the Arty A7-35T],
)

== IR Receiver Circuit

The IR receiver requires a supply voltage of *5 V*
to operate correctly. The Arty A7-35T board, however, only provides a *3.3 V* rail,
and its I/O pins must not see more than * < 3.4 V* on any input. Two problems therefore
had to be solved:

+ *Boost the supply* from 3.3 V to 5 V for the Receiver power pin.
+ *Level-shift the output* of the TSOP (which swings between 0 V and $V_"CC"$ = 5 V)
  down to a safe 3.3 V logic level before connecting it to the FPGA.

Both issues are addressed by the circuit shown below.

=== Schematic

#figure(
  image("IR-Receiver.pdf", width: 90%),
  caption: [IR receiver circuit — 5 V with a 5 V power supply and output voltage divider],
) <fig-ir-rx>

=== Supply network

The power supply provides $V_"CC" = 5 "V"$ DC.

=== Output level-shift (voltage divider)

The TSOP output swings from 0 V (active) to $V_"CC" = 5 "V"$ (idle).
A resistive voltage divider scales this to a safe level for the 3.3 V FPGA input
($V_"in,max" = 3.4 "V"$).

Choose $R_1 = 1 "k"Omega$ (top) and $R_2 = 2 "k"Omega$ (bottom, to GND):

$
V_"out" = V_"CC,supply" times frac(R_2, R_1 + R_2)
        = 5 "V" times frac(1 "k" Omega, 1 "k" Omega + 2 "k" Omega)
        approx 3.33 "V" < 3.4 "V" space checkmark
$

== IR Transmitter Circuit

The Arty A7-35T only provides a *3.3 V* supply rail, and the FPGA control pin
`ir_tx_PAD` drives at 3.3 V logic levels. Because the IR LED requires
more current than the FPGA GPIO can safely source (max. 12 mA per pin), an *NPN
transistor* (e.g. 2N2222) is used as a low-side switch between the LED
and GND. The FPGA drives only the base current; the full LED current flows through
the collector. The entire circuit is supplied at 5V, as we use the same 5 V supply as the receiver. This allows the IR LED to achieve the necessary forward voltage and current for proper transmission while keeping all node voltages within the board's safe operating range.

=== Schematic

#figure(
  image("IR-Transmitter.pdf", width: 90%),
  caption: [IR transmitter circuit — NPN low-side switch driving 950 nm IR LED at 38 kHz],
) <fig-ir-tx>

=== Design targets

- IR LED forward voltage: $V_F approx 1.2 "V"$ 
- LED current: $I_"f,LED" = 20 "mA"$
- Supply: $V_"CC" = 5 "V"$ 
- NPN saturation voltage: $V_"CE,sat" approx 0.2 "V"$
- NPN current gain: $h_"FE,min" = 100$ (conservative for 2N2222)
- FPGA GPIO output: 3.3 V, max. 12 mA drive capability

=== Led resistor $R_3$
To set the LED current to 20 mA in saturation:
$
R_3 = frac(V_"CC" - V_F - V_"CE,sat", I_"f,LED")
    = frac(5 V - 1.2 V, 0.02 A)
    = frac(3.8 V, 0.02 A)
    = 190 space "Omega"
    -> "use" 220 space "Omega" " (E12 series)"
$


=== Base resistor $R_4$

To saturate the transistor ($I_B >= I_"LED" / h_"FE"$) while keeping the FPGA GPIO
current within its 12 mA limit:

$
I_"B,needed" = frac(I_"LED", h_"FE,min") = frac(100 "mA", 100) = 1 "mA"
$

$
R_B = frac(V_"GPIO" - V_"BE", I_B)
    = frac(3.3 V - 0.6 V , 1 "mA")
    = frac(2.7 V, 1 "mA")
    = 2.7 space "kOmega"
    -> "use" 3 space "kOmega"
$

Resulting FPGA GPIO current:

$
I_"GPIO" = frac(3.3 V - 0.6 V, 3 "kOmega") approx 1 "mA" < 12 "mA" space checkmark
$


== ESP32–FPGA Serial Protocol Design

=== Motivation

The ESP32-C3 needed a simple, robust way to command the FPGA to replay or record an
IR slot. SPI hardware was available on both sides, but wiring the full SPI bus
(MOSI, MISO, SCK, CS) across a jumper connection on a prototype board introduced
noise issues. A 2-wire bit-banged solution (DATA + CLK) was chosen for simplicity.

=== Frame format

A 12-bit frame is transmitted MSB-first at 500 Baud (2 ms per bit half-period), idle
LOW. See @tab-frame for the field breakdown.

The *3-bit magic field* (`101`) was deliberately included to discard malformed or
partially-received frames — even a single glitch bit that shifts the frame by one
position cannot produce a coincidental magic match in the command and magic fields
simultaneously.

=== FPGA-side receiver (`esp32_spi_receiver.sv`)

The receiver was implemented as a standalone synchronous module:

+ *2-FF synchronizer* — CLK and DATA lines are double-registered to cross from the
  asynchronous ESP32-C3 clock domain into the FPGA's 10 MHz clock domain.
+ *Rising-edge detector* — a one-cycle pulse `clk_rise` is generated on each rising
  edge of the synchronized CLK, gating the shift register.
+ *Idle timeout* — if CLK remains LOW for more than 3 ms (30 000 cycles at 10 MHz)
  the bit counter resets, re-synchronising the receiver after a partial or corrupted
  frame without requiring a hard reset.
+ *12-bit shift register* — bits are shifted in MSB-first on `clk_rise`; a `frame_done`
  pulse fires one cycle after the 12th bit arrives.
+ *Magic check and decode* — `frame_done` triggers a combinational check of bits
  `[2:0]`; if the magic matches, `slot_addr`, `replay_req` or `record_req` are
  asserted for exactly one clock cycle.

=== ESP32-C3 firmware side

The `fpga_send_frame(slot, cmd)` function in `wifi_button.c` bit-bangs the 12-bit
frame:

```c
// Build the frame word
uint16_t frame = ((slot & 0x3F) << 6) | ((cmd & 0x7) << 3) | MAGIC;

// Clock out 12 bits, MSB first
for (int i = 11; i >= 0; i--) {
    gpio_set_level(GPIO_DATA, (frame >> i) & 1);
    vTaskDelay(pdMS_TO_TICKS(1));   // half-period: 1 ms
    gpio_set_level(GPIO_CLK, 1);
    vTaskDelay(pdMS_TO_TICKS(1));
    gpio_set_level(GPIO_CLK, 0);
}
// Return lines to idle
gpio_set_level(GPIO_DATA, 0);
```

The `vTaskDelay(1 ms)` half-period gives 500 Baud — well within the FPGA synchronizer
margin (10 MHz core clock, 20 synchronizer cycles per bit).

== Wi-Fi Web Interface

=== Architecture

The ESP32-C3 firmware runs under FreeRTOS with ESP-IDF v5.x. After Wi-Fi AP
initialization it starts an `esp_http_server` instance with wildcard URI matching.
Dynamic HTML is built in RAM buffers using `snprintf` and sent in a single chunk.

=== HTTP API

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*Method*], [*URI*], [*Action*]),
    [`GET`],  [`/`],           [Home — overview of all 4 remotes],
    [`GET`],  [`/remote/N`],   [Detail page for remote _N_ (0–3)],
    [`GET`],  [`/replay/S`],   [Send PLAY frame for slot _S_ to FPGA],
    [`GET`],  [`/record/S`],   [Send REC frame for slot _S_ to FPGA],
    [`POST`], [`/rename/S`],   [Store a name for slot _S_ (plain-text body)],
  ),
  caption: [HTTP API endpoints],
) <tab-api>

=== Slot Management

Slots use a flat 6-bit address (`[5:4]` = remote ID 0–3, `[3:0]` = slot 0–9).
State is held in RAM:

- `recorded_slots` — 64-bit bitmask, bit _N_ set if slot _N_ has been recorded
- `slot_names[40][24]` — per-slot user-defined name (max. 23 characters)

=== Challenge: HTML buffer truncation on the last remote card

The dynamically-built HTML response for the home page was being silently truncated,
cutting off the last remote card in the browser.

*Solution:* The root cause was a `size_t` underflow bug: `snprintf` returns the
_desired_ output length even when the buffer is full, causing `buf_size - pos` to
wrap around to a huge value. The buffer was increased to 16 KB and all `snprintf`
calls were replaced with a safe macro that clamps `pos` to `buf_size` before writing.

=== Challenge: Slot names not surviving page navigation

Slot names entered by the user were lost when navigating back to the remote page
because the HTML was regenerated from the in-memory array, which was populated
correctly — but the input field `value` attribute was not being set.

*Solution:* The `build_remote_html()` function was updated to pass the stored
`slot_names[slot]` as the `value` attribute of each name input field. Additionally,
the `doRename()` JavaScript function now updates the `<h3>` heading live after a
successful save, providing immediate visual feedback without a page reload.

= System Parameters

#figure(
  table(
    columns: (auto, auto),
    table.header([*Parameter*], [*Value*]),
    [IR carrier frequency],     [38 kHz (demodulated by TSOP receiver)],
    [FPGA clock],               [100 MHz (Artix-7 PLL)],
    [NEC leader burst],         [9 ms ± 20%],
    [NEC data bit '1'],         [2.25 ms pulse distance],
    [NEC data bit '0'],         [1.125 ms pulse distance],
    [Serial baud rate],         [500 Baud (2 ms half-period)],
    [Max. slots],               [40 (4 remotes × 10 slots)],
    [Slot name max. length],    [23 characters],
    [Wi-Fi SSID],               [IR-Remote],
    [Web interface URL],        [`http://192.168.4.1`],
    [HTML buffer (home)],       [16 KB],
    [HTML buffer (remote)],     [24 KB],
  ),
  caption: [System parameters],
) <tab-params>

= Building & Flashing

== FPGA

```bash
# Simulate a single module
make -C IRDecoder/NECDecoder sim

# Synthesize and program the Arty A7
make -C IRDecoder/NECDecoder synth
make -C TopLevel program
```

== ESP32-C3 Firmware

```bash
cd wifi_button
idf.py set-target esp32c3
idf.py build
idf.py flash monitor
```

= Conclusion & Outlook

The project successfully demonstrates a complete IR remote decoder with wireless replay
capability. The modular VHDL design proved easy to test independently with cocotb
testbenches, and the ESP32-C3 web interface requires no app installation on the
client device.

Key lessons learned:

- *Timing tolerances* must be generous when targeting compatibility with multiple
  remote brands — a ±20% window works well in practice.
- *Buffer management* in embedded HTTP servers requires careful accounting; silent
  truncation from `snprintf` overflow is easy to miss without end-to-end testing.
- *Hardware/software interface design* (the 12-bit frame protocol) benefits from a
  validation field (magic bits) even in simple point-to-point links.

*Future work* includes persistent slot storage via NVS flash, support for additional
IR protocols (RC5, Sony SIRC), and OTA firmware updates for the ESP32.
