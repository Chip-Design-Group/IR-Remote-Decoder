# Ablaufdiagramm `ir_storage_bram`

```mermaid
flowchart TD
  A[Reset] --> B[rd_data=0,\nrd_valid=0]
  B --> C[Warte auf posedge clk]

  C --> D{rst_n=0?}
  D -->|ja| B
  D -->|nein| E[rd_valid=0\n(Default je Takt)]

  E --> F{wr_en=1?}
  F -->|ja| G[mem[wr_addr] = wr_data]
  F -->|nein| H
  G --> H{rd_en=1?}

  H -->|ja| I[rd_data = mem[rd_addr]\nrd_valid = 1]
  H -->|nein| J[Kein Read-Response]

  I --> C
  J --> C
```
