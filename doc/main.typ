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

Infrared remote control systems are everywhere in consumer electronics and usually rely on simple pulse distance modulation. The original goal of this project was to build a simple hardware decoder for the standard NEC protocol that runs directly on an FPGA. We wanted to be able to decode the signals in real time and also record and replay them.

Because the baseline implementation was finished much faster than expected we decided to significantly expand the scope of the project. We added support for multiple different remotes and entirely different pulse distance protocols out of the box.

To make the whole system actually usable as a real consumer product we integrated an ESP32 microcontroller into the design. The FPGA handles all the strict timing requirements for receiving and transmitting the high speed infrared signals while the ESP32 provides a convenient wireless web interface. This allows us to store up to forty captured commands in named slots and replay any of them directly from a smartphone browser connecting any old infrared controlled device to a modern smart home setup.

#figure(
  image("../docs/images/supported_remotes.jpeg", width: 80%),
  caption: [A selection of the different remote controls supported by the decoder],
) <fig-supported-remotes>

= System Architecture

== Overview (Maik Unglert)

The architecture is split into two main hardware subsystems that work closely together to provide the full feature set. The FPGA acts as the raw hardware engine taking care of all the high speed signal processing. It decodes the incoming 38 kHz infrared bursts stores the captured commands in internal block RAM and accurately reconstructs the waveforms for playback.

On the other side the ESP32 serves as the brain of the user interface. It hosts a local Wi-Fi access point and a lightweight web server. When a user interacts with the web interface the ESP32 serializes the request into a custom two wire serial protocol and sends it over to the FPGA. This clear separation of concerns keeps the hardware logic simple and focused on strict timing while the microcontroller handles the complex network stack.

#figure(
  canvas({
    import draw: *
    set-style(line: (stroke: 1pt), content: (padding: .1))

    content((0, 2), box(stroke: 1pt, inset: 8pt, align(center)[*Original Remote*]), name: "remote")
    content((4, 2), box(stroke: 1pt, inset: 8pt, align(center)[*IR Receiver*]), name: "rx")

    content((0, -2), box(stroke: 1pt, inset: 8pt, align(center)[*Smartphone* \ Web UI]), name: "phone")
    content((4, -2), box(stroke: 1pt, inset: 8pt, align(center)[*ESP32* \ WiFi Server]), name: "esp")

    content(
      (8, 0),
      box(stroke: 1pt, inset: 8pt, align(center)[*FPGA Core* \ Decoder, Storage, \ Replay Encoder]),
      name: "fpga",
    )

    content((12, 0), box(stroke: 1pt, inset: 8pt, align(center)[*IR Transmitter* \ LED Circuit]), name: "tx")
    content((16, 0), box(stroke: 1pt, inset: 8pt, align(center)[*Target Device* \ TV, LED Strip]), name: "device")

    line("remote", "rx", mark: (end: ">"), name: "l1")
    content("l1.mid", text(7pt)[Infrared Space], anchor: "south", padding: 4pt)

    line("rx", "fpga", mark: (end: ">"), name: "l2")
    content("l2.mid", text(7pt)[Raw Pulses], anchor: "south-east", padding: 4pt)

    line("phone", "esp", mark: (start: ">", end: ">"), name: "l3")
    content("l3.mid", text(7pt)[HTTP / WiFi], anchor: "south", padding: 4pt)

    line("esp", "fpga", mark: (end: ">"), name: "l4")
    content("l4.mid", text(7pt)[SPI Commands], anchor: "north-east", padding: 4pt)

    line("fpga", "tx", mark: (end: ">"), name: "l5")
    content("l5.mid", text(7pt)[38 kHz Signal], anchor: "south", padding: 4pt)

    line("tx", "device", mark: (end: ">"), name: "l6")
    content("l6.mid", text(7pt)[Infrared Space], anchor: "south", padding: 4pt)
  }),
  caption: [System architecture overview showing the real world interaction flow],
) <fig-system-arch>

== EdgeDetector (Lukas Mittermeier)

Monitors the demodulated IR receiver output and produces single-cycle strobe pulses
on rising and falling edges, providing the timing reference for `PulseTimer`.

=== Challenge: Glitches from the IR demodulator

The TSOP-series demodulator occasionally produces sub-microsecond glitches that
triggered false edge detections.

*Solution:* A 2-stage synchronizer followed by a simple debounce counter (3 clock
cycles) was added before the edge detection logic, eliminating spurious pulses without
affecting timing accuracy.

== PulseTimer (Lukas Mittermeier)

Measures the duration of each IR pulse in clock cycles and outputs the width together
with a polarity flag to the `NECDecoder`.

=== Challenge: Counter overflow on missing stop bit

