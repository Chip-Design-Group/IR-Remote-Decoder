# src
SystemVerilog-Module fuer IR Recorder und Replay.
Der TX-Pfad ist fuer eine externe IR-LED-Treiberstufe mit NPN-Transistor ausgelegt
(`ir_npn_drive`/`ir_tx_npn_drive`; `ir_led_out` bleibt als Alias).

Empfohlene Dateien:
- `ir_recorder.sv`
- `ir_replay_fsm.sv`
- `ir_storage_bram.sv`
- `nec_encoder.sv`
- `ir_tx.sv`
- `ir_recorder_replay_top.sv`
