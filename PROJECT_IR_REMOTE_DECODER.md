# 📡 IR Remote Decoder - Projektbeschreibung

**Ein dedizierter ASIC zur Dekodierung von Infrarot-Fernbedienungen (NEC-Protokoll)**

---

## 📋 Projekt-Übersicht

### Kurzbeschreibung
Ein Hardware-Decoder für Standard-Infrarot-Fernbedienungen, der das **NEC-Protokoll** in Echtzeit dekodiert und die empfangenen Befehle über UART an einen PC/Terminal ausgibt. Das Projekt demonstriert präzise Timing-Kontrolle, Protokoll-Dekodierung und State Machine Design in Hardware.

### Projektziele
- ✅ Verständnis von **Timing-kritischen Systemen** (µs-Präzision)
- ✅ **Protokoll-Dekodierung** in Hardware (NEC IR-Protokoll)
- ✅ **Finite State Machines** für Datenempfang
- ✅ **Edge Detection** und **Pulse-Width-Messung**
- ✅ **UART-Protokoll** für serielle Kommunikation
- ✅ Test-Driven Development mit **CocoTB**
- ✅ Integration in **OpenLane/Librelane** ASIC-Flow

### Team-Größe & Dauer
- **Team:** 4 Personen
- **Dauer:** 10 Arbeitstage
- **Arbeitsweise:** Modular, parallele Entwicklung möglich

### Warum Hardware?
- ⚡ **Timing-Präzision:** Software (z.B. Arduino) hat ±10µs Jitter durch Interrupts
- ⚡ **Hardware:** Clock-genaue Messung (±0.1µs @ 10 MHz)
- ⚡ **Keine CPU-Last:** Dedizierte Logik, kein Polling nötig
- ⚡ **Parallel-Fähig:** Chip kann nebenbei andere Tasks ausführen
- ⚡ **Low Power:** Nur aktiv bei IR-Empfang (~2 mW)

---

## 🎯 Funktionale Spezifikation

### Hauptfunktionen

#### 1. NEC-Protokoll Dekodierung
Das **NEC IR-Protokoll** ist der Standard für die meisten TV-Fernbedienungen (Samsung, LG, Panasonic, etc.).

**Frame-Struktur:**
```
┌────────────┬────────────┬──────────────────────────┬──────┐
│ AGC Burst  │   Space    │      Data (32 Bit)       │ Stop │
│   9 ms     │   4.5 ms   │  Address + Command       │560µs │
└────────────┴────────────┴──────────────────────────┴──────┘
```

**Bit-Encoding:**
```
Logische '0':  560µs Burst + 560µs Space  = 1.12 ms
Logische '1':  560µs Burst + 1.69ms Space = 2.25 ms
```

**Daten-Format (32 Bit):**
```
┌──────────┬──────────┬──────────┬──────────┐
│ Address  │ ~Address │ Command  │ ~Command │
│  8 Bit   │  8 Bit   │  8 Bit   │  8 Bit   │
└──────────┴──────────┴──────────┴──────────┘
```

#### 2. Pulse-Width Messung
- **Timing-Auflösung:** 0.1 µs (@ 10 MHz Clock)
- **Messbereich:** 100 µs - 10 ms
- **Toleranz:** ±20% (robust gegen billige Fernbedienungen)

#### 3. Fehler-Erkennung
- **Checksum-Validierung:** Address und Command werden invertiert übertragen
- **Timeout-Detection:** Ungültige Pulse werden erkannt
- **Glitch-Filtering:** Kurze Störimpulse (<100µs) werden ignoriert

#### 4. UART Output
- **Baudrate:** 9600 bps
- **Format:** 8N1 (8 data bits, no parity, 1 stop bit)
- **Ausgabe-Format:**
  ```
  Address: 0x00, Command: 0x45
  ```

#### 5. LED-Feedback
- 🟢 **Grün:** Gültiger Frame empfangen
- 🔴 **Rot:** Fehler (Checksum falsch, Timeout)
- 🟡 **Gelb:** Empfang aktiv (während Dekodierung)

---

## 🏗️ System-Architektur

### Block-Diagramm

```
┌──────────────────────────────────────────────────────┐
│              IR Remote Decoder Chip                   │
├──────────────────────────────────────────────────────┤
│                                                       │
│  IR_IN ──> [Synchronizer] ──> [Edge Detector]       │
│                                      │                │
│                                      ↓                │
│                          ┌───────────────────────┐   │
│                          │  Pulse Width Timer    │   │
│                          │  (16-bit Counter)     │   │
│                          └───────────┬───────────┘   │
│                                      │                │
│                                      ↓                │
│                          ┌───────────────────────┐   │
│                          │  NEC Protocol FSM     │   │
│                          │  - IDLE               │   │
│                          │  - LEADER             │   │
│                          │  - SPACE              │   │
│                          │  - DATA (32 bits)     │   │
│                          │  - VALIDATE           │   │
│                          └───────────┬───────────┘   │
│                                      │                │
│                                      ↓                │
│                          ┌───────────────────────┐   │
│                          │  Data Register        │   │
│                          │  (32-bit Shift Reg)   │   │
│                          └───────────┬───────────┘   │
│                                      │                │
│                                      ↓                │
│                          ┌───────────────────────┐   │
│                          │  Checksum Validator   │   │
│                          └───────────┬───────────┘   │
│                                      │                │
│                                      ↓                │
│  UART_TX <───────────────┴──────────────────────────┤
│  LED_STATUS <──── (Visual Feedback)                  │
└──────────────────────────────────────────────────────┘
```