If no falling edge arrives after the final NEC data bit (missing stop bit), the
counter would overflow and corrupt the next frame's timing.

*Solution:* A configurable timeout was added. If the counter exceeds the maximum
expected NEC pulse width (~70 ms), it resets and signals a timeout to the decoder FSM,
which returns to its idle state.

== NECDecoder (Maik Unglert)

The `nec_decoder` is the central component of the IR receiver pipeline. It consumes
pulse measurements from `ir_pulse_timer` and decodes them into complete IR frames
according to the NEC protocol, as well as the Samsung32, Samsung36, and the
project-specific N8X2 dialect.

=== NEC Protocol Basics

Before diving into the implementation, it helps to understand how NEC actually works.
The other protocols the decoder supports (Samsung32, Samsung36, N8X2) are all built
on the same idea, so NEC is covered here as the representative example.

NEC uses Pulse Distance Modulation on a 38 kHz carrier. The idea is simple. Every
bit is made up of a short 562 µs burst, followed by a space. The length of that space
determines whether it's a `0` (562 µs) or a `1` (1687 µs).

#figure(
  image("../docs/images/necmodulation.png", width: 85%),
  caption: [NEC bit encoding: the burst is always 562 µs, the space length determines
    the bit value @sbprojects_nec],
) <fig-nec-modulation>

A complete NEC frame carries 32 bits, split into four 8-bit fields, all transmitted
LSB-first: Address, \~Address, Command, and \~Command. The inverted bytes serve
as a checksum. If `address XOR ~address` or `command XOR ~command` doesn't equal
`0xFF`, the frame is considered corrupted and discarded. The whole thing is preceded
by a 9 ms leader burst and a 4.5 ms space, which the receiver uses to detect the
start of a new frame.

#figure(
  image("../docs/images/nectrain.png", width: 90%),
  caption: [Full NEC frame structure: 9 ms leader + 4.5 ms space + 32 data bits
    (Address, \~Address, Command, \~Command), LSB first @sbprojects_nec],
) <fig-nec-full-frame>

Each button press sends exactly one such frame. If the button is held down, the remote
doesn't repeat the full frame. Instead it sends a much shorter repeat code (9 ms
burst + 2.25 ms space + 562 µs stop burst) every ~110 ms for as long as the button
stays pressed.

#figure(
  image("../docs/images/necsequence.png", width: 90%),
  caption: [NEC repeat sequence: one full command frame, then repeat codes every
    ~110 ms while the button is held @sbprojects_nec],
) <fig-nec-repeat>

=== FSM Architecture

The decoder itself is not particularly complicated to design. NEC is a well-documented
protocol, and mapping it to a state machine is fairly straightforward. The FSM starts
in IDLE, waits for an AGC burst to kick things off, then steps through the leader
space, the individual data bits, and finally a validation step where the checksum is
checked. If anything goes wrong at any point, a timeout or an unexpected pulse sends
it straight back to IDLE.

The part that took more work was getting it to behave reliably with real remotes under
real conditions. On paper the protocol is clean; in practice, remotes deviate from the
spec, demodulators have quirks, and held buttons send a stream of repeat codes that
need careful handling. @fig-nec-fsm shows the full state machine; the following
sections describe the practical problems that came up during testing.

