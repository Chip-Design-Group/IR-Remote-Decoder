## Person A: Recorder + Storage
#### Dateien: 
ir_recorder.sv, ir_storage_bram.sv
#### Aufgabe: 
Aufzeichnen und Speichern (record_req, target_slot, mem_wr_*)
#### Lieferung: 
fertige Write-Path-Logik + Unit-Test test_ir_recorder.py
## Person B: Replay-Steuerung
#### Dateien: 
ir_replay_fsm.sv
#### Aufgabe: 
Slot lesen, Daten entpacken, Encoder starten (mem_rd_*, enc_start)
#### Lieferung: 
fertige Replay-FSM + Unit-Test test_ir_replay.py
## Person C: Encoder + TX
#### Dateien: 
nec_encoder.sv, ir_tx.sv
#### Aufgabe: 
NEC-Timing-Sequenz + 38kHz-Ausgabe
#### Lieferung: 
funktionierende Sende-Kette + Timing-Checks (Waveform)
## Person D: Integration + Verifikation
#### Dateien: 
ir_recorder_replay_top.sv, test_ir_closed_loop.py, IRRecoder_Replay/sim/*, IRRecoder_Replay/doc/*
#### Aufgabe: 
Module verdrahten, End-to-End-Test, Sim-Flow, Doku
#### Lieferung: 
make test/make sim nutzbar, Closed-Loop-Test grün, Architektur dokumentiert