### Externe Hardware (Minimal!)

```
┌─────────────────────────────────────┐
│  TSOP38238 IR-Empfänger             │
│                                      │
│  Kosten: ~0.50€                     │
│  Pinout:                            │
│    1. GND                            │
│    2. VCC (+3.3V)                   │
│    3. OUT → Zu Chip-Pin (ir_in)     │
│                                      │
│  Funktion:                          │
│  - Empfängt 38 kHz moduliertes IR   │
│  - Filtert Umgebungslicht           │
│  - Demoduliert Carrier              │
│  - Gibt sauberes Digital-Signal aus │
└─────────────────────────────────────┘
```

**Wichtig:** Der TSOP38238 macht die analoge Arbeit! Dein Chip bekommt nur noch digitale Pulse.

### Pin-Belegung

```
Inputs:
  - clk_PAD          : System Clock (10 MHz)
  - rst_n_PAD        : Active-low Reset
  - ir_in_PAD        : IR input from TSOP38238

Outputs:
  - uart_tx_PAD      : UART transmit (decoded data)
  - led_valid_PAD    : Green LED (valid frame)
  - led_error_PAD    : Red LED (error)
  - led_active_PAD   : Yellow LED (receiving)

Power:
  - VDD, VSS         : Core power (1.2V)
  - IOVDD, IOVSS     : I/O power (3.3V)

Total: ~10 I/O Pads
```

---

## 👥 Team-Aufgaben & Rollenzuteilung

### Person 1: Pulse Width Timer & Edge Detection
**Verantwortlich für:**
- `edge_detector.sv` - Synchronizer & Flanken-Detektion
- `pulse_timer.sv` - Präzise Pulse-Width-Messung
- Tests: `test_edge_detector.py`, `test_pulse_timer.py`

**Deliverables:**
- Metastability-sichere Synchronisation des IR-Eingangs
- Detektion von steigenden/fallenden Flanken
- 16-bit Timer für Pulse-Width-Messung (0.1µs Auflösung)
- Timeout-Detektion (>10ms = ungültiger Puls)

**Technische Details:**
- 2-Stage Synchronizer gegen Metastabilität
- Edge-Detection mit Flip-Flop-Register
- Counter mit Auto-Reset bei Flanken

---

### Person 2: NEC Protocol Decoder (State Machine)
**Verantwortlich für:**
- `nec_decoder.sv` - Protokoll-FSM
- `bit_decoder.sv` - Logik 0/1 Dekodierung
- Tests: `test_nec_decoder.py`, `test_bit_decoder.py`

**Deliverables:**
- State Machine mit 5 Zuständen:
  - IDLE: Warte auf AGC Burst
  - LEADER: 9ms Burst erkannt
  - SPACE: 4.5ms Space erkannt
  - DATA: 32 Bits empfangen
  - VALIDATE: Checksum prüfen
- 32-bit Shift-Register für Datenempfang
- Timing-Validation (±20% Toleranz)

**State-Diagramm:**
```
    IDLE
     │
     │ (9ms Burst)
     ↓
   LEADER
     │
     │ (4.5ms Space)
     ↓
   SPACE
     │
     │ (Start Bit 0)
     ↓
    DATA ──┐
     ↑     │
     └─────┘ (32 Bits)
     │
     │ (32 Bits komplett)
     ↓
  VALIDATE
     │
     │ (Checksum OK)
     ↓
   IDLE (data_valid = 1)
```

---

### Person 3: UART Transmitter & Output Formatter
**Verantwortlich für:**
- `uart_tx.sv` - UART Transmitter
- `output_formatter.sv` - ASCII-Formatierung
- Tests: `test_uart_tx.py`, `test_output_formatter.py`

**Deliverables:**
- UART-Transmitter (9600 Baud, 8N1)
- Baud-Rate-Generator (10 MHz / 9600 = ~1042 Takte)
- ASCII-String-Formatierung:
  ```
  "Addr: 0x00, Cmd: 0x45\n"
  ```
- Byte-to-Hex-Konverter

**UART-Timing:**
```
@ 9600 Baud: 1 Bit = 104.2 µs
Frame-Zeit: ~1.04 ms pro Byte
```

---