#figure(
  canvas(length: 1.0cm, {
    import draw: *

    let box(pos, lbl, id) = {
      let (x, y) = pos
      rect(
        (x - 1.15, y - 0.32),
        (x + 1.15, y + 0.32),
        radius: 0.18,
        name: id,
        fill: rgb("#e3f2fd"),
        stroke: rgb("#1565c0") + 0.9pt,
      )
      content((x, y), text(size: 6.8pt, weight: "bold", lbl))
    }
    let note(pos, t) = content(pos, text(size: 5.4pt, fill: luma(80), t))
    let arr(a, b) = line(a, b, stroke: 0.75pt, mark: (end: ">", size: 0.18))

    // Layout:
    //   main column   x = 0   (IDLE, LEADER, SPACE, DATA, VALIDATE)
    //   repeat column x = 5   (REPEAT_WAIT_STOP, REPEAT_EMIT)
    //   left  return rail  x = -2.5  (VALIDATE → IDLE)
    //   right return rail  x =  7.2  (REPEAT_EMIT → IDLE)

    box((0, 0), "IDLE", "idle")
    box((0, -3), "LEADER", "leader")
    box((0, -6), "SPACE", "space")
    box((0, -9), "DATA", "data")
    box((0, -12), "VALIDATE", "validate")
    box((5, -6), "REPEAT\_WAIT\_STOP", "rwait")
    box((5, -9), "REPEAT\_EMIT", "remit")

    // protocol hints right of their states
    note((1.4, -3.5), [NEC: 9 ms\ Sam: 4.5 ms])
    note((1.4, -9.5), [8 / 32 / 36 bits])

    // ── main path ──────────────────────────────────────────────────
    arr("idle.south", "leader.north")
    note((-1.7, -1.5), [AGC burst])

    arr("leader.south", "space.north")
    note((-1.7, -4.5), [AGC space])

    arr("space.south", "data.north")
    note((-1.7, -7.5), [first bit])

    arr("data.south", "validate.north")
    note((-1.7, -10.5), [all bits done])

    // DATA self-loop (left side)
    bezier("data.west", "data.west", (-2.0, -8.6), (-2.0, -9.4), stroke: 0.75pt, mark: (end: ">", size: 0.18))
    note((-2.4, -9), [next bit])

    // ── VALIDATE → IDLE via FAR LEFT rail ──────────────────────────
    line((-1.15, -12), (-2.5, -12), (-2.5, 0), (-1.15, 0), stroke: 0.75pt, mark: (end: ">", size: 0.18))
    note((-3.25, -6), [checksum OK\ → data\_valid])

    // ── repeat branch ──────────────────────────────────────────────
    // LEADER → REPEAT_WAIT_STOP (right, then level)
    line("leader.east", (3.0, -3), (3.0, -6), "rwait.west", stroke: 0.75pt, mark: (end: ">", size: 0.18))
    note((3.15, -4.5), [repeat space\ + armed])

    arr("rwait.south", "remit.north")
    note((6.3, -7.5), [stop burst])

    // ── REPEAT_EMIT → IDLE via FAR RIGHT rail ──────────────────────
    line((6.15, -9), (7.2, -9), (7.2, 0), (1.15, 0), stroke: 0.75pt, mark: (end: ">", size: 0.18))
    note((7.4, -4.5), [re-emit\ data\_valid])

    // ── start ──────────────────────────────────────────────────────
    arr((0, 0.75), "idle.north")
    note((0, 0.92), [Reset])
  }),
  caption: [NECDecoder state machine. LEADER detects protocol from leader burst length
    (NEC: 9 ms, Samsung: 4.5 ms). DATA collects 8, 32, or 36 bits.
    Any timeout in any state resets to IDLE.],
) <fig-nec-fsm>

=== Multi-Protocol Support

During testing in the lab it turned out that the remotes we had around did not all
speak standard NEC. Some Samsung remotes use a shorter 4.5 ms leader instead of 9 ms,
and some use 36-bit frames instead of 32. There was also a cheap RGB LED controller
that sent only 8-bit frames with slightly different timing. So the decoder ended up
supporting four variants, all built on the same pulse-distance principle.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header([*Protocol*], [*Leader*], [*Data bits*], [*Checksum*]),
    [`NEC`      ], [9 ms burst + 4.5 ms], [32 (8+8+8+8)], [addr XOR \~addr, cmd XOR \~cmd],
    [`Samsung32`], [4.5 ms burst + 4.5 ms], [32], [cmd XOR \~cmd],
    [`Samsung36`], [4.5 ms + split-sync], [36], [cmd XOR \~cmd (lenient)],
    [`N8X2`     ], [9 ms burst + 4.5 ms], [8], [none],
  ),
  caption: [Supported protocol variants in `nec_decoder`],
)


=== Getting It to Work with Real Remotes

The initial simulation passed every test case, but as soon as a physical remote was
pointed at the receiver things started going wrong. The first hurdle was timing
tolerance: the NEC spec says a leader burst is 9 ms, but different remote brands
deviate by up to 15 % in either direction, and the first version used exact window
comparisons that rejected anything not close enough. Switching to ±20 % windows
fixed that, and all the limits were moved into named `localparam` constants so they
could be adjusted per brand without touching FSM logic.

Once frames were coming through, the next challenge was figuring out which protocol
each remote actually spoke. Without a logic analyzer, the first attempt was Vivado's
built-in ILA monitor, but getting comfortable with it took more time than it was
worth. The simpler solution was to send the raw pulse timings over UART at a high
baud rate and read them in a terminal, then compare the numbers against the IRMP
protocol reference @irmp. That turned out to be the most practical approach.

Most remotes matched a known protocol right away. One exception was a cheap RGB LED
remote that produced 8-bit frames with the same 9 ms leader and 4.5 ms space as NEC,
but with a logical-1 space of around 1.03 ms instead of NEC's 1.69 ms and no
checksum at all. Nothing in the IRMP list matched it, so the protocol was implemented
under the name N8X2.

The Samsung36 remote came with a structural quirk. Halfway through its 36-bit frame,
after the first 16 address bits, it sends another long 4.5 ms space as a delimiter
before the remaining 20 bits. The decoder initially saw that space, assumed the frame
was over, and discarded everything. The fix was a check inside the DATA state: if the
protocol is Samsung, the bit counter is in the range 16 to 18, and the space duration
falls within the AGC-space window, the space is consumed silently without advancing
the bit counter and the FSM continues.

