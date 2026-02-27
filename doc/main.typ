#import "@preview/ilm:1.4.1": *
#import "@preview/cetz:0.3.4": canvas, draw

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
  bibliography: bibliography("references.bib"),
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

= FPGA Design

== EdgeDetector (Lukas Mittermeier)

The EdgeDetector is the first timing-critical stage in the receive path: it converts the asynchronous demodulator output into clock-domain-safe edge strobes and therefore defines the timing reference for `PulseTimer`. In implementation, the main challenge was not edge detection itself but making sure that asynchronous input behavior does not create unstable or ambiguous events in downstream logic. A 2-stage synchronizer was introduced as the baseline mechanism to reduce metastability risk and to provide a clean sampled signal (`ir_in_sync`) before any edge decision is made.

During integration, we observed that many apparent "edge detector bugs" were in fact caused by expectation mismatches between asynchronous signal behavior and synchronous sampling. Inputs that toggle close to a clock edge can be observed one or more cycles later, depending on the synchronizer pipeline state. This is correct hardware behavior, but it can look non-deterministic in early tests if latency assumptions are implicit. We therefore aligned module and test expectations around one explicit rule: edge pulses are generated from the synchronized signal only, and each detected transition is represented by a single-cycle `edge_rise` or `edge_fall` strobe. This eliminated interpretation conflicts between simulation traces and decoder timing assumptions and directly clarified how short disturbances should be treated.

Based on this rule set, noise and very short glitches were evaluated as an integration risk. A dedicated multi-sample glitch filter was discussed early, but for the current revision it was intentionally deferred to avoid distorting narrow timing boundaries and to keep the stage minimal. Instead, robustness was achieved through strict synchronizer-based edge generation plus verification scenarios that inject mid-cycle toggles and short disturbances. This approach kept edge strobes deterministic in the clock domain and provided a stable interface contract for subsequent decoder stages, while leaving room for a future optional debounce/filter block if field measurements justify it.

On the verification side, cocotb scheduling details were a relevant lesson learned. Driving DUT inputs in the wrong simulator phase can produce failures that resemble RTL defects although the root cause is testbench timing. We therefore separated sampling and driving phases (`ReadOnly` vs. `ReadWrite`) and added explicit mid-cycle stimulus to emulate asynchronous input transitions realistically. With this setup, edge pulse width, polarity, and mutual exclusivity (`edge_rise` and `edge_fall` never high simultaneously) could be validated reliably across normal transitions and glitch-like stimuli.

== PulseTimer (Lukas Mittermeier)

The PulseTimer measures each high and low phase of the demodulated IR signal in clock cycles and forwards `pulse_width`, `pulse_level`, and `pulse_done` to the decoder stage. During early implementation, the counter size was intentionally tailored to the initial NEC-focused scope and set to 16 bits, because this matched the expected first integration targets and kept the module compact. During system integration, however, the main issue was not a broken counter but an inconsistent pulse-width definition between RTL and testbench, which caused off-by-one behavior at timing thresholds. The implementation was aligned to one shared rule (count full clock cycles between two edges), and decoder limits were adjusted to the same convention so borderline NEC pulses were classified consistently.

As the architecture moved beyond a strict NEC-only path toward multi-protocol support, the timing envelope widened and the original 16-bit assumption became too tight for robust operation under all scenarios. Longer protocol phases, larger tolerance windows, and recovery/timeout paths increased the practical maximum pulse length that had to be represented without ambiguity. To avoid overflow risk and preserve a single timing infrastructure across protocols, the PulseTimer counter was expanded to 18 bits. This change removed corner-case truncation effects, stabilized classification at long pulse boundaries, and reduced integration friction between protocol-specific decoder stages.

Robustness was improved by adding a timeout path for missing trailing edges, preventing stale measurements from propagating into the next frame. If no valid edge arrives within the configured maximum pulse window, the module emits a timeout condition and returns cleanly to idle, allowing the decoder FSM to recover deterministically. On verification level, cocotb stimulus timing was also cleaned up to avoid simulation-phase artifacts, and long timeout checks were separated from fast regressions to keep daily test cycles practical while still covering the recovery path.

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

The OutputFormatter converts decoded frame data into a UART-friendly ASCII stream and acts as the main debugging bridge between RTL behavior and terminal output. Instead of exposing raw internal buses, the module emits compact human-readable lines such as protocol label, address, and command. This significantly reduced debugging time during integration, because protocol recognition errors and payload mismatches became visible immediately without waveform inspection.