### Person 4: Integration, Testing & PAD-Wrapper
**Verantwortlich für:**
- `ir_decoder_top.sv` - Top-Level Integration
- `test_ir_decoder_integration.py` - End-to-End Tests
- PAD-Instanziierung (sg13g2_IOPadIn/Out)
- Gesamte Projekt-Dokumentation

**Deliverables:**
- Vollständige Chip-Integration
- PAD-Wrapper für alle I/O-Pins
- Umfassende Integrationstests:
  - Test mit simulierten Fernbedienungs-Signalen
  - Verschiedene Button-Codes
  - Error-Cases (Checksumfehler, Timeout)
- Test-Coverage-Report (>95%)
- Waveform-Dokumentation

---

## 📅 10-Tage-Projektplan

### **Tag 1-2: Setup & Modul-Design**

#### Tag 1: Kickoff & Architektur
**Morning:**
- [ ] **Alle:** Projekt-Kickoff-Meeting (1h)
  - Architektur-Review
  - NEC-Protokoll-Walkthrough
  - Git-Repository Setup
- [ ] **Alle:** Aufgabenverteilung & Verantwortlichkeiten klären

**Afternoon:**
- [ ] **Person 1:** Spezifikation Edge Detector & Pulse Timer
- [ ] **Person 2:** State-Diagramm für NEC-Decoder zeichnen
- [ ] **Person 3:** UART-Timing berechnen & Spec schreiben
- [ ] **Person 4:** Top-Level Interface definieren, Projektstruktur erstellen

#### Tag 2: Erste Implementierung
- [ ] **Person 1:** `edge_detector.sv` + `pulse_timer.sv` (Basis)
- [ ] **Person 2:** `nec_decoder.sv` (FSM-Struktur, noch ohne Logik)
- [ ] **Person 3:** `uart_tx.sv` (Baud-Rate-Generator + Start-Bit)
- [ ] **Person 4:** Makefile, config.yaml, CI/CD-Setup

**End-of-Day:** Code-Review #1 (Interfaces prüfen)

---

### **Tag 3-5: Core-Module & Unit-Tests**

#### Tag 3: Module fertigstellen
- [ ] **Person 1:** 
  - Edge-Detection-Logik komplett
  - Pulse-Timer mit Auto-Reset
  - Timeout-Detektion
- [ ] **Person 2:**
  - FSM-Logik komplett (alle 5 States)
  - Bit-Dekodierung (0/1 Unterscheidung)
  - Shift-Register für 32 Bits
- [ ] **Person 3:**
  - UART-Transmitter komplett
  - Output-Formatter (Hex-Konvertierung)
- [ ] **Person 4:**
  - PAD-Wrapper-Module vorbereiten
  - Test-Infrastruktur (CocoTB-Helpers)

#### Tag 4: Unit-Tests schreiben
- [ ] **Person 1:** `test_edge_detector.py` + `test_pulse_timer.py`
  - Test: Flanken-Erkennung
  - Test: Pulse-Width-Messung (100µs - 10ms)
  - Test: Timeout-Detektion
- [ ] **Person 2:** `test_nec_decoder.py`
  - Test: AGC Burst Recognition
  - Test: Space Detection
  - Test: Bit 0/1 Dekodierung
  - Test: Checksum-Validierung
- [ ] **Person 3:** `test_uart_tx.py` + `test_output_formatter.py`
  - Test: Baudrate (9600 Baud)
  - Test: Start/Stop-Bits
  - Test: ASCII-Formatierung
- [ ] **Person 4:** `test_helpers.py` (Shared Test-Utilities)

#### Tag 5: Debugging & Verbesserungen
- [ ] **Alle:** Bugfixes aus Unit-Tests
- [ ] **Alle:** Peer-Review (jeder schaut Code eines anderen an)
- [ ] **Person 1+2:** Interface-Integration testen
- [ ] **Person 3+4:** UART-Output-Logik integrieren

**Milestone:** Alle Module funktionieren einzeln! ✅

---

### **Tag 6-7: Integration & System-Tests**

#### Tag 6: Integration
**Morning:**
- [ ] **Person 4 (Lead):** Top-Level-Integration
  - Verbinde Pulse-Timer → NEC-Decoder
  - Verbinde NEC-Decoder → Output-Formatter
  - Verbinde Output-Formatter → UART-TX

**Afternoon:**
- [ ] **Person 1+2:** Interface-Debugging (Timing-Issues?)
- [ ] **Person 3+4:** UART-Output testen
- [ ] **Alle:** Erste End-to-End-Simulation

#### Tag 7: End-to-End Tests & Waveform-Analyse
- [ ] **Person 4 (Lead):** `test_ir_decoder_integration.py`
  - Test: Samsung TV Power Button (0x00, 0x45)
  - Test: LG TV Volume+ (0x01, 0x02)
  - Test: Alle 20 Standard-Buttons einer Fernbedienung
  - Test: Checksum-Fehler → Error-LED
  - Test: Timeout → Reset
  - Test: Repeat-Code (Button gedrückt halten)