The last issue only appeared when using multiple remotes in quick succession. A weakly
received signal from one remote, arriving shortly after a valid frame from another,
could accidentally match the structure of a repeat code. Since the decoder still
remembered the previous frame, it accepted the garbled signal as a repeat and
produced a phantom output. Tightening the timing windows for repeat detection and
adding stricter structure checks solved this.



== OutputFormatter (Lukas Mittermeier)

Serializes decoded NEC frames (address + command) into ASCII for UART transmission,
enabling host-side logging and testbench verification.

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

== NEC Encoder (Maik Unglert)

To support the replay functionality, a complete transmit path was needed. The encoder
module sits in the middle of this path, taking a stored frame payload from the
`IRReplayFSM` and turning it into a single-wire digital sequence called `mark_active`,
which is then sent to the `IRTx` module to drive the physical LED.

The architecture is built around a simple state machine driven by a one-microsecond
tick. It moves through the leader burst, leader space, data bits, and a final stop
burst. Although its name and internal documentation focus heavily on the NEC standard,
it actually supports all four protocol variants out of the box. It achieves this by
reading the protocol ID from the payload and dynamically adjusting the required waiting
times for bursts and spaces on the fly.

In stark contrast to the decoder, bringing up the encoder was relatively painless.
The decoder had to deal with noisy physical signals, distorted pulse widths, and
unpredictable remotes. The encoder, on the other hand, only needs to output perfectly
timed digital signals. Getting it to match the exact timing requirements took some
testing, but the real challenge was handling all the protocol-specific quirks
perfectly in reverse.

The Samsung36 protocol requires a strange 4.5 ms sync space right in the middle of
the frame. The encoder handles this by pausing the normal bit transmission when the
bit index hits 16, inserting the sync burst and space, and only then moving on to
the remaining bits.

Repeat codes were another edge case. When the repeat flag is set in the stored
payload, the encoder skips the data bits entirely. It just outputs the 9 ms leader
mark, a shorter 2.25 ms space, and directly goes to the stop burst. Everything is
driven by the same microsecond counter, which made it easy to dial in the exact
lengths needed to reliably trigger different TV and LED receivers.

== IRTx (Maik Unglert)

The final piece of the playback chain is the transmitter module. While the encoder
figures out the exact microsecond lengths of the bursts and spaces, the infrared LED
cannot just be turned on solidly during a burst. It needs to be pulsed rapidly at a
specific carrier frequency so the receiver on the other end can distinguish the
signal from background light.

The `IRTx` module takes the `mark_active` signal from the encoder and modulates it
with a 38 kHz carrier wave. It uses a simple clock divider that counts system ticks
and toggles the output pin at the correct frequency whenever the encoder says a burst
is active. During spaces, the output is held low. This modulated 38 kHz digital
pulse train is routed directly to an FPGA pin to drive an external NPN transistor
circuit, which switches the high current needed for the actual IR LED (the physical
circuit design is detailed in @sec-irtx-hardware).

#figure(
  canvas(length: 1cm, {
    let lw = 0.8pt
    let w = 8

    // Labels
    draw.content((-0.2, 2.5), [*`mark_active`*], anchor: "east")
    draw.content((-0.2, 1.25), [*38 kHz Carrier*], anchor: "east")
    draw.content((-0.2, 0), [*`ir_tx` Out*], anchor: "east")

    // mark_active waveform (high - low - high)
    draw.line((0, 2), (0, 3), (3, 3), (3, 2), (6, 2), (6, 3), (w, 3), stroke: lw + blue)
    draw.content((1.5, 3.2), text(size: 8pt)[Burst (Mark)], anchor: "south")
    draw.content((4.5, 2.2), text(size: 8pt)[Space], anchor: "south")
    draw.content((7.0, 3.2), text(size: 8pt)[Burst (Mark)], anchor: "south")

    // Carrier waveform (continuous)
    let carrier_pts = ()
    for i in range(24) {
      let x = i * (w / 23)
      let y = 1.0 + calc.sin(i * 180deg) * 0.5
      carrier_pts.push((x, y))
    }
    // Make square waves out of the points
    for i in range(0, 23, step: 2) {
      draw.line(
        (i * (w / 24), 1),
        (i * (w / 24), 1.5),
        ((i + 1) * (w / 24), 1.5),
        ((i + 1) * (w / 24), 1),
        ((i + 2) * (w / 24), 1),
        stroke: lw + gray,
      )
    }

    // Modulated output waveform (carrier when high, low when low)
    for i in range(0, 23, step: 2) {
      let x1 = i * (w / 24)
      let x2 = (i + 1) * (w / 24)
      let x3 = (i + 2) * (w / 24)

      // Inside first burst
      if x3 <= 3 {
        draw.line((x1, -0.5), (x1, 0), (x2, 0), (x2, -0.5), (x3, -0.5), stroke: lw + red)
      } // Inside space
      else if x1 >= 3 and x3 <= 6 {
        draw.line((x1, -0.5), (x3, -0.5), stroke: lw + red)
      } // Inside second burst
      else if x1 >= 6 {
        draw.line((x1, -0.5), (x1, 0), (x2, 0), (x2, -0.5), (x3, -0.5), stroke: lw + red)
      }
    }

    // Time axis
    draw.line((0, -1.2), (w + 0.5, -1.2), stroke: 0.5pt, mark: (end: ">"))
    draw.content((w + 0.6, -1.2), text(size: 8pt)[$t$], anchor: "west")
  }),
  caption: [Modulation of the `mark_active` envelope onto the 38 kHz carrier],
) <fig-irtx-modulation>


