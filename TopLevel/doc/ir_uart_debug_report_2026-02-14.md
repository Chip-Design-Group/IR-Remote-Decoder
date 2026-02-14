# IR/UART Debug Report

**Datum:** 14. Februar 2026  
**Projekt:** IR-Remote-Decoder

## Zusammenfassung

Das UART-Problem hatte nicht nur eine, sondern mehrere Ursachen in unterschiedlichen Schichten:

1. **Build-Konfiguration zeitweise mit `DEBUG_INPUT_ONLY`**
   - Decoder/UART-Pfad war dabei in Reset gehalten.
   - Effekt: LED-Aktivität sichtbar, aber keine normale UART-Frames.

2. **Timing-Risiko im `output_formatter` (Byte + Request im selben FF-Block)**
   - `uart_data` und `uart_tx_req` wurden gleichzeitig getaktet gesetzt.
   - Effekt: UART konnte im Request-Zyklus noch den alten Byte-Wert sehen (verschobene/komische Zeichenfolge).

3. **Zu frühe Repeat-Erkennung im `nec_decoder`**
   - Repeat wurde nach `9ms + 2.25ms` bereits akzeptiert.
   - Der finale NEC-Repeat-Burst (`~560us LOW`) wurde nicht zwingend bestätigt.
   - Effekt: einzelne neue Tastendrücke konnten fälschlich als Repeat der alten Taste erscheinen.

## Symptome im Feldtest

- Teilweise gar keine UART-Ausgabe trotz IR-Aktivität auf LEDs.
- Zeitweise verschobene/ungewöhnliche Byte-Reihenfolge im Terminal.
- Bei Wechsel auf andere Fernbedienungs-Tasten kam sporadisch nochmals der vorherige Command (Repeat-ähnlich).

## Umgesetzte Fixes

### 1) UART-Byte-Handoff stabilisiert

**Datei:** `OutputFormatter/src/output_formatter.sv`

- `uart_data` wird jetzt **kombinatorisch** aus `byte_idx` gebildet.
- `uart_tx_req` bleibt ein klarer 1-Takt-Puls im FF-Block.

Ergebnis: UART sampelt den vorgesehenen Byte-Wert im selben Send-Zyklus stabil.

### 2) NEC-Repeat-Erkennung gehärtet

**Datei:** `NECDecoder/src/nec_decoder.sv`

- Neuer FSM-Zustand `REPEAT_WAIT`.
- Nach erkanntem `REPEAT_SPACE` wird auf den finalen `BIT_BURST` gewartet.
- Nur bei kompletter Repeat-Sequenz wird `REPEAT` ausgelöst.

Ergebnis: weniger False-Repeats bei Tastensprüngen.

## Verifikation

- `NECDecoder` Testsuite erfolgreich (`16/16 PASS`), inkl. zusätzlichem Test:
  - `test_repeat_missing_final_burst_is_ignored`
- FPGA neu gebaut und programmiert.
- Feldtest zeigte stabile Frames wie `A:00 C:45\n` und insgesamt deutlich robusteres Verhalten.

## Final in Git (minimal)

Final gepusht wurden nur die nötigen Runtime-Fixes:

- `NECDecoder/src/nec_decoder.sv`
- `OutputFormatter/src/output_formatter.sv`

Nicht gepusht wurden temporäre/Debug-nahe Dateien (z. B. ILA-Skript oder lokale Build-Helfer).

## Optionaler nächster Schritt

Falls bei sehr noisiger Umgebung noch selten Fehl-Repeats auftreten:

- Repeat nur in engem Zeitfenster nach letzter gültiger Taste akzeptieren  
  (typisch etwa 80–130 ms, abhängig vom Zielgerät/Remote-Verhalten).