- [ ] **Alle:** Waveform-Analyse in GTKWave
  - Timing-Diagramme dokumentieren
  - Screenshots für Präsentation

**Milestone:** System funktioniert komplett! ✅

---

### **Tag 8-9: PAD-Integration & ASIC-Flow**

#### Tag 8: Chip-Level Integration
- [ ] **Person 4:** PAD-Instanziierung
  - `sg13g2_IOPadIn` für ir_in, rst_n, clk
  - `sg13g2_IOPadOut` für uart_tx, LEDs
  - Power-PADs (IOVDD, IOVSS, VDD, VSS)
  
- [ ] **Person 1:** Pin-Placement-Constraints
  - `.pcf` Datei erstellen
  - IR-Input auf optimalen Pin
  
- [ ] **Person 2:** Clock-Constraints
  - SDC-File für 10 MHz Clock
  - Setup/Hold-Time Constraints
  
- [ ] **Person 3:** I/O-Timing
  - UART-TX Output-Delay
  - IR-Input Synchronizer-Delay

**Test:** Chip-Level-Simulation mit PADs

#### Tag 9: OpenLane/Librelane Flow
**Morning:**
- [ ] **Alle:** `config.yaml` konfigurieren
  ```yaml
  DESIGN_NAME: ir_decoder_top
  VERILOG_FILES:
    - src/edge_detector.sv
    - src/pulse_timer.sv
    - src/nec_decoder.sv
    - src/uart_tx.sv
    - src/output_formatter.sv
    - src/ir_decoder_top.sv
  CLOCK_PERIOD: 100  # 10 MHz
  CLOCK_PORT: clk_PAD
  ```

**Afternoon:**
- [ ] **Person 4:** Synthesis-Run
  ```bash
  make librelane
  ```
- [ ] **Alle:** Fehler beheben (Syntax, Linting)
- [ ] **Alle:** Place & Route optimieren
- [ ] **Alle:** DRC/LVS-Checks

**Iterations:** 2-3 Synthesis-Runs erwarten

---

### **Tag 10: Dokumentation & Präsentation**

#### Morning: Finalisierung
- [ ] **Person 1:** Dokumentation Edge-Detector & Pulse-Timer
  - README.md mit Timing-Diagrammen
  - Inline-Comments vervollständigen
  
- [ ] **Person 2:** Dokumentation NEC-Decoder
  - State-Diagramm in README
  - Protokoll-Spezifikation
  
- [ ] **Person 3:** Dokumentation UART & Output
  - Baudrate-Berechnung dokumentieren
  - Output-Format beschreiben
  
- [ ] **Person 4:** Gesamt-Dokumentation
  - Top-Level README
  - Test-Coverage-Report generieren
  - Synthesis-Results zusammenfassen

#### Afternoon: Präsentation vorbereiten
- [ ] **Alle:** Demo-Script schreiben
  ```python
  # demo.py
  # Simuliere verschiedene Fernbedienungs-Buttons
  # Zeige UART-Output im Terminal
  # Zeige Waveforms in GTKWave
  ```

- [ ] **Alle:** Präsentations-Slides erstellen (15 min)
  1. Projekt-Übersicht
  2. NEC-Protokoll Erklärung
  3. Architektur & Module
  4. Live-Demo (Simulation)
  5. Waveform-Analyse
  6. Synthesis-Results
  7. Lessons Learned

- [ ] **Alle:** Präsentation proben (2× Durchlauf)

---

## 🧪 Test-Strategie

### Unit-Tests (Tag 4)

#### 1. Edge Detector & Pulse Timer

```python
# test_pulse_timer.py
@cocotb.test()
async def test_measure_short_pulse():
    """Teste Messung eines kurzen Pulses (560µs)."""
    dut.ir_in.value = 0  # IR aktiv (LOW)
    await Timer(560, units='us')
    dut.ir_in.value = 1  # IR inaktiv (HIGH)
    await Timer(1, units='us')
    
    # Erwarte: 560µs ±20% = 448-672µs
    assert 448 <= dut.pulse_width.value <= 672
    assert dut.pulse_valid.value == 1

@cocotb.test()
async def test_measure_long_pulse():
    """Teste Messung eines langen Pulses (1690µs)."""
    dut.ir_in.value = 0
    await Timer(1690, units='us')
    dut.ir_in.value = 1
    await Timer(1, units='us')
    
    assert 1352 <= dut.pulse_width.value <= 2028  # ±20%
    assert dut.pulse_valid.value == 1

@cocotb.test()
async def test_timeout_detection():
    """Teste Timeout bei >10ms Puls."""
    dut.ir_in.value = 0
    await Timer(11, units='ms')  # Zu lang!
    
    assert dut.timeout.value == 1
```

#### 2. NEC Decoder