A central design challenge was that one fixed text format was not sufficient once multi-protocol support was added. NEC-style protocols fit into a short `A:xx C:yy` representation, while Samsung variants require extended fields and different frame lengths. The final implementation therefore uses protocol-dependent formatting with dynamic output length, including dedicated paths for SAM32 and SAM36. Table <tab-output-formatter-formats> summarizes the resulting UART line formats and their byte lengths. This avoided lossy presentation of decoded information and kept the UART output aligned with the semantic structure used in decoder and replay paths.

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([*Protocol*], [*UART output pattern*], [*Length*]),
    [`NEC / ONKYO / APPLE / N8X2`], [`P:XXXXXXXX A:aa C:cc\n`], [`21 bytes`],
    [`SAM32`], [`P:SAM32   A:aaaa C:cccc\n`], [`25 bytes`],
    [`SAM36`], [`P:SAM36    A:aaaa ID:x C:cc\n`], [`28 bytes`],
  ),
  caption: [OutputFormatter protocol-dependent UART formats],
) <tab-output-formatter-formats>

Handshake robustness with the UART transmitter was another important topic. The formatter cannot assume that the transmitter is always ready, so byte emission is controlled by an explicit FSM (`IDLE`, `SEND`, `WAIT_ACK`, `WAIT_UART`) and only advances when `uart_ready` is asserted. During development, this prevented dropped or duplicated characters when backpressure occurred, especially in scenarios where multiple frames arrived close together. Buffering decoded inputs at frame start further ensured that a running output line remains stable even if new decoder values appear in parallel. The corresponding state flow is shown in Fig. <fig-output-formatter-fsm>.

#figure(
  image("OutputFormatterFSM.png", width: 55%),
  caption: [OutputFormatter UART handshake FSM],
) <fig-output-formatter-fsm>

Verification was intentionally broad: directed tests covered protocol labels, field extraction, and UART handshake behavior, while a full 256×256 address/command sweep was also evaluated. That exhaustive run was useful once as a confidence check, but in practice it turned out to be too slow for daily development iterations. The team therefore treated it as an occasional deep-regression test and relied on faster focused tests for normal workflow, which gave much quicker feedback while still preserving confidence in formatting correctness.

== UART_TX (Katalin Szentmiklosy)

The UART transmitter serializes 8-bit data into standard 8N1 frames (start bit, 8 data bits LSB-first, stop bit) for debug output to a host PC. The module implements a four-state FSM (IDLE, START, DATA, STOP) with a configurable `CLOCKS_PER_BIT` parameter to set the baud rate. Initially, a simplified version without baud interval timing was developed to verify the basic state transitions and bit serialization logic. The final implementation adds a `baud_cnt` counter that holds each bit for exactly one bit period, ensuring correct UART timing. In the IDLE state, `tx_out` remains high and `ready` is asserted. When `send_req` is triggered, `data_in` is latched into an internal shift register, and the FSM transitions through START, DATA (shifting out 8 bits via `bit_idx`), and STOP states, each waiting for the configured baud interval before advancing.

 

//#figure(

 // image("../IRDecoder/UART_TX/uart_tx.png", width: 80%),

 // caption: [UART TX state machine — 8N1 transmission with baud interval timing],

//) <fig-uart-tx-fsm>

== Interface Contract (Katalin Szentmiklosy)

Before implementation, a versioned interface contract (`ir_types_pkg.sv`) was established defining a 67-bit storage word (`ir_word_t`) that packs frame data (48 bits), frame length (6 bits), protocol ID (5 bits), and flags (8 bits). Fixed bit positions (`IR_FLAGS_LSB/MSB`, `IR_PROTOCOL_ID_LSB/MSB`, etc.) enable transparent debugging, while helper functions (`ir_pack_word`, `ir_unpack_word`) ensure consistent encoding across RTL and testbenches. The 6-bit slot address supports 40 slots (4 remotes × 10 buttons), with bits [5:4] encoding remote ID and [3:0] button number. Flag bits define slot validity (`IR_FLAG_VALID_BIT`) and repeat mode (`IR_FLAG_REPEAT_BIT`), with reserved bits for future extensions. This contract eliminated bit-slicing errors between recorder, storage, and replay modules during parallel development.

== Recorder (Katalin Szentmiklosy)

The recorder implements a five-state FSM (IDLE, WAIT_VALID, WRITE, DONE, ERROR) that accepts decoded NEC payloads and writes them to storage BRAM. When `record_req` is asserted, the module latches `target_slot` and waits for `dec_valid`. Initially, a simplified version without timeout handling was developed to verify basic state transitions and payload packing. The final implementation adds a configurable `WAIT_TIMEOUT_CYCLES` parameter (default 256): if no valid frame arrives, the FSM transitions to ERROR and pulses the error flag for one cycle. On success, `ir_pack_word()` serializes the payload into `ir_word_t` format, triggering a single-cycle `mem_wr_en` pulse. The `busy` signal remains high during WAIT_VALID and WRITE to prevent concurrent requests.

 

//#figure(

 // image("../IRRecorder_Replay/Recorder/ir_recorder.png", width: 90%),

  //caption: [IR Recorder FSM — timeout handling and back-to-back request support],

//) <fig-ir-recorder-fsm>

