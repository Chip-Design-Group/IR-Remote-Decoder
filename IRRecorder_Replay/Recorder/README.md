# Recorder (`ir_recorder`)

## Was macht dieses Modul?
`ir_recorder` nimmt bereits dekodierte IR-Daten (`dec_payload`) an und schreibt sie in den Speicher (`ir_storage_bram`).

Kurz gesagt:
- wartet auf einen Record-Request (`record_req`),
- uebernimmt bei gueltigen Decoder-Daten (`dec_valid`) den Payload,
- packt den Payload zu einem 67-Bit-Wort (`ir_pack_word(dec_payload)`), das `frame_data`, `frame_bits`, `protocol_id` und `flags` enthält,
- schreibt das Wort in den Zielslot (`target_slot`) ueber `mem_wr_*`.

Statussignale:
- `busy`: Recorder ist aktiv.
- `done`: Aufnahme/Write wurde erfolgreich abgeschlossen.
- `error`: Fehlerfall (z. B. Request ohne gueltige Daten innerhalb eines Timeouts).

MVP-Hinweis:
- Der REC-Button treibt `record_req`.
- `target_slot` ist im MVP typischerweise fest `0`.

## Ablaufdiagramm (funktional)
```mermaid
flowchart TD
    A[Idle] --> B{record_req high}
    B -- Nein --> A
    B -- Ja --> C[Set busy]
    C --> D{dec_valid high}
    D -- Nein --> E[Wait for decoded payload]
    E --> D
    D -- Ja --> F[Pack payload to ir_word]
    F --> G[Set mem_wr_addr to target_slot]
    G --> H[Set mem_wr_data to packed payload]
    H --> I[Pulse mem_wr_en for one clock]
    I --> J[Set done and clear busy]
    J --> A

    E --> K{timeout reached}
    K -- Nein --> D
    K -- Ja --> L[Set error and clear busy]
    L --> A
```

## Zeitlicher Ablauf (vereinfacht)
```mermaid
sequenceDiagram
    participant CTRL as Control/Buttons
    participant REC as ir_recorder
    participant BRAM as ir_storage_bram

    Note over CTRL,REC: Takt N
    CTRL->>REC: record_req=1, target_slot
    REC->>REC: busy=1

    Note over REC: Wartephase bis dec_valid=1
    REC->>REC: dec_valid abfragen

    Note over CTRL,REC: Takt N+k
    CTRL->>REC: dec_valid=1, dec_payload
    REC->>REC: mem_wr_data = ir_pack_word(dec_payload)
    REC->>BRAM: mem_wr_en=1, mem_wr_addr=target_slot, mem_wr_data

    Note over CTRL,REC: Takt N+k+1
    REC->>REC: mem_wr_en=0
    REC->>REC: done=1, busy=0

    Note over CTRL,REC: naechster Takt
    REC->>REC: done=0 (Pulsende), zurueck nach Idle
```

Hinweis:
- Aktuelle Implementierung: `done` und `error` sind 1-Takt-Pulse.
- Aktuelle Timeout-Definition: `WAIT_TIMEOUT_CYCLES = 256` (Parameter in `ir_recorder.sv`).