```python
# test_nec_decoder.py

async def send_nec_bit(dut, bit):
    """Helper: Sende ein NEC-codiertes Bit."""
    dut.ir_in.value = 0
    await Timer(560, units='us')  # Burst
    dut.ir_in.value = 1
    if bit == 0:
        await Timer(560, units='us')   # Short space
    else:
        await Timer(1690, units='us')  # Long space

async def send_nec_frame(dut, address, command):
    """Helper: Sende komplettes NEC-Frame."""
    # AGC Burst
    dut.ir_in.value = 0
    await Timer(9000, units='us')
    dut.ir_in.value = 1
    await Timer(4500, units='us')
    
    # Address (8 bit LSB first)
    for i in range(8):
        bit = (address >> i) & 1
        await send_nec_bit(dut, bit)
    
    # ~Address
    for i in range(8):
        bit = ((~address) >> i) & 1
        await send_nec_bit(dut, bit)
    
    # Command
    for i in range(8):
        bit = (command >> i) & 1
        await send_nec_bit(dut, bit)
    
    # ~Command
    for i in range(8):
        bit = ((~command) >> i) & 1
        await send_nec_bit(dut, bit)
    
    # Stop bit
    dut.ir_in.value = 0
    await Timer(560, units='us')
    dut.ir_in.value = 1

@cocotb.test()
async def test_decode_power_button():
    """Test: Dekodiere TV Power Button."""
    clock = Clock(dut.clk, 100, units='ns')  # 10 MHz
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    await Timer(1, units='us')
    dut.rst_n.value = 1
    
    # Samsung TV Power = Address 0x00, Command 0x45
    await send_nec_frame(dut, address=0x00, command=0x45)
    
    await Timer(10, units='us')
    
    assert dut.address.value == 0x00
    assert dut.command.value == 0x45
    assert dut.data_valid.value == 1
    assert dut.decode_error.value == 0

@cocotb.test()
async def test_invalid_checksum():
    """Test: Fehlerhafte Checksum → Error."""
    # Sende absichtlich kaputtes Frame
    # (Address != ~Address_inverse)
    # ... (manuell konstruieren)
    
    assert dut.decode_error.value == 1
    assert dut.data_valid.value == 0
```

#### 3. UART Transmitter

```python
# test_uart_tx.py

async def uart_receive_byte(dut):
    """Helper: Empfange ein Byte vom UART."""
    # Warte auf Start-Bit (falling edge)
    while dut.tx.value == 1:
        await RisingEdge(dut.clk)
    
    await Timer(104.2, units='us')  # Halbes Bit
    
    # Lese 8 Data-Bits
    byte = 0
    for i in range(8):
        await Timer(104.2, units='us')
        if dut.tx.value == 1:
            byte |= (1 << i)
    
    # Stop-Bit
    await Timer(104.2, units='us')
    assert dut.tx.value == 1  # Stop bit = HIGH
    
    return byte

@cocotb.test()
async def test_send_hello():
    """Test: Sende 'Hello' via UART."""
    clock = Clock(dut.clk, 100, units='ns')
    cocotb.start_soon(clock.start())
    
    # Sende "Hello"
    for char in "Hello":
        dut.data.value = ord(char)
        dut.send.value = 1
        await RisingEdge(dut.clk)
        dut.send.value = 0
        
        # Warte bis gesendet
        while dut.ready.value == 0:
            await RisingEdge(dut.clk)
    
    # Empfange und prüfe
    received = ""
    for _ in range(5):
        byte = await uart_receive_byte(dut)
        received += chr(byte)
    
    assert received == "Hello"
```

### Integration-Tests (Tag 7)