Early implementations required manual timeout counter resets when `record_req` was deasserted mid-wait, leaving stale error flags. Additionally, the FSM forced an extra idle cycle between consecutive requests, reducing throughput. The final design resets `wait_cnt_q` automatically when `record_req` drops, and both DONE and ERROR states accept immediate `record_req` re-assertion, transitioning directly to WAIT_VALID or WRITE without idle cycles. This allows seamless retry workflows where users can re-trigger recording after a timeout without manual state clearing.

== Storage BRAM (Katalin Szentmiklosy)
The storage module infers block RAM (`(* ram_style = "block" *)`) with separate synchronous read and write controls on a shared clock (`wr_en`, `rd_en`). Write operations update the target slot synchronously when `wr_en` is asserted. Read operations pulse `rd_valid` for exactly one cycle when `rd_en` is high, outputting data from `rd_addr`. BRAM content persists across resets; only the read interface state (`rd_data`, `rd_valid`) is cleared to prevent stale outputs.

 

//#figure(

 // image("../IRRecorder_Replay/STORAGE_BRAM/ir_storage_bram.png", width: 75%),

 // caption: [Storage BRAM operation flow — single-cycle read/write with persistent storage],

//) <fig-ir-storage-bram>

Initially, `rd_valid` remained asserted for multiple cycles when `rd_en` was held high, violating the single-cycle pulse contract defined in `ir_types_pkg`. The final implementation explicitly deasserts `rd_valid` at the start of each clock cycle and only reasserts it when `rd_en` is sampled, ensuring strict single-cycle pulse behavior regardless of input hold time. This matches the handshake protocol expected by downstream modules (e.g., IR player) and prevents spurious read acknowledgments.

== IRReplayFSM (Lukas Mittermeier)

The IRReplayFSM coordinates the replay path from a user replay request to a valid encoder start pulse. Instead of trying to trigger the encoder immediately, the state machine was designed as a strict handshake pipeline: first latch the requested slot, then issue a one-cycle memory read request, wait for `mem_rd_valid`, decode and validate the stored word, wait until both encoder and transmitter are ready, and only then emit a single-cycle `enc_start`. This stepwise approach was chosen early to avoid race conditions between storage, protocol decoding, and transmitter availability.

The implemented state sequence is shown in Fig. <fig-ir-replay-fsm> and reflects the exact handshake order used in RTL (`READ_REQ` -> `READ_WAIT` -> `DECODE_WORD` -> `WAIT_ENCODER` -> `START_ENCODE` -> `DONE/ERROR`).

#figure(
  image("IRReplayFSM.png", width: 65%),
  caption: [IR Replay FSM state machine],
) <fig-ir-replay-fsm>

During development, one recurring problem was that apparently valid replay requests still produced incorrect output frames. The root cause was not in the state transitions themselves, but in protocol-specific payload interpretation. For Samsung36, the semantic storage layout and the encoder bit-consumption order were not identical, so replayed bits were sent in the wrong sequence even though the slot read and handshake path worked correctly. The solution was to insert a protocol-specific remapping step directly in the replay FSM after unpacking the stored word and before entering the encoder wait state. This kept protocol adaptation localized in one module and prevented protocol quirks from leaking into generic storage or encoder control logic.

Another important design decision was explicit backpressure handling. In early integration attempts, replay control can look functionally correct as long as the encoder is always ready in simulation, but this assumption does not hold in full-system operation. The final FSM therefore remains in `ST_WAIT_ENCODER` until both `enc_ready` and `tx_ready` are asserted, guaranteeing that `enc_start` is never issued speculatively. This removed intermittent replay failures under load and made behavior deterministic when replay requests coincided with ongoing transmissions.

Error handling was also made explicit instead of implicit. After reading and unpacking the stored slot word, the FSM checks the validity flag before starting transmission. Invalid or empty slots are routed to a dedicated error path that raises `error` and returns cleanly to idle. Valid words proceed to the normal replay path and generate `done` after a successful start handshake. Separating these outcomes simplified verification because both happy-path and failure-path behavior can be asserted directly at the FSM boundary.

From a methodology perspective, the replay controller was developed as a sequence of increasingly realistic contracts: first read-handshake correctness, then payload integrity, then encoder/transmitter readiness gating, and finally protocol-specific replay correctness. This ordering helped isolate bugs early and reduced debug complexity when multiple modules interacted. In practice, the strongest lesson was that replay correctness depends less on the number of states and more on clear ownership boundaries: storage read timing, payload semantics, and start conditions must each be validated explicitly before moving to the next stage.

== NECEncoder

== IRTx

= My Contribution (Sauerwein Alexander)

Bringing up the
physical hardware prototype on the Arty A7-35T FPGA board, designing the IR receiver
and transmitter circuits with component selection, implementing the ESP32–FPGA serial
protocol, and building the Wi-Fi web interface.

== FPGA Hardware Bring-Up (Arty A7-35T)