= Bringing up the physical hardware

Bringing up the
physical hardware prototype on the Arty A7-35T FPGA board, designing the IR receiver
and transmitter circuits with component selection, implementing the ESP32–FPGA serial
protocol and building the WiFi web interface.

== FPGA Hardware Bring Up (Arty A7-35T) (Alexander Sauerwein)

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

Status LEDs were mapped to the four on board RGB LEDs and used during bring up to
verify the behavior:

#figure(
  table(
    columns: (auto, auto),
    table.header([*LED*], [*Meaning*]),
    [`LD7`], [Heartbeat: blinks at ≈ 0.8 s to confirm clock and reset are healthy],
    [`LD6`], [IR receiving: on while `ir_in` is active],
    [`LD4`], [Decode OK: 200 ms pulse after a valid frame is decoded],
    [`LD5`], [Record active: fast blink (≈ 100 ms) while a slot is being recorded],
  ),
  caption: [Debug LED assignments on the Arty A7-35T],
)

== IR Receiver Circuit (Alexander Sauerwein)

The IR receiver requires a supply voltage of *5 V*
to operate correctly. The Arty A7-35T board, however, only provides a *3.3 V* rail,
and its I/O pins must not see more than *3.4 V* on any input
(Artix-7 absolute maximum rating for $V_"IN"$ on a 3.3 V-powered bank @artix7_ds181).
Two problems therefore had to be solved:

+ *Boost the supply* from 3.3 V to 5 V for the Receiver power pin.
+ *Level shift the output* of the TSOP (which swings between 0 V and $V_"CC"$ = 5 V)
  down to a safe 3.3 V logic level before connecting it to the FPGA.

=== Schematic

#figure(
  image("IR-Receiver.pdf", width: 80%),
  caption: [IR receiver circuit, 5 V power supply and output voltage divider],
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

== IR Transmitter Circuit (Alexander Sauerwein) <sec-irtx-hardware>

The Arty A7-35T only provides a *3.3 V* supply rail and the FPGA control pin
`ir_tx_PAD` drives at 3.3 V logic levels. Because the IR LED requires
more current than the FPGA GPIO can safely source, (the Artix-7 datasheet specifies
a maximum of *12 mA* per output pin @artix7_ds181). An *NPN
transistor* (2N2222) is used as a switch between the LED
and GND. The FPGA drives only the base current. The entire circuit is supplied at 5V, as we use the same 5 V supply as the receiver. This allows the IR LED to achieve the necessary forward voltage and current.

=== Schematic

#figure(
  image("IR-Transmitter.pdf", width: 80%),
  caption: [IR transmitter circuit, NPN driving IR LED],
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
  = frac(3.3 V - 0.6 V, 1 "mA")
  = frac(2.7 V, 1 "mA")
  = 2.7 space "k"Omega
$

$
  I_"GPIO" = frac(3.3 V - 0.6 V, 2.7 "k"Omega) =1 "mA" < 12 "mA" space checkmark
$

== ESP32–FPGA Serial Protocol Design (Alexander Sauerwein)

=== Design Evolution: from Parallel GPIO to Serial Protocol

The first approach considered for signalling commands from the ESP32-C3 to the FPGA
was to dedicate one output GPIO per slot asserting the corresponding pin high would
trigger a replay (short high pulse) or record (3 second high pulse) operation. While simple to implement in firmware, this
approach has a scalability problem: At first we only wanted to support 4 remotes with 2 slots each. This was doable, but we wanted to support more remotes and more buttons (now 4 remotes × 10 buttons)
plus a record/replay command input, at least 41 GPIOs would now be required.
The ESP32-C3 has only 22 usable GPIOs in total @esp32c3_devkitc02, making this approach impossible.