```python
# test_ir_decoder_integration.py

@cocotb.test()
async def test_full_tv_remote_sequence():
    """Test: Komplette TV-Fernbedienungs-Simulation."""
    clock = Clock(dut.clk, 100, units='ns')
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    await Timer(1, units='us')
    dut.rst_n.value = 1
    
    # Simuliere 10 verschiedene Tasten
    buttons = {
        0x45: "Power",
        0x46: "Mute",
        0x47: "Source",
        0x40: "Vol+",
        0x41: "Vol-",
        0x42: "CH+",
        0x43: "CH-",
        0x44: "Menu",
        0x48: "OK",
        0x49: "Back"
    }
    
    for code, name in buttons.items():
        dut._log.info(f"Testing button: {name}")
        
        # Sende Frame
        await send_nec_frame(dut, address=0x00, command=code)
        
        # Warte auf Dekodierung
        await Timer(100, units='us')
        
        # Prüfe Output
        assert dut.command.value == code, f"Button {name} falsch dekodiert"
        assert dut.data_valid.value == 1
        assert dut.led_valid.value == 1  # Grüne LED
        
        # Warte zwischen Buttons
        await Timer(200, units='ms')

@cocotb.test()
async def test_different_tv_brands():
    """Test: Verschiedene TV-Hersteller (unterschiedliche Addresses)."""
    brands = {
        0x00: "Samsung",
        0x01: "LG",
        0x04: "Sony",
        0x08: "Panasonic"
    }
    
    for addr, brand in brands.items():
        await send_nec_frame(dut, address=addr, command=0x45)
        assert dut.address.value == addr, f"{brand} Address falsch"

@cocotb.test()
async def test_button_hold_repeat_code():
    """Test: Taste gedrückt halten (Repeat-Codes)."""
    # Erstes Frame (normal)
    await send_nec_frame(dut, address=0x00, command=0x45)
    
    # Repeat-Codes (alle 108ms)
    for _ in range(10):
        await Timer(108, units='ms')
        # Repeat = 9ms Burst + 2.25ms Space + 560µs Stop
        dut.ir_in.value = 0
        await Timer(9000, units='us')
        dut.ir_in.value = 1
        await Timer(2250, units='us')
        dut.ir_in.value = 0
        await Timer(560, units='us')
        dut.ir_in.value = 1
        
        # Command sollte gleich bleiben
        assert dut.command.value == 0x45

@cocotb.test()
async def test_noise_rejection():
    """Test: Kurze Störimpulse werden ignoriert."""
    # Sende viele kurze Glitches
    for _ in range(20):
        dut.ir_in.value = 0
        await Timer(50, units='us')  # Zu kurz!
        dut.ir_in.value = 1
        await Timer(100, units='us')
    
    # Kein Fehler, kein Data-Valid
    assert dut.decode_error.value == 0
    assert dut.data_valid.value == 0
```

### Coverage-Ziele

- **Line Coverage:** > 95%
- **Branch Coverage:** > 90%
- **FSM State Coverage:** 100% (alle 5 States besucht)
- **FSM Transition Coverage:** > 95% (alle gültigen Übergänge)

---

## 📐 Hardware-Spezifikationen

### Timing-Requirements

| Parameter | Min | Typical | Max | Unit | Toleranz |
|-----------|-----|---------|-----|------|----------|
| System Clock | 9.5 | 10.0 | 10.5 | MHz | ±5% |
| AGC Burst | 8.5 | 9.0 | 9.5 | ms | ±5% |
| Space | 4.0 | 4.5 | 5.0 | ms | ±10% |
| Bit Burst | 500 | 560 | 620 | µs | ±10% |
| Logical '0' Space | 450 | 560 | 670 | µs | ±20% |
| Logical '1' Space | 1350 | 1690 | 2030 | µs | ±20% |
| Repeat Burst | 8.5 | 9.0 | 9.5 | ms | ±5% |
| Repeat Space | 2.0 | 2.25 | 2.5 | ms | ±10% |
| UART Baud Rate | 9400 | 9600 | 9800 | bps | ±2% |

### Power & Area Estimates

- **Core Area:** ~0.03 mm² (30,000 µm²)
- **Total Die Area:** 1.2 mm × 1.2 mm = 1.44 mm²
- **Gate Count:** ~1,500 - 2,500 gates
  - Pulse Timer: ~300 gates (16-bit counter)
  - NEC Decoder: ~800 gates (FSM + Shift-Reg)
  - UART TX: ~400 gates
  - Output Formatter: ~500 gates
- **Power (estimated):** < 3 mW @ 10 MHz
  - Idle: ~0.5 mW
  - Active (receiving): ~3 mW
- **Technology:** IHP SG13G2 (130nm)

---

## 🛠️ Entwicklungs-Tools & Setup

### Erforderliche Software

```bash
# HDL & Simulation
- Icarus Verilog (iverilog)     # HDL Simulator
- Verilator                     # Optional: Faster sim
- GTKWave                       # Waveform Viewer

# Testing
- Python 3.10+
- CocoTB 2.0+                   # Testbench Framework
- pytest                        # Test Runner
- Coverage.py                   # Coverage Analysis

# ASIC Flow
- Librelane/OpenLane            # Synthesis & P&R
- Yosys                         # Synthesis
- Magic                         # Layout Tool
- KLayout                       # GDS Viewer

# Version Control & CI
- Git
- GitHub (+ GitHub Actions)
```

### Installation (Ubuntu/Debian)

```bash
# System-Pakete
sudo apt update
sudo apt install -y \
    iverilog \
    gtkwave \
    verilator \
    python3-pip \
    git

# Python-Pakete
pip3 install --upgrade \
    cocotb \
    pytest \
    coverage

# ASIC-Tools (falls nicht vorhanden)
# Siehe: https://github.com/efabless/openlane
```

### Dateistruktur