The implementation was verified on a Digilent Arty A7-35T board carrying a Xilinx
Artix-7 XC7A35T FPGA. The board provides a 100 MHz system oscillator.

The FPGA I/O pins were mapped as folliwing:
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
verify the behavior:

#figure(
  table(
    columns: (auto, auto),
    table.header([*LED*], [*Meaning*]),
    [`LD7`], [Heartbeat — blinks at ≈ 0.8 s to confirm clock and reset are healthy],
    [`LD6`], [IR receiving — on while `ir_in` is active (demodulator output low)],
    [`LD4`], [Decode OK — 200 ms pulse after a valid frame is decoded],
    [`LD5`], [Record active — fast blink (≈ 100 ms) while a slot is being recorded],
  ),
  caption: [Debug LED assignments on the Arty A7-35T],
)

== IR Receiver Circuit

The IR receiver requires a supply voltage of *5 V*
to operate correctly. The Arty A7-35T board, however, only provides a *3.3 V* rail,
and its I/O pins must not see more than *3.4 V* on any input
(Artix-7 absolute maximum rating for $V_"IN"$ on a 3.3 V-powered bank @artix7_ds181).
Two problems therefore had to be solved:

+ *Boost the supply* from 3.3 V to 5 V for the Receiver power pin.
+ *Level-shift the output* of the TSOP (which swings between 0 V and $V_"CC"$ = 5 V)
  down to a safe 3.3 V logic level before connecting it to the FPGA.

Both issues are addressed by the circuit shown below.

=== Schematic

#figure(
  image("IR-Receiver.pdf", width: 80%),
  caption: [IR receiver circuit — 5 V power supply and output voltage divider],
) <fig-ir-rx>

=== Supply network

Instead of using the 3.3 V supply from the Arty A7-35T, an external $V_"CC" = 5 "V"$ DC power supply is used to power the IR receiver module. The 5 V supply is connected to the VCC pin, while its GND is shared with the FPGA board to maintain a common reference.

=== Output level-shift (voltage divider)

The Receiver output swings from 0 V (active) to $V_"CC" = 5 "V"$ (idle).
A resistive voltage divider scales this to a safe level for the 3.3 V FPGA input
($V_"in,max" = 3.4 "V"$).

Choose $R_1 = 1 "k"Omega$ (top) and $R_2 = 2 "k"Omega$ (bottom):

$
V_"out" = V_"CC,supply" times frac(R_2, R_1 + R_2)
        = 5 "V" times frac(1 "k" Omega, 1 "k" Omega + 2 "k" Omega)
        approx 3.33 "V" < 3.4 "V" space checkmark
$

== IR Transmitter Circuit

The Arty A7-35T only provides a *3.3 V* supply rail, and the FPGA control pin
`ir_tx_PAD` drives at 3.3 V logic levels. Because the IR LED requires
more current than the FPGA GPIO can safely source, (the Artix-7 datasheet specifies
a maximum of *12 mA* per output pin @artix7_ds181). An *NPN
transistor* (2N2222) is used as a switch between the LED
and GND. The FPGA drives only the base current. The entire circuit is supplied at 5V, as we use the same 5 V supply as the receiver. This allows the IR LED to achieve the necessary forward voltage and current.

=== Schematic

#figure(
  image("IR-Transmitter.pdf", width: 80%),
  caption: [IR transmitter circuit — NPN driving IR LED],
) <fig-ir-tx>

=== Design targets

- IR LED forward voltage: $V_F approx 1.2 "V"$
- LED current: $I_"f,LED" = 20 "mA"$, $I_"LED,max" = 100 "mA"$
- Supply: $V_"CC" = 5 "V"$ 
- NPN current gain: $h_"FE,min" = 100$ (conservative for 2N2222)
- FPGA GPIO output: 3.3 V, max. 12 mA drive capability (LVCMOS33 @artix7_ds181)

=== Led resistor $R_3$
To set the LED current to 20 mA:
$
R_3 = frac(V_"CC" - V_F, I_"f,LED")
    = frac(5 V - 1.2 V, 0.02 A)
    = 190 Omega
    -> "use" 220 Omega " (E12 series)"
$


=== Base resistor $R_4$

To saturate the transistor ($I_B >= I_"LED,max" / h_"FE"$) while keeping the FPGA GPIO
current within its 12 mA limit:

$
I_"B,needed" = frac(I_"LED,max", h_"FE,min") = frac(100 "mA", 100) = 1 "mA"
$

$
R_B = frac(V_"GPIO" - V_"BE", I_B)
    = frac(3.3 V - 0.6 V , 1 "mA")
    = frac(2.7 V, 1 "mA")
    = 2.7 space "k"Omega
$

$
  I_"GPIO" = frac(3.3 V - 0.6 V, 2.7 "k"Omega) =1 "mA" < 12 "mA" space checkmark
$

== ESP32–FPGA Serial Protocol Design

=== Design Evolution: from Parallel GPIO to Serial Protocol

