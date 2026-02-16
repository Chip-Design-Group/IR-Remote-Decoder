## Person A: Recorder + Storage
#### Dateien: 
Recorder/src/ir_recorder.sv, STORAGE_BRAM/src/ir_storage_bram.sv
#### Aufgabe: 
Aufzeichnen und Speichern (record_req, target_slot, mem_wr_*)
MVP: REC-Button schreibt in Slot 0
#### Lieferung: 
fertige Write-Path-Logik + Unit-Test Recorder/test/test_ir_recorder.py
## Person B: Replay-Steuerung
#### Dateien: 
Replay_FSM/src/ir_replay_fsm.sv
#### Aufgabe: 
Slot lesen, Daten entpacken, Encoder starten (mem_rd_*, enc_start)
MVP: PLAY-Button liest Slot 0 und startet Senden
#### Lieferung: 
fertige Replay-FSM + Unit-Test Replay_FSM/test/test_ir_replay.py
## Person C: Encoder + TX
#### Dateien: 
nec_encoder/src/nec_encoder.sv, TX/src/ir_tx.sv
#### Aufgabe: 
NEC-Timing-Sequenz + 38kHz-Ausgabe
#### Lieferung: 
funktionierende Sende-Kette + Timing-Checks (Waveform)
## Person D: Integration + Verifikation
#### Dateien: 
TopLevel/src/ir_recorder_replay_top.sv, TopLevel/test/test_ir_closed_loop.py, sim/*
#### Aufgabe: 
Module verdrahten, End-to-End-Test, Sim-Flow, Doku
MVP-Bedienung: genau zwei Buttons (REC/PLAY), vorerst nur Slot 0
#### Lieferung: 
make test/make sim nutzbar, Closed-Loop-Test grün, Architektur dokumentiert
