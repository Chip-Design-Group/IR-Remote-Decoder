# N8X2 Integration Notes (Kurz)

## Ausgangsproblem
- N8X2 wurde im UART nicht erkannt (`P:N8X2` fehlte), `LD4` blieb aus.
- Replay war damit ebenfalls unzuverlaessig, weil ohne korrekte Klassifikation als NEC/N8X gemischt wurde.

## Ursache 1: Space-Fenster-Ueberlappung
- NEC `1`-Space und N8X2 `1`-Space lagen zu nah beieinander.
- Effekt: N8X2-`1` wurde als normales NEC-`1` einsortiert.

### Loesung
- NEC `BIT1_MIN` angehoben, damit N8X2-`1` nicht mehr in das NEC-`1`-Fenster faellt.
- Ergebnis: N8X2-`1` wird sauber als `bit1x2` erkannt.

## Ursache 2: Mark-Dauer bei einigen N8X2-Frames
- Ein Teil der N8X2-Signale hatte nicht nur langen `1`-Space, sondern auch laengere Marks (~1.03 ms).
- Effekt: FSM verwarf diese Pulse im Burst-Zweig als ungueltig.

### Loesung
- Zusaetzliche Burst-Klassifikation fuer NEC/N8X2 (`is_bit_burst_x2`) eingefuehrt.
- In `SPACE` und `DATA` sowohl im Next-State als auch im Datapath akzeptiert.

## Status nach Fix
- N8X2 wird erkannt (`protocol_id = 10`, Label `N8X2`).
- Speicherung und Replay funktionieren mit N8X2-Timing.
- Bitstream wurde neu gebaut und auf Arty programmiert.