The first approach considered for signalling commands from the ESP32-C3 to the FPGA
was to dedicate one output GPIO per slot asserting the corresponding pin high would
trigger a replay (short high pulse) or record (3 second high pulse) operation. While simple to implement in firmware, this
approach has a scalability problem: At first we only wanted to support 4 remotes with 2 slots each. This was doable, but we wanted to support more remotes and more buttons (now 4 remotes × 10 buttons)
plus a record/replay command input, at least 41 GPIOs would now be required.
The ESP32-C3 has only 22 usable GPIOs in total @esp32c3_devkitc02, making this approach impossible.

Another thought was to use a binary-encoded slot address over 6 GPIO lines
($2^6 = 64$ addressable slots) plus one GPIO for the command (PLAY / REC).
This would have required 7 FPGA input pins still unpractical, and any additional command types would require more pins.

The final design encodes the full command into a *2-wire serial frame* (DATA + CLK).
This reduces the physical connection to the absolute minimum and the protocol can be
extended with new command types or wider slot addresses without touching the hardware.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Approach*], [*GPIOs needed*], [*Drawback*]),
    [One GPIO per slot],        [≥ 41],  [Exceeds ESP32-C3 pin count entirely],
    [Binary slot + cmd GPIO],   [7],     [Rigid — adding commands requires more pins],
    [2-wire serial (chosen)],   [2],     [Requires synchronous receiver on FPGA side],
  ),
  caption: [Interface design alternatives considered],
)

=== ESP32-C3 Pin Mapping

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*ESP32-C3 GPIO*], [*Signal*], [*Connected to*]),
    [`GPIO 4`], [`DATA` (SPI MOSI)], [FPGA `spi_data_PAD`],
    [`GPIO 5`], [`CLK`  (SPI CLK)],  [FPGA `spi_clk_PAD`],
    [`GND`],    [Common ground],     [FPGA GND / 5 V supply GND],
  ),
  caption: [ESP32-C3 pin assignments for FPGA interface],
)

#pagebreak(weak: true)

=== Frame Format

A 12-bit frame is transmitted MSB-first over two bit-banged GPIO lines at 500 Baud
(1 ms per half-period, 2 ms per bit). The FPGA samples DATA on the rising CLK edge.