```
firstdesign/
└── M5_IR_Decoder/
    ├── README.md                     # Modul-Dokumentation
    ├── Makefile                      # Build & Test Automation
    ├── config.yaml                   # Librelane Configuration
    ├── constraints/
    │   ├── pins.pcf                 # Pin-Placement
    │   └── timing.sdc               # Timing-Constraints
    ├── src/
    │   ├── ir_decoder_top.sv        # Top-Level (Person 4)
    │   ├── edge_detector.sv         # Person 1
    │   ├── pulse_timer.sv           # Person 1
    │   ├── nec_decoder.sv           # Person 2
    │   ├── bit_decoder.sv           # Person 2
    │   ├── uart_tx.sv               # Person 3
    │   └── output_formatter.sv      # Person 3
    ├── test/
    │   ├── test_helpers.py          # Shared utilities
    │   ├── test_edge_detector.py    # Person 1
    │   ├── test_pulse_timer.py      # Person 1
    │   ├── test_nec_decoder.py      # Person 2
    │   ├── test_uart_tx.py          # Person 3
    │   └── test_integration.py      # Person 4
    ├── sim_build/                   # Simulation Output
    │   └── *.fst                    # Waveforms
    ├── runs/                        # OpenLane Runs
    └── docs/
        ├── nec_protocol.md          # Protokoll-Spec
        ├── timing_diagrams/         # Timing-Diagramme
        └── waveforms/               # Screenshots
```

---

## 📊 Erfolgs-Kriterien

### Muss-Kriterien (Must-Have)
- ✅ Alle 4 Module funktionieren einzeln (Unit-Tests bestanden)
- ✅ NEC-Protokoll wird korrekt dekodiert
- ✅ Checksum-Validierung funktioniert
- ✅ UART gibt korrekte ASCII-Strings aus
- ✅ Mindestens 10 verschiedene Button-Codes getestet
- ✅ Integration erfolgreich (End-to-End-Tests bestanden)
- ✅ Synthesis erfolgreich (keine kritischen Errors)
- ✅ Test-Coverage > 90%

### Soll-Kriterien (Should-Have)
- ✅ Timing-Toleranz ±20% funktioniert
- ✅ Repeat-Codes (Button-Hold) werden erkannt
- ✅ Fehler-Handling (Timeout, Checksum) funktioniert
- ✅ LED-Feedback funktioniert
- ✅ Verschiedene Fernbedienungen getestet (simuliert)
- ✅ Timing-Constraints erfüllt (keine Violations)
- ✅ DRC/LVS clean

### Kann-Kriterien (Nice-to-Have)
- 🎁 GDS-File generiert (Tape-Out Ready)
- 🎁 Power-Analyse durchgeführt
- 🎁 Formale Verifikation (SymbiYosys)
- 🎁 Multi-Protokoll-Support (RC5, Sony SIRC)
- 🎁 IR-Transmitter (Chip kann auch senden!)

---

## 🚀 Erweiterungs-Ideen (nach Projektende)

### Level 1: More Protocols
- **RC5 Protocol** (Philips)
- **Sony SIRC** (12/15/20 bit)
- **Samsung Protocol** (32-bit variant)
- **Auto-Detection:** Chip erkennt Protokoll automatisch

### Level 2: IR Transmitter
- **38 kHz Carrier-Generator**
- **Modulator** für Burst-Erzeugung
- **NEC-Frame-Generator**
- Use-Case: Universelle Fernbedienung

### Level 3: Learning Mode
- **Capture Mode:** Beliebige IR-Codes speichern
- **Replay Mode:** Gespeicherte Codes wieder senden
- **RAM-basierter Speicher** (statt ROM)

### Level 4: Smart-Home-Integration
- **I2C/SPI-Interface** statt UART
- **Interrupt-Output** bei Button-Press
- **Command-Mapping:** IR → GPIO-Outputs (Relais-Steuerung)

---

## 📚 Lernziele & Kompetenzen

### Technische Kompetenzen
- ✅ **Timing-kritische Systeme** (µs-Präzision)
- ✅ **Protokoll-Dekodierung** (Bitstream → Daten)
- ✅ **State Machine Design** (komplexe FSM)
- ✅ **Edge Detection & Synchronisation** (Metastabilität)
- ✅ **Serial Communication** (UART)
- ✅ **Test-Driven Development** (CocoTB)
- ✅ **Waveform-Analyse** (Debugging)

### ASIC-Spezifisch
- ✅ **RTL-Design** (SystemVerilog Best Practices)
- ✅ **Synthesis** (Yosys, Area/Speed Trade-offs)
- ✅ **Timing-Constraints** (SDC-Files)
- ✅ **Place & Route** (OpenROAD)
- ✅ **DRC/LVS** (Layout-Verifikation)
- ✅ **Power-Analysis** (estimation)

### Soft Skills
- ✅ **Team-Arbeit** (4 Personen, klare Schnittstellen)
- ✅ **Projekt-Management** (10-Tage-Zeitplan einhalten)
- ✅ **Code-Review** (Peer-Review-Prozess)
- ✅ **Dokumentation** (README, Inline-Comments)
- ✅ **Präsentation** (technische Demo)

---

## 🎓 Bewertungs-Rubriken (Vorschlag)

