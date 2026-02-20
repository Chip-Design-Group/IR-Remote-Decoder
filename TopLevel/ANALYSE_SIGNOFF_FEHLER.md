# Analyse: Signoff-Fehler und nächstes Vorgehen

## 1) Welche Fehler sind aufgetreten?

Im `Chip_run` (Padframe-Top) sind am Ende diese harten Fehler aufgetreten:

- `16592 Magic DRC errors found`
- `1224 Magic Illegal Overlap errors found`

Betroffene Klassen aus den Reports:

- `Slt.c` (max width without slots), vor allem auf `Metal2/3/4/6`
- `TM2.bR` (TopMetal2 spacing bei breiten Leitungen)
- `obsm7-metal7.ILLEGAL_OVERLAP`
- `obsm3-metal3.ILLEGAL_OVERLAP`

Gleichzeitig waren folgende Kernchecks sauber:

- Routing DRC (`Checker.TrDRC`) clean
- KLayout DRC clean
- LVS clean

## 2) Warum war `fast` bzw. `top-run` verwirrend?

- `config_fast.yaml` deaktiviert viele Signoff-Checks, daher wirkt der Run "grün", obwohl volle Signoff-Probleme später auftreten können.
- `src/runs/top-run` ist ein anderer, älterer Run:
  - Flow: `Classic`
  - Design: `ir_recorder_replay_chip_top`
  - nicht der aktuelle Padframe-Top-Run (`ir_recorder_replay_padframe_top`, Flow `Chip`)

## 3) Aktueller technischer Befund

Die großen Fehlerzahlen kommen primär aus Magic-basierten Regeln/Interpretationen im Padframe/Bondpad/Sealring-Kontext, nicht aus einem offensichtlichen funktionalen Core-Fehler.

Das ist wichtig:

- Für reine Iteration kann man das temporär ausklammern.
- Für Produktion muss das gegen MPW/Foundry-Signoff-Vorgaben abgesichert werden.

## 4) Was du jetzt tun musst (konkret)

### Schritt A: Fehlerursache isolieren (Debug)

Nutze den neuen Debug-Run:

```bash
cd /home/maik/HM/Semester_5/IR-Remote-Decoder/librelane
nix-shell
cd /home/maik/HM/Semester_5/IR-Remote-Decoder/TopLevel/src
make librelane-drc-debug
```

`config_drc_debug.yaml` macht zwei Dinge:

- deaktiviert `KLayout.SealRing` und `KLayout.Filler`
- entschärft Core-Ring-Breite/Spacing (`10um`, `4.0um`)

Ziel: prüfen, ob die Massenviolationen stark einbrechen.

### Schritt B: Schnell iterieren

Für kürzere Iterationen:

```bash
make librelane-signoff-quick
```

### Schritt C: Finalen Produktionslauf

Wenn Debug stabil ist:

```bash
make librelane-tapeout
```

Danach zwingend prüfen:

- `final/metrics.json`
- `flow.log`, `warning.log`, `error.log`
- DRC/LVS/Timing-Checker

## 5) Produktion: Entscheidungskriterium

Du kannst nur dann sicher einreichen, wenn eines von beiden erfüllt ist:

1. Alle von deinem MPW/Foundry geforderten Signoff-Checks sind clean.
2. Offene Punkte sind offiziell als zulässige Waiver akzeptiert.

Ohne diese Absicherung ist ein Versand riskant.

## 6) Dateien/Targets, die jetzt relevant sind

- `src/config_drc_debug.yaml`
- `src/config_signoff_quick.yaml`
- `src/config_tapeout.yaml`
- `src/config_signoff.yaml`
- `src/TAPEOUT_CHECKLIST.md`
- `src/Makefile`
  - `librelane-drc-debug`
  - `librelane-signoff-quick`
  - `librelane-tapeout`