#figure(
  canvas(length: 1cm, {
    // ── layout constants ──────────────────────────────────────────────
    let bits = (
      // label, data bit value (for DATA line)
      // Example frame: slot=0b000001 (slot 1), cmd=001 (PLAY), magic=101
      // => bits [11..0] = 00 0001 001 101
      "0","0","0","0","0","1",   // slot [11:6]
      "0","0","1",               // cmd  [5:3]
      "1","0","1",               // magic[2:0]
    )
    let n     = bits.len()       // 12
    let bw    = 1.0              // bit width (cm)
    let clkY  = 2.2              // y-centre of CLK lane
    let datY  = 0.6              // y-centre of DATA lane
    let hi    = 0.55             // signal amplitude
    let lw    = 0.6pt            // line weight

    // ── idle period (half bit before first edge) ──────────────────────
    let idle  = 0.6
    let total = idle + n * bw + idle

    // ── lane labels ───────────────────────────────────────────────────
    draw.content((-.05, clkY), [*CLK*],  anchor: "east", padding: 2pt)
    draw.content((-.05, datY), [*DATA*], anchor: "east", padding: 2pt)

    // ── baseline (idle LOW) ───────────────────────────────────────────
    draw.line((0, clkY - hi), (total, clkY - hi),
              stroke: lw + gray)
    draw.line((0, datY - hi), (total, datY - hi),
              stroke: lw + gray)

    // ── CLK waveform ──────────────────────────────────────────────────
    // idle LOW, then for each bit: rise at t=0, fall at t=bw/2
    let clk-pts = ((0, clkY - hi), (idle, clkY - hi))
    for i in range(n) {
      let x0 = idle + i * bw
      let xm = x0 + bw * 0.5
      let x1 = x0 + bw
      clk-pts.push((x0, clkY - hi))
      clk-pts.push((x0, clkY + hi))
      clk-pts.push((xm, clkY + hi))
      clk-pts.push((xm, clkY - hi))
      clk-pts.push((x1, clkY - hi))
    }
    clk-pts.push((total, clkY - hi))
    draw.line(..clk-pts, stroke: lw + blue)

    // ── DATA waveform ─────────────────────────────────────────────────
    // DATA is set BEFORE the rising CLK edge and held until after
    let dat-pts = ((0, datY - hi),)
    // idle LOW
    dat-pts.push((idle, datY - hi))

    for i in range(n) {
      let x0  = idle + i * bw
      let x1  = x0 + bw
      let cur = if bits.at(i) == "1" { datY + hi } else { datY - hi }
      let nxt = if i + 1 < n {
        if bits.at(i + 1) == "1" { datY + hi } else { datY - hi }
      } else { datY - hi }   // return to idle after last bit

      dat-pts.push((x0, cur))
      dat-pts.push((x1, cur))
      if cur != nxt {
        dat-pts.push((x1, nxt))
      }
    }
    dat-pts.push((total, datY - hi))
    draw.line(..dat-pts, stroke: lw + red)

    // ── bit labels (field groups) ─────────────────────────────────────
    let fields = (
      (0,  5,  "Slot [11:6]"),
      (6,  8,  "Cmd [5:3]"),
      (9,  11, "Magic [2:0]"),
    )
    for (fs, fe, label) in fields {
      let x0 = idle + fs * bw
      let x1 = idle + (fe + 1) * bw
      let xm = (x0 + x1) / 2
      // bracket
      draw.line((x0 + 0.05, datY - hi - 0.25),
                (x0 + 0.05, datY - hi - 0.35),
                (x1 - 0.05, datY - hi - 0.35),
                (x1 - 0.05, datY - hi - 0.25),
                stroke: 0.5pt + black)
      draw.content((xm, datY - hi - 0.55), text(size: 7pt, label),
                   anchor: "center")
    }

    // ── individual bit value labels ───────────────────────────────────
    for i in range(n) {
      let xm = idle + i * bw + bw * 0.5
      draw.content((xm, datY),
                   text(size: 7pt, weight: "bold", bits.at(i)),
                   anchor: "center")
    }

    // ── rising-edge sample markers (↑) ───────────────────────────────
    for i in range(n) {
      let x = idle + i * bw
      draw.line((x, clkY - hi - 0.1), (x, clkY + hi + 0.1),
                stroke: (paint: green.darken(20%), thickness: 0.5pt,
                         dash: "dashed"))
    }

    // ── time axis ─────────────────────────────────────────────────────
    draw.line((0, -.85), (total, -.85), stroke: 0.5pt,
              mark: (end: ">"))
    draw.content((total + 0.1, -.85), text(size: 7pt)[t], anchor: "west")
    for i in range(n + 1) {
      let x = idle + i * bw
      draw.line((x, -.80), (x, -.90), stroke: 0.5pt)
      draw.content((x, -1.03),
                   text(size: 6pt, str(i) + " ms"),
                   anchor: "center")
    }
  }),
  caption: [
    Timing diagram of one 12-bit serial frame \
    (example: slot 1, PLAY command, magic `101`). \
    #text(size: 8pt)[
      #box(fill: blue,  width: 8pt, height: 4pt) CLK — \
      #box(fill: red,   width: 8pt, height: 4pt) DATA — \
      #box(fill: green.darken(20%), width: 8pt, height: 4pt) rising CLK edge (FPGA samples DATA here)
    ]
  ],
) <fig-timing>

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

During testing, the FPGA occasionally received corrupted frames due to GPIO
noise.

*Solution:* The 3-bit magic field (`101`) was introduced as a lightweight frame
validator. Frames not matching the magic value are discarded by the FPGA.

=== ESP32-C3 Firmware

The `fpga_send_frame(slot, cmd)` function in `wifi_button.c` sends the frame:

```c
// Build the 12-bit frame word
uint16_t frame = ((slot & 0x3F) << 6) | ((cmd & 0x7) << 3) | MAGIC;

// Clock out 12 bits, MSB first
for (int i = 11; i >= 0; i--) {
    gpio_set_level(GPIO_DATA, (frame >> i) & 1);
    vTaskDelay(pdMS_TO_TICKS(1));   // setup: 1 ms before rising CLK edge
    gpio_set_level(GPIO_CLK, 1);
    vTaskDelay(pdMS_TO_TICKS(1));   // hold:  1 ms after rising CLK edge
    gpio_set_level(GPIO_CLK, 0);
}
gpio_set_level(GPIO_DATA, 0);       // return to idle
```

== Wi-Fi Web Interface

=== Architecture

The ESP32-C3 runs FreeRTOS with ESP-IDF v5.x, configured as a Wi-Fi SoftAP
(SSID: _IR-Remote_). An `esp_http_server` instance handles all requests with
wildcard URI matching. When a user presses a button in the browser, the HTTP handler
calls `fpga_send_frame()` directly from the request task, keeping latency minimal.

=== HTTP API

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*Method*], [*URI*], [*Action*]),
    [`GET`],  [`/`],           [Home — overview of all 4 remotes],
    [`GET`],  [`/remote/N`],   [Detail page for remote _N_ (0–3)],
    [`GET`],  [`/replay/S`],   [Transmit PLAY frame for slot _S_ to FPGA],
    [`GET`],  [`/record/S`],   [Transmit REC frame for slot _S_ to FPGA],
    [`POST`], [`/rename/S`],   [Store a name for slot _S_ (plain-text body)],
  ),
  caption: [HTTP API endpoints],
) <tab-api>

=== Challenge: HTML buffer truncation on the last remote card

The dynamically-built HTML response was silently truncated, cutting off the last
remote card in the browser.

