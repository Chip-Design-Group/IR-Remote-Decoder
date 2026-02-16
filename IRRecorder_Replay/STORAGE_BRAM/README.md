# Ablaufdiagramm: `ir_storage_bram`

## Was macht `ir_storage_bram`?
`ir_storage_bram` ist der interne Speicherblock fuer aufgezeichnete IR-Codes.
Er speichert pro Slot ein 32-Bit-Wort (`ir_word_t`) und trennt sauber zwischen:

- **Schreiben (Record-Pfad)**: `wr_en`, `wr_addr`, `wr_data`
- **Lesen (Replay-Pfad)**: `rd_en`, `rd_addr` -> `rd_data`, `rd_valid`

Das Modul ist als BRAM-Inferenz gedacht (FPGA Block RAM), damit die Daten effizient und stabil gespeichert werden.

## Ablaufdiagramm (Write + Read)
```mermaid
flowchart TD
    A[clk Flanke] --> B{wr_en = 1?}
    B -- Ja --> C[Speichere wr_data in RAM an wr_addr]
    B -- Nein --> D{rd_en = 1?}
    C --> D

    D -- Ja --> E[Lese RAM an rd_addr nach rd_data]
    E --> F[Setze rd_valid fuer 1 Takt]

    D -- Nein --> G[Keine Speicheraktion]
    G --> H[rd_valid = 0]
    F --> I[Naechster Takt]
    H --> I
```

## Signale kurz erklaert
- `wr_en`: Schreibfreigabe.
- `wr_addr`: Zielslot fuer den Write.
- `wr_data`: 32-Bit IR-Wort, das gespeichert wird.
- `rd_en`: Lesefreigabe.
- `rd_addr`: Quellslot fuer den Read.
- `rd_data`: Ausgelesenes 32-Bit IR-Wort.
- `rd_valid`: Zeigt an, dass `rd_data` gueltig ist (typisch 1 Takt).

## Warum ist das wichtig im Recorder/Replay-System?
- Beim **Aufzeichnen** schreibt der Recorder den dekodierten NEC-Code in einen Slot.
- Beim **Abspielen** liest die Replay-FSM denselben Slot wieder aus.
- So kann ein empfangener Code spaeter reproduzierbar erneut gesendet werden.

## Praktischer Hinweis fuer deine Implementierung
Wenn du das RTL fertig machst, setze den Speicher als Array mit BRAM-Hinweis um, z. B.:

```systemverilog
(* ram_style = "block" *) ir_word_t mem [0:SLOT_COUNT-1];
```

Damit inferiert der Synthesizer den Speicher als Block RAM statt als reine FF-Struktur.

## Zeitlicher Ablauf (Timing, vereinfacht)
```mermaid
sequenceDiagram
    participant REC as Recorder_ReplayFSM
    participant BRAM as ir_storage_bram

    Note over REC,BRAM: Takt N (posedge clk)
    REC->>BRAM: wr_en=1, wr_addr, wr_data
    Note right of BRAM: Write erfolgt auf Taktflanke N

    Note over REC,BRAM: Takt N+1 (posedge clk)
    REC->>BRAM: rd_en=1, rd_addr
    Note right of BRAM: Read und Ausgabe erfolgen im selben Takt

    Note over REC,BRAM: Takt N+1 (nach Taktflanke)
    BRAM-->>REC: rd_data gueltig
    BRAM-->>REC: rd_valid=1 (1 Takt)

    Note over REC,BRAM: Takt N+2
    BRAM-->>REC: rd_valid=0
```

Hinweis:
- Exakte Latenz kann je nach RTL-Implementierung variieren.
- Fuer dieses Projekt ist das Ziel: `rd_valid` pulst genau dann, wenn `rd_data` stabil/gueltig ist.
