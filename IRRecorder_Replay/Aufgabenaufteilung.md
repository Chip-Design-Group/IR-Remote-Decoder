## Person A: Recorder + Storage
#### Dateien: 
modules/ir_recorder/src/ir_recorder.sv, modules/ir_storage_bram/src/ir_storage_bram.sv
#### Aufgabe: 
Aufzeichnen und Speichern (record_req, target_slot, mem_wr_*)
MVP: REC-Button schreibt in Slot 0
#### Lieferung: 
fertige Write-Path-Logik + Unit-Test modules/ir_recorder/test/test_ir_recorder.py
## Person B: Replay-Steuerung
#### Dateien: 
modules/ir_replay_fsm/src/ir_replay_fsm.sv
#### Aufgabe: 
Slot lesen, Daten entpacken, Encoder starten (mem_rd_*, enc_start)
MVP: PLAY-Button liest Slot 0 und startet Senden
#### Lieferung: 
fertige Replay-FSM + Unit-Test modules/ir_replay_fsm/test/test_ir_replay.py
## Person C: Encoder + TX
#### Dateien: 
modules/nec_encoder/src/nec_encoder.sv, modules/ir_tx/src/ir_tx.sv
#### Aufgabe: 
NEC-Timing-Sequenz + 38kHz-Ausgabe
#### Lieferung: 
funktionierende Sende-Kette + Timing-Checks (Waveform)
## Person D: Integration + Verifikation
#### Dateien: 
modules/ir_recorder_replay_top/src/ir_recorder_replay_top.sv, modules/ir_recorder_replay_top/test/test_ir_closed_loop.py, IRRecorder_Replay/sim/*
#### Aufgabe: 
Module verdrahten, End-to-End-Test, Sim-Flow, Doku
MVP-Bedienung: genau zwei Buttons (REC/PLAY), vorerst nur Slot 0
#### Lieferung: 
make test/make sim nutzbar, Closed-Loop-Test grün, Architektur dokumentiert
