# SAM36 Replay Fix – Probleme und Loesungen

## Ausgangsproblem
Beim gleichen Samsung36-Button war die Ausgabe zwischen Original (Fernbedienung) und Replay unterschiedlich.
Typische Symptome waren vertauschte Felder in `A`/`C` (z. B. `A:8877 C:0F` vs. `A:300F C:88`), obwohl derselbe Button verwendet wurde.

## Ursache 1: Falsches Bit-Mapping fuer SAM36 im Replay
- Der Recorder speichert SAM36 in semantischer Struktur:
  - `frame_data[47:32] = addr16`
  - `frame_data[31:28] = id4`
  - `frame_data[27:20] = cmd8`
  - `frame_data[19:12] = ~cmd8`
- Der Encoder sendet aber in aufsteigendem `bit_idx` direkt `frame_data[bit_idx]`.
- Das vorherige Mapping hat die Felder in der falschen Reihenfolge fuer den Encoder umgebaut.

### Loesung
In `IRRecorder_Replay/Replay_FSM/src/ir_replay_fsm.sv` wurde die Funktion `map_sam36_frame_data(...)` korrigiert.
Neue Reihenfolge fuer den Encoder (LSB-first), damit der ausgesendete Frame dem empfangenen SAM36-Frame entspricht:
- `bits[7:0]   = ~cmd`
- `bits[15:8]  = cmd`
- `bits[19:16] = id`
- `bits[35:20] = addr`

## Ursache 2: Test-Erwartung lief mit alter Mapping-Logik
Der Replay-Test fuer SAM36 pruefte zuvor noch das alte, fehlerhafte Mapping.

### Loesung
In `IRRecorder_Replay/Replay_FSM/test/test_ir_replay.py` wurde `map_sam36_expected(...)` auf die korrigierte Bit-Reihenfolge angepasst.

## Zusaetzliche Verifikation
- Relevante Python-Tests erfolgreich:
  - `IRRecorder_Replay/Replay_FSM/test/test_ir_replay.py`
  - `IRRecorder_Replay/nec_encoder/test/test_nec_encoder.py`
- FPGA neu gebaut und programmiert (`build.tcl`, `program_arty.tcl`).
- Hardware-Verifikation durch Nutzer bestaetigt: Replay entspricht jetzt dem Original-Button.

## Geaenderte Dateien
- `IRRecorder_Replay/Replay_FSM/src/ir_replay_fsm.sv`
- `IRRecorder_Replay/Replay_FSM/test/test_ir_replay.py`
- `IRRecorder_Replay/Replay_FSM/SAM36_REPLAY_FIX.md`