*Solution:* A `size_t` underflow in `snprintf` — it returns the _desired_ length even
when the buffer is full — caused `buf_size - pos` to wrap to a huge value. The buffer
was increased to 16 KB and all `snprintf` calls were wrapped in a `SNPRINTF_SAFE`
macro that clamps `pos` to `buf_size` before each write.

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
    [Serial baud rate],         [500 Baud (2 ms per bit, 1 ms half-period)],
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
= Chip Design Creation (Katalin Szentmiklosy)

 

Chip creation was performed using LibreLane with the IHP SG13G2 PDK. Initially, LibreLane v2.4.13 (main branch, commit aa0c518b) was used, where the chip flow failed with `Unknown flow 'Chip'`, as the chip flow was only available in newer versions. After switching to the dev environment (LibreLane v3.0.0.dev50, commit c771c564), the chip flow became available. To avoid inconsistencies between team members, a unified tool version was established (identical LibreLane commit, shared Nix shell environment).

 

== Baseline Implementation Without Padframe

 

The initial chip creation followed the lecture template and used a simplified architecture without ESP32 interface to first verify the basic chip flow. The configuration was built up incrementally: `meta.flow` switched to `Chip`, `PNR_SDC_FILE` and `SIGNOFF_SDC_FILE` explicitly set, `DIE_AREA` and `CORE_AREA` initially dimensioned generously (`[0, 0, 2000, 2000]` and `[500, 500, 1500, 1500]` respectively) to avoid placement issues during development. Initially, `ERROR_ON_SYNTH_CHECKS: false` was used, which caused unconnected nets to only become visible in late DRC stages. After enabling `ERROR_ON_SYNTH_CHECKS: true`, synthesis warnings became hard errors, immediately detecting an unconnected `clk_core` port that was then explicitly bound to `clk`.

 

#figure(

  image("chip_without_padframe.jpeg", width: 85%),

  caption: [Chip layout without padframe — initial core placement],

) <fig-chip-no-padframe>

 

== Padframe Integration

 

A dedicated wrapper (`ir_recorder_replay_padframe_top.sv`) was created that instantiates IHP SG13G2 IO pads (`sg13g2_IOPadIn`, `sg13g2_IOPadOut30mA`) and connects them to the core via `.pad`/`.p2c`/`.c2p` ports. Four mandatory power pads (`u_vdd_pad`, `u_vss_pad`, `u_iovdd_pad`, `u_iovss_pad`) were added, with their PG pins left implicit for synthesis compatibility, as explicit power pin connections caused errors in early synthesis stages. Pad placement was switched to real instance names (`u_pad_clk`, `u_pad_rst_n` instead of generic names), with the ordering defined via `PAD_WEST`/`EAST`/`NORTH`/`SOUTH` in `config.yaml`. Initially, `CORE_AREA` used non-grid-snapped values, leading to IFP-0028 warnings. The final values were set to grid coordinates (`[342.74, 343.71, 997.52, 994.95]`) to eliminate these warnings.

 

The PDN setup was configured through `PDN_ENABLE_PINS: true`, `PDN_CORE_RING: true`, and `PDN_CORE_RING_CONNECT_TO_PADS: false`, where the core ring is manually connected to pads via stripes. Ring widths were incrementally increased from initial 8 µm to final 15 µm until power grid violations were reduced to zero. SDC constraints were converted to `get_ports {...}` syntax (instead of `get_pins`) to correctly reference at pad level, and extended with symmetric IO delays for `inout` pads (`set_input_delay`/`set_output_delay` for `io_spi_data_pad`). Initially, erroneous `set_input_delay` definitions were set on `io_clk_pad` (clock port), leading to timing warnings, and were removed.

 

#figure(

  image("chip_small_with_padframe.jpeg", width: 85%),

  caption: [Chip layout with padframe — before architecture extensions],

) <fig-chip-small-padframe>

 

== Architecture Extension

 

After successful baseline with padframe, the architecture was extended: ESP32 SPI interface (`esp32_spi_receiver.sv`), multi-protocol support, and `raw_pulse_uart_formatter.sv` were added. Slot address widths were consistently changed to `ir_slot_t` (6 bit), as different modules initially used different widths (`[2:0]` in `ir_replay_fsm`, 6 bit in `esp32_spi_receiver`), leading to synthesis warnings about bit truncations. ESP32 SPI commands asserted `esp_slot_addr` for only one clock cycle, while the core logic required multiple cycles for processing. A latch (`esp_slot_addr_lat`) was introduced during integration to stabilize the address pulse; in the current implementation, `combined_slot_sel` is selected directly from `esp_slot_addr` on ESP request pulses. The top-level hierarchy was structured in two levels: `ir_recorder_replay_chip_top.sv` instantiates the core logic and combines external pad requests with ESP32 commands (`combined_record_req = record_req | esp_record_req`), while status signals (`stat_receiving`, `stat_code_valid`, `stat_record_active`) were mapped directly to output pads and handshake signals (`rec_done`, `rep_done`, `busy`, `error`) were marked as `_unused`.

 