Another thought was to use a binary encoded slot address over 6 GPIO lines
($2^6 = 64$ addressable slots) plus one GPIO for the command (PLAY / REC).
This would have required 7 FPGA input pins which is still unpractical and any additional command types would require more pins.

The final design encodes the full command into a *2 wire serial frame* (DATA + CLK).
This reduces the physical connection to the absolute minimum and the protocol can be
extended with new command types or wider slot addresses without touching the hardware.

=== ESP32-C3 Pin Mapping

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*ESP32-C3 GPIO*], [*Signal*], [*Connected to*]),
    [`GPIO 4`], [`DATA` (SPI MOSI)], [FPGA `spi_data_PAD`],
    [`GPIO 5`], [`CLK`  (SPI CLK)], [FPGA `spi_clk_PAD`],
    [`GND`], [Common ground], [FPGA GND / 5 V supply GND],
  ),
  caption: [ESP32-C3 pin assignments for FPGA interface],
)


=== Frame Format

A 12 bit frame is transmitted over two bit GPIO lines at 500 Baud
(1 ms per half period, 2 ms per bit). The FPGA samples DATA on the rising CLK edge.

#figure(
  canvas(length: 1cm, {
    // ── layout constants ──────────────────────────────────────────────
    let bits = (
      // label, data bit value (for DATA line)
      // Example frame: slot=0b000001 (slot 1), cmd=001 (PLAY), magic=101
      // => bits [11..0] = 00 0001 001 101
      "0",
      "0",
      "0",
      "0",
      "0",
      "1", // slot [11:6]
      "0",
      "0",
      "1", // cmd  [5:3]
      "1",
      "0",
      "1", // magic[2:0]
    )
    let n = bits.len() // 12
    let bw = 1.0 // bit width (cm)
    let clkY = 2.2 // y-centre of CLK lane
    let datY = 0.6 // y-centre of DATA lane
    let hi = 0.55 // signal amplitude
    let lw = 0.6pt // line weight

    // ── idle period (half bit before first edge) ──────────────────────
    let idle = 0.6
    let total = idle + n * bw + idle

    // ── lane labels ───────────────────────────────────────────────────
    draw.content((-.05, clkY), [*CLK*], anchor: "east", padding: 2pt)
    draw.content((-.05, datY), [*DATA*], anchor: "east", padding: 2pt)

    // ── baseline (idle LOW) ───────────────────────────────────────────
    draw.line((0, clkY - hi), (total, clkY - hi), stroke: lw + gray)
    draw.line((0, datY - hi), (total, datY - hi), stroke: lw + gray)

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
      let x0 = idle + i * bw
      let x1 = x0 + bw
      let cur = if bits.at(i) == "1" { datY + hi } else { datY - hi }
      let nxt = if i + 1 < n {
        if bits.at(i + 1) == "1" { datY + hi } else { datY - hi }
      } else { datY - hi } // return to idle after last bit

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
      (0, 5, "Slot [11:6]"),
      (6, 8, "Cmd [5:3]"),
      (9, 11, "Magic [2:0]"),
    )
    for (fs, fe, label) in fields {
      let x0 = idle + fs * bw
      let x1 = idle + (fe + 1) * bw
      let xm = (x0 + x1) / 2
      // bracket
      draw.line(
        (x0 + 0.05, datY - hi - 0.25),
        (x0 + 0.05, datY - hi - 0.35),
        (x1 - 0.05, datY - hi - 0.35),
        (x1 - 0.05, datY - hi - 0.25),
        stroke: 0.5pt + black,
      )
      draw.content((xm, datY - hi - 0.55), text(size: 7pt, label), anchor: "center")
    }

    // ── individual bit value labels ───────────────────────────────────
    for i in range(n) {
      let xm = idle + i * bw + bw * 0.5
      draw.content((xm, datY), text(size: 7pt, weight: "bold", bits.at(i)), anchor: "center")
    }

    // ── rising-edge sample markers (↑) ───────────────────────────────
    for i in range(n) {
      let x = idle + i * bw
      draw.line((x, clkY - hi - 0.1), (x, clkY + hi + 0.1), stroke: (
        paint: green.darken(20%),
        thickness: 0.5pt,
        dash: "dashed",
      ))
    }

    // ── time axis ─────────────────────────────────────────────────────
    draw.line((0, -.85), (total, -.85), stroke: 0.5pt, mark: (end: ">"))
    draw.content((total + 0.1, -.85), text(size: 7pt)[t], anchor: "west")
    for i in range(n + 1) {
      let x = idle + i * bw
      draw.line((x, -.80), (x, -.90), stroke: 0.5pt)
      draw.content((x, -1.03), text(size: 6pt, str(i) + " ms"), anchor: "center")
    }
  }),
  caption: [
    Timing diagram of one 12-bit serial frame \
    (example: slot 1, PLAY command, magic `101`).
  ],
) <fig-timing>

