# IR Recorder & Replay – Mini-Universalfernbedienung

Diese Erweiterung ergänzt das **IR Remote Decoder Projekt** um eine **Record-&-Replay-Funktion** für das NEC-Infrarotprotokoll.

Der FPGA kann damit:
- empfangene IR-Codes **aufzeichnen**,
- **im internen Block RAM (BRAM)** speichern,
- und später **wieder aussenden**.

Damit wird aus dem reinen Decoder eine **aktive Mini-Universalfernbedienung**.

---

## Features

- Aufnahme von **NEC-kompatiblen IR-Codes**
- Speicherung im **FPGA-internen Block RAM**
- Wiederholung (Replay) gespeicherter Codes per Knopfdruck
- Reiner Hardware-Ansatz (kein Softcore, kein externes RAM)
- Vollständig **simulier- und testbar** mit Cocotb
- Modularer Aufbau, sauber in das bestehende Projekt integriert

---

## Design-Philosophie

Es werden **keine Rohpulse oder Timings** gespeichert.  
Stattdessen speichert das System die **bereits dekodierten NEC-Daten**:

| Feld | Breite |
|---|---|
| Address | 16 Bit |
| Command | 8 Bit |
| Flags (z. B. Repeat/Valid) | 8 Bit |
| **Summe** | **32 Bit pro Code** |

Vorteile:
- sehr geringer Speicherbedarf
- robuste Reproduktion der IR-Signale
- klare Trennung zwischen Decoder, Speicher und Encoder

---

## Modulübersicht
```
IR_RX
↓
NECDecoder
↓
IR_Recorder ──► BRAM (IR_Storage)
↓
Buttons ──► Replay_FSM ──► NEC_Encoder ──► IR_TX ──► NPN-Transistor ──► IR_LED
```

### Module im Detail

| Modul | Beschreibung |
|---|---|
| `IR_Recorder` | Nimmt gültige NEC-Frames entgegen und schreibt sie in den BRAM |
| `ir_bram` | FPGA-interner Block RAM zur Speicherung der IR-Codes |
| `Replay_FSM` | Steuert das Abspielen gespeicherter Codes |
| `NEC_Encoder` | Erzeugt das NEC-Protokoll (Leader, Bits, Stop) |
| `IR_TX` | 38-kHz-Trägererzeugung und Modulation für die IR-LED über NPN-Treiberstufe |

---

##  Speicherorganisation (BRAM)

- Speicherung als 32-Bit-Worte
- Beispiel: 8 Speicherplätze (Slots)
```
Slot 0: { addr[15:0], cmd[7:0], flags[7:0] }
Slot 1: { ... }
...
Slot 7
```

Der BRAM wird per Inferenz vom Synthesizer erzeugt  
(`ram_style = "block"`).

---

## Bedienkonzept (MVP: 2 Buttons)

| Eingabe | Funktion |
|---|---|
| REC-Button | Letzten gültigen IR-Code in Slot 0 speichern |
| PLAY-Button | Slot 0 abspielen |

Für den ersten Stand wird nur **ein Slot (Slot 0)** genutzt.  
Das Konzept bleibt danach leicht erweiterbar (mehr Slots, Zähler, Anzeige).

---

## Tests

Die Erweiterung ist vollständig mit **Cocotb** testbar.

### Empfohlene Tests

1. **Record-Test**
   - Simulierter NEC-Frame
   - Record-Button aktiv
   - Prüfen des BRAM-Inhalts

2. **Replay-Test**
   - Vordefinierter Code im BRAM
   - Replay auslösen
   - Timing des NEC-Signals prüfen

3. **Closed-Loop-Test**

    Decode → Store → Replay → Decode

Der erneut dekodierte Code muss mit dem Original identisch sein.

---

## Implementierungsaufwand

Die Erweiterung ist bewusst so ausgelegt, dass sie in **ca. 2 Tagen** realisierbar ist:

**Tag 1**
- BRAM-Modul
- IR_Recorder
- NEC_Encoder
- Simulation der Timings

**Tag 2**
- Replay_FSM
- IR_TX
- Integration ins TopLevel
- Cocotb-Tests
- Dokumentation

---

## Voraussetzungen

- Funktionierender NECDecoder
- IR-Empfänger
- IR-LED (38 kHz) mit NPN-Transistor als Treiber (z. B. BC547 oder 2N2222)
- Taktbasis passend für µs-Timing
- Optional: Buttons oder Schalter

### Hardware-Hinweis (IR-Sendezweig)

Die IR-LED sollte nicht direkt vom FPGA-Pin getrieben werden, sondern über eine NPN-Treiberstufe:

- FPGA-`IR_TX` -> Basiswiderstand (z. B. 1 kOhm) -> Basis des NPN
- Emitter des NPN -> GND
- Kollektor des NPN -> Kathode der IR-LED
- Anode der IR-LED -> Vorwiderstand -> VCC

Damit sind höhere LED-Ströme möglich, ohne den FPGA-Ausgang zu überlasten.

---

## Hinweise & Erweiterungen

Mögliche Erweiterungen:
- Anzeige der gespeicherten Slots (OLED / 7-Segment)
- Mehr Speicherplätze
- Lern-/Overwrite-Modus
- Unterstützung weiterer IR-Protokolle

---

## Lizenz

Diese Erweiterung steht unter derselben Open-Source-Lizenz wie das Hauptprojekt.
Beiträge, Verbesserungen und Pull Requests sind willkommen.