### Code-Qualität (25%)
- **Lesbarkeit:** Sauberer, strukturierter Code
- **Kommentare:** Inline-Dokumentation vorhanden
- **Modularität:** Klare Module, wiederverwendbar
- **Best Practices:** SystemVerilog Coding-Standards

### Funktionalität (30%)
- **Muss-Kriterien:** Alle erfüllt
- **Robustheit:** Edge-Cases behandelt
- **Fehler-Handling:** Timeout, Checksum-Fehler
- **Performance:** Timing-Requirements erfüllt

### Testing & Verifikation (25%)
- **Unit-Tests:** Alle Module getestet
- **Integration-Tests:** End-to-End-Szenarien
- **Coverage:** > 90%
- **Waveform-Analyse:** Dokumentiert

### ASIC-Flow (10%)
- **Synthesis:** Erfolgreich, keine Errors
- **Timing:** Setup/Hold-Time erfüllt
- **DRC/LVS:** Clean (wenn durchgeführt)

### Dokumentation & Präsentation (10%)
- **README:** Vollständig, verständlich
- **Inline-Docs:** Gut kommentiert
- **Demo:** Funktioniert, gut erklärt
- **Team-Arbeit:** Gleichmäßige Beiträge

---

## 📞 Support & Ressourcen

### Offizielle Dokumentation
- [NEC IR Protocol Spec](http://www.sbprojects.net/knowledge/ir/nec.php)
- [CocoTB Docs](https://docs.cocotb.org/)
- [SystemVerilog IEEE 1800-2017](https://ieeexplore.ieee.org/document/8299595)
- [Librelane/OpenLane](https://openlane.readthedocs.io/)

### Beispiel-Code in diesem Repo
- `firstdesign/M1_Controller/` - State Machine Beispiel
- `firstdesign/M2_Adder/` - Arithmetic Logic
- `firstdesign/M4_7segment/` - Output-Module

### Hardware-Datenblätter
- [TSOP38238 Datasheet](https://www.vishay.com/docs/82491/tsop382.pdf)
- [IHP SG13G2 PDK](https://github.com/IHP-GmbH/IHP-Open-PDK)

### Community & Support
- **GitHub Issues:** Für Bugs & Feature-Requests
- **Daily Standup:** 15 min/Tag (Team-Sync)
- **Code-Review:** Pull-Request-basiert
- **Slack/Discord:** Team-Kanal für schnelle Fragen

---

## ✅ Projekt-Checkliste

### Setup (Tag 1-2)
- [ ] Git-Repository geclont
- [ ] Alle Tools installiert (iverilog, cocotb, etc.)
- [ ] Projektstruktur erstellt (`M5_IR_Decoder/`)
- [ ] Team-Rollen zugewiesen
- [ ] NEC-Protokoll verstanden

### Implementation (Tag 3-5)
- [ ] Alle Module implementiert (4× src/*.sv)
- [ ] Alle Unit-Tests geschrieben (6× test/*.py)
- [ ] Alle Unit-Tests bestanden
- [ ] Code-Reviews durchgeführt

### Integration (Tag 6-7)
- [ ] Top-Level-Integration komplett
- [ ] End-to-End-Tests bestanden
- [ ] Waveforms analysiert & dokumentiert
- [ ] Bugs gefixt

### ASIC-Flow (Tag 8-9)
- [ ] PAD-Integration durchgeführt
- [ ] config.yaml konfiguriert
- [ ] Synthesis erfolgreich
- [ ] Timing-Constraints erfüllt
- [ ] DRC/LVS clean (optional)

### Finalisierung (Tag 10)
- [ ] README.md vollständig
- [ ] Alle Module dokumentiert
- [ ] Test-Coverage-Report generiert
- [ ] Demo-Script funktioniert
- [ ] Präsentation vorbereitet
- [ ] 15-min Präsentation geprobt

---

## 🎉 Projekt-Erfolg!

Nach 10 Tagen habt ihr:
- ✅ Einen **funktionsfähigen IR-Remote Decoder** entwickelt
- ✅ **NEC-Protokoll** in Hardware implementiert
- ✅ **Timing-kritische Systeme** verstanden (µs-Präzision)
- ✅ **State Machines** für Protokoll-Dekodierung gemeistert
- ✅ **Team-basierte ASIC-Entwicklung** durchgeführt
- ✅ **Test-Driven Development** praktiziert
- ✅ Den **kompletten ASIC-Flow** durchlaufen
- ✅ Ein **Demo-fähiges Projekt** erstellt

### Praktische Anwendungen:
- 📺 Universeller IR-Empfänger für Smart-Home
- 🎮 Custom-Controller für Retro-Gaming-Konsolen
- 🤖 Roboter-Fernsteuerung
- 🔬 Lern-Tool für Protokoll-Analyse

**Viel Erfolg! 🚀📡**

---

*Projekt erstellt am: 10. Februar 2026*  
*Letzte Aktualisierung: 10. Februar 2026*  
*Version: 1.0*