#pagebreak(weak: true)

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*Bits*], [*Field*], [*Description*]),
    [11:6], [Slot address], [`000001` = slot 1,..., `101000` = slot 40],
    [5:3], [Command], [`001` = PLAY, `010` = REC],
    [2:0], [Magic], [`101`  discards corrupted frames on FPGA],
  ),
  caption: [12 bit serial frame layout],
) <tab-frame>

=== Challenge: Noise on the serial line

During testing, the FPGA occasionally received corrupted frames due to GPIO
noise.

*Solution:* The 3 bit magic field (`101`) was introduced as a frame
validator. Frames not matching the magic value are discarded by the FPGA.

=== FPGA-Side Receiver (Maik Unglert)

Once the ESP32-C3 was configured to transmit the core commands over the wire,
we needed a way for the FPGA to safely receive and interpret this data. Because the ESP32
and the FPGA operate on completely different, unsynchronized clocks, we couldn't just wire
the pins directly into our state machines.

To solve this, the `esp32_spi_receiver` was built as a standalone, 4-stage pipeline that
safely bridges the gap between the two hardware domains:

1. *2-FF Synchronizer:* First, we pass the incoming clock and data lines through two
  cascaded flip-flops. This "cleans" the signal and safely brings it into the FPGA's
  internal 10 MHz clock domain without risking metastability (crashing the logic).
2. *Edge Detector:* Now that the clock is synchronized, we look for just the rising edge
  of it. This generates a tiny, one-cycle pulse (`clk_rise`) that tells the rest of the
  receiver exactly when a new bit of data is ready to be read.
3. *Idle Timeout:* If the ESP32 crashes or is power-cycled mid-transmission, we would
  normally be stuck waiting forever for the rest of an incomplete frame. We added a timer
  that simply resets the receiver if the clock goes quiet for more than 3 milliseconds.
4. *Shift Register & Magic Check:* With the timing locked in, the 12 bits are shifted in.
  Once full, the receiver checks if the last 3 bits match our expected `101` "magic" value.
  If yes, the frame is valid, and the slot address and command are forwarded to the core logic.

#figure(
  canvas({
    import draw: *
    set-style(line: (stroke: 1pt), content: (padding: .1))

    content((0, 0), [*ESP32*], name: "esp")

    content((3.5, 0), box(stroke: 1pt, inset: 6pt, align(center)[2-FF \ Sync]), name: "sync")
    content((7, 2), box(stroke: 1pt, inset: 6pt, align(center)[Edge \ Detect]), name: "edge")
    content((7, -2), box(stroke: 1pt, inset: 6pt, align(center)[Idle \ Timeout]), name: "timeout")
    content((11, 0), box(stroke: 1pt, inset: 6pt, align(center)[Shift Reg & \ Magic Check]), name: "shift")

    content((15, 0), [*FPGA Core*], name: "out")

    line("esp", "sync", mark: (end: ">"), name: "l1")
    content("l1.mid", text(7pt)[`clk`, `data`], anchor: "south")

    line("sync", "edge", mark: (end: ">"), name: "l2")
    content("l2.mid", text(7pt)[`clk_sync`], anchor: "south-east")

    line("sync", "timeout", mark: (end: ">"), name: "l3")
    content("l3.mid", text(7pt)[`clk_sync`], anchor: "north-east")

    line("sync", "shift", mark: (end: ">"), name: "l4")
    content("l4.mid", text(7pt)[`data_sync`], anchor: "south")

    line("edge", "shift", mark: (end: ">"), name: "l5")
    content("l5.mid", text(7pt)[`clk_rise`], anchor: "south-west")

    line("timeout", "shift", mark: (end: ">"), name: "l6")
    content("l6.mid", text(7pt)[`rst_cnt`], anchor: "north-west")

    line("shift", "out", mark: (end: ">"), name: "l7")
    content("l7.mid", text(7pt)[`slot`, `req`], anchor: "south")
  }),
  caption: [Block diagram illustrating the four pipeline stages of the SPI receiver.],
) <fig-spi-receiver>

Thanks to good communication with Alex, the integration between the ESP32 and the FPGA went smoothly, resulting in almost no problems and only minor issues.

== WiFi Web Interface (Alexander Sauerwein)

=== Architecture

Initially the ESP32-C3 was connected to an existing local WiFi network and
served the web interface from there. But during testing, the round trip latency was
unacceptably high: the client request had to travel through the router and back before
the FPGA command was sent, and network congestion made response times inconsistent (we waited up to 10 seconds).