Congestion issues were resolved through iterative adjustment of `PL_TARGET_DENSITY_PCT: 35` (initially 50%), `GPL_CELL_PADDING: 4`, `GRT_OVERFLOW_ITERS: 200`, and `DRT_OPT_ITERS: 64`. `RUN_POST_GRT_RESIZER_TIMING: true` enabled post-GRT timing repair, while `WIRE_LENGTH_THRESHOLD: 2000` was increased to avoid deferred wire-length aborts (longest observed wire: ~1613 µm at `io_spi_data_pad`). Antenna repair was configured through `GRT_ANTENNA_REPAIR_ITERS: 12`, `GRT_ANTENNA_REPAIR_MARGIN: 50`, and `GRT_ANTENNA_REPAIR_DIODE_ONLY: true` to fix antenna violations through diode insertion.

 

#figure(

  image("chip_big_with_padframe.jpeg", width: 85%),

  caption: [Extended chip layout with padframe — architecture with ESP32 interface and multi-protocol support],

) <fig-chip-big-padframe>

 

== Bondpad Integration and Area Optimization

 

70×70 µm bondpads from the provided `bondpad` folder were integrated via `PAD_BONDPAD_NAME: bondpad_70x70`, `EXTRA_GDS`, and `EXTRA_LEFS`. `PAD_PLACE_IO_TERMINALS` was set to `bondpad_70x70/pad` (explicit pin name) to avoid multi-pin BTerm errors that occurred when OpenROAD found multiple pins in the bondpad macro. Disconnected pin handling was tightened: blanket ignores (`IGNORE_DISCONNECTED_PINS: true`) were removed and replaced with targeted `IGNORE_DISCONNECTED_MODULES: [bondpad_70x70]`, while `ERROR_ON_DISCONNECTED_PINS: true` was set to immediately detect unconnected pins in core logic. Initially, slew warnings appeared at `io_uart_tx_pad` (max slew: 1.87 ns, limit: 1.5 ns) and `io_ir_tx_npn_drive_pad` (max slew: 2.13 ns). Buffer insertion (`sg13g2_buf_8`) was tested but only improved values marginally (1.87 → 1.82 ns), so the change was reverted as the warnings were within acceptable margins and caused no functional issues.

 

`DIE_AREA` and `CORE_AREA` were incrementally reduced to minimize chip area. In early project iterations, generous die areas up to 2000×2000 µm² were used, leading to unnecessarily high chip costs. Incremental reduction to final 1340×1340 µm² reduced die area by 55%, with congestion and timing checks performed after each iteration to ensure the reduction caused no routing problems. PDN obstructions (`PDN_OBSTRUCTIONS`, `ROUTING_OBSTRUCTIONS`) were set to `[TopMetal2, 495, 500, 845, 720]` to keep the reserved logo area free on TopMetal2.

 

#figure(

  image("final_chipdesign.jpeg", width: 85%),

  caption: [Final optimized chip layout — with bondpads and reduced die area],

) <fig-chip-final>

 

== Fast vs. Signoff Configuration

 

To accelerate development, two configurations were established: `config_fast.yaml` for rapid iterations (development cycles of ~15 min instead of ~2 hrs) and `config_signoff.yaml` for final verification. Both configs share identical design parameters (`CLOCK_PERIOD: 100`, `VERILOG_FILES`, `DIE_AREA`, PDN setup) but differ in `meta.substituting_steps`. `config_fast.yaml` skips expensive checks (DRC, Antenna, LVS, Density) to enable fast design iterations, while `config_signoff.yaml` activates all checks and only skips known issues (Magic overlap in bondpad regions, density checks). This split enabled rapid testing of design changes during development (e.g., congestion parameters, pad placement) and final verification only for stable designs.

 

== Final Configuration

 

The final signoff configuration uses `ir_recorder_replay_padframe_top` as top-level module with 100 ns clock period (10 MHz) and `CLOCK_PORT: io_clk_pad`. Pads are distributed across four sides: 5 West (clk, rst_n, ir_in, spi_clk, spi_data), 3 East (ir_tx, uart_tx, receiving), 2 North (valid, recording), with each pad connected to 70×70 µm bondpads (`bondpad_70x70`). The PDN uses a 15 µm core ring with 3.5 µm stripes at 40 µm pitch, while placement is configured with 35% target density and 4-cell padding. Routing uses 200 GRT iterations and 64 DRT iterations, with timing constraints specifying max fanout 16, max transition 1.25 ns, and buffer cell `sg13g2_buf_4`. The final signoff flow (`make librelane-signoff`) runs without blocking errors in the enabled checks; some checks (e.g., Magic DRC and selected density/overlap checks) remain intentionally substituted in the current signoff profile.

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
