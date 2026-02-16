# Bericht: Fehlinterpretation von NEC-Repeat bei schwachem IR-Signal

Datum: 16. Februar 2026

## Problem
Bei größerem Abstand zur Fernbedienung oder schwachem/rauschigem IR-Signal wurden normale Frames teilweise als Repeat interpretiert.
Das führte zu unerwarteten zusätzlichen `data_valid`-Ereignissen bzw. doppelten UART-Frames.

## Ursache
Es gab zwei zusammenwirkende Ursachen:

1. Repeat-Erkennung war nicht robust genug gegen grenzwertige Pulse.
2. Zeitfenster/Toleranzen für Repeat waren nicht klar am praktischen NEC-Verhalten ausgerichtet.

Zusätzlich wurde zuvor ein permanenter interner Testpfad im Top-Level entfernt, der unabhängig von realem IR-Verkehr Frames erzeugen konnte.

## Lösung
Die Repeat-Logik wurde neu aufgebaut und anschließend auf Arduino-ähnliches Verhalten abgestimmt:

- Repeat wird als eigener Pfad in der FSM behandelt:
  - `REPEAT_WAIT_STOP`
  - `REPEAT_EMIT`
- Repeat wird nur akzeptiert, wenn ein vollständiger Repeat-Frame erkanntet wird:
  - AGC-Burst (~9ms)
  - Repeat-Space (~2.25ms)
  - finaler 560us-Burst
- Repeat ist nur nach zuvor gültigem Vollframe aktiv (`has_valid_frame`).
- Repeat ist zeitlich begrenzt über ein Gap-Fenster (`REPEAT_WINDOW_MAX = 120ms`).
- NEC-Repeat-Space wurde auf praxisnahe ±20% gesetzt (`REPEAT_MIN=1.8ms`, `REPEAT_MAX=2.7ms`).

## Technische Änderungen

### `NECDecoder/src/nec_decoder.sv`
- Repeat-Zustände ergänzt und in Next-State-Logik integriert.
- Repeat-Erkennung auf vollständige Sequenz erweitert.
- `has_valid_frame` und `since_valid_cnt` ergänzt.
- Gap-Fenster für Repeat-Aktivierung ergänzt.
- Ausgabeverhalten: Repeat erzeugt `data_valid` für den letzten gültigen Frame.

### Weitere Stabilitätskorrekturen (im selben Fix-Zyklus)
- `TopLevel/src/ir_decoder_top.sv`
  - internen permanenten Testgenerator aus dem aktiven Empfangspfad entfernt.
- `OutputFormatter/src/output_formatter.sv`
  - Multi-Driver auf `byte_idx` entfernt.
- `TopLevel/constraints/arty_a7_100t.xdc`
  - `PULLUP` auf `ir_in_PAD` gesetzt.
- `TopLevel/program_arty.tcl`
  - Programmierskript wiederhergestellt.

## Ergebnis
Nach Rebuild und Flash wurde bestätigt:

- Repeat-Funktion ist vorhanden.
- Fehl-Repeat bei schlechtem Signal ist im Testfall behoben.
- Systemverhalten entspricht dem erwarteten Bediengefühl („klappt wunderbar“).

## Build/Programmierstatus
- Bitstream erfolgreich erzeugt.
- FPGA erfolgreich programmiert (`Programming Complete!`).
