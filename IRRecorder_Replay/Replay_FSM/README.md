# Replay FSM

Die `ir_replay_fsm` steuert den Replay-Ablauf: Sie liest einen Slot aus dem Speicher, entpackt das 32-Bit-Wort zu `address/command/flags` und startet den Encoder nur dann, wenn `enc_ready` und `tx_ready` aktiv sind.

## Kurzablauf

1. `replay_req` (Rising Edge) startet den Ablauf und uebernimmt `target_slot`.
2. `mem_rd_en` wird fuer einen Takt gepulst, um den Slot zu lesen.
3. Bei `mem_rd_valid` wird das Wort uebernommen und entpackt.
4. Wenn `flags[IR_FLAG_VALID_BIT] = 1`, wartet die FSM auf `enc_ready && tx_ready`.
5. `enc_start` wird fuer einen Takt gepulst, `enc_payload` ist das entpackte Wort.
6. Danach folgt ein `done`-Puls; bei ungueltigem Slot ein `error`-Puls.

## State Machine

```mermaid
stateDiagram-v2
    [*] --> ST_IDLE

    ST_IDLE --> ST_READ_REQ: replay_req rising edge
    ST_READ_REQ --> ST_READ_WAIT: mem_rd_en pulse
    ST_READ_WAIT --> ST_DECODE_WORD: mem_rd_valid

    ST_DECODE_WORD --> ST_WAIT_ENCODER: flags[valid]=1
    ST_DECODE_WORD --> ST_ERROR: flags[valid]=0

    ST_WAIT_ENCODER --> ST_START_ENCODE: enc_ready && tx_ready
    ST_START_ENCODE --> ST_DONE: enc_start pulse

    ST_DONE --> ST_IDLE
    ST_ERROR --> ST_IDLE
```