To eliminate the router hop entirely, the ESP32-C3 was reconfigured as a *WiFi
SoftAP* (SSID: _IR-Remote_). The client connects directly to the ESP32, so every HTTP
request arrives in one wireless hop and the HTTP handler can call `fpga_send_frame()`
immediately.


=== HTTP API

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*Method*], [*URI*], [*Action*]),
    [`GET`], [`/`], [Home overview of all 4 remotes],
    [`GET`], [`/remote/N`], [Detail page for remote _N_ (0–3)],
    [`GET`], [`/replay/S`], [Transmit PLAY frame for slot _S_ to FPGA],
    [`GET`], [`/record/S`], [Transmit REC frame for slot _S_ to FPGA],
    [`POST`], [`/rename/S`], [Store a name for slot _S_ (plain-text body)],
  ),
  caption: [HTTP API endpoints],
) <tab-api>

= Flashing the FPGA (Maik Unglert)

== Hardware Components & Top-Level Integration

As detailed in the earlier chapters, the system is built from several modular IP
components (decoder, recorder/memory, replay FSM, encoder, etc.). To tie all these
individual hardware components together, a global `ir_recorder_replay_top` module
was created. This file handles the entire datapath from the incoming physical IR pulse
to the decoding, storage, replay, and final IR transmission.

When bringing this design to the physical FPGA board via the `ir_recorder_replay_arty_top`
wrapper, several integration challenges emerged that required immediate fixes:

- *Clock Mismatch:* The individual modules (`nec_decoder`, `pulse_timer`, etc.) were
  originally implemented and tested with a 10 MHz clock assumption. The Arty A7 board,
  however, provides a 100 MHz oscillator. Instead of using an internal PLL to divide
  the clock, the entire codebase was adapted by parameterizing every time-dependent
  module with a `CORE_CLK_HZ` parameter. This allowed the core logic to dynamically
  calculate its internal 1 µs ticks and UART baud rates based directly on the 100 MHz
  board clock.
- *Invisible LED Pulses:* Status signals like `dec_valid` or `error` only assert for
  a single clock cycle. At 100 MHz, this is just 10 nanoseconds — completely invisible
  to the human eye. To solve this, dedicated pulse-stretching timers were added to the
  top-level wrapper, holding the debug LEDs on for 200 ms whenever a flag is triggered.
- *Button Multiplexing for Standalone Testing:* Before the ESP32 WiFi bridge was even
  connected, we needed a way to test the core FPGA record and replay logic directly
  on the hardware. The Arty board only provides four physical buttons, but we
  needed to trigger both recording and replaying across four different memory slots
  to verify the memory management. This was solved by implementing a press-classification
  timer in the top level. A short press triggers a replay, while holding the button
  for more than 0.6 seconds triggers a record operation for that specific slot.

== Vivado CLI Automation

Initially, the standard Vivado GUI was installed to compile and flash the bitstream.
However, the GUI proved to be incredibly sluggish, bloated, and actively hindered a
fast iterative development cycle. Opening the project, clicking through the synthesis,
implementation, and bitstream generation menus took far too much time and broke focus.

To solve this, the entire FPGA build process was heavily automated using Vivado's
command-line mode (`vivado -mode batch`). Because the project was developed in a
strictly modular fashion — where each component like the encoder, decoder, and UART
resides in its own isolated directory — a central integration folder was created
to house the build scripts.

- `build.tcl`: This script automatically creates an in-memory Vivado project and dynamically
  collects all necessary `.sv` source files scattered across the different component
  folders. It then attaches the Arty A7 constraints file (`.xdc`), sets the top module
  to `ir_recorder_replay_arty_top`, and sequentially launches multi-threaded synthesis
  and implementation runs until the final `.bit` file is generated.
- `program_arty.tcl`: This script connects to the local hardware server, searches
  the USB bus for the connected Artix-7 target, uploads the generated bitstream
  directly to the FPGA, and closes the connection.

This automation allows the entire project to be built and flashed from scratch with a
single `make program` command in the terminal, completely bypassing the Vivado GUI.

= End-to-End System Validation

With the FPGA logic complete and the physical hardware assembled, the true test was
seeing if the system could fully replace real remote controls in a living room
environment. Using the WiFi web interface, several commercial devices were targeted:
a Samsung television, a Samsung sound system, and a generic RGB LED strip.

The process of pointing the original remote at the receiver, hitting record on the web
interface, and then using the digital interface to replay the command back to the device
worked flawlessly. It was incredibly rewarding to see the entire stack function as a
cohesive product. By bringing together the custom FPGA hardware, the precise waveform
encoder, and the ESP32 wireless bridge, the project successfully bridges the gap between
legacy hardware and modern networks — allowing us to control otherwise "dumb"
IR-only devices conveniently from our smartphones.

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
