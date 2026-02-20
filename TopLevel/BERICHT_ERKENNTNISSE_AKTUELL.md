# Bericht: Aktueller Stand der Signoff-Analyse

## Kontext

- Projekt: `ir_recorder_replay_padframe_top` (Chip-Flow)
- Ziel: Produktionsreifer Signoff
- Problem: Sehr hohe Magic-Fehlerzahlen trotz funktionierendem PnR

## Bisherige Beobachtungen

### 1) Voller Chip-Run (`Chip_run`)

- Deferred Errors:
  - `Magic DRC`: 16592
  - `Magic Illegal Overlap`: 1224
- Gleichzeitig:
  - OpenROAD Routing DRC: clean
  - KLayout DRC: clean
  - LVS: clean

Hauptklassen in `drc.magic.rpt`:

- `Slt.c` (max width without slots) auf M2/M3/M4/M6 (dominant)
- `TM2.bR` (TopMetal2 spacing bei breiten Segmenten)
- kleinere Restklassen (`CntB.h1`)

`IllegalOverlap`-Quellen:

- überwiegend `obsm7-metal7.ILLEGAL_OVERLAP`
- zusätzlich wenige `obsm3-metal3.ILLEGAL_OVERLAP`

### 2) DRC-Debug-Run (`Chip_run_drc_debug`)

Änderungen:

- `KLayout.SealRing: null`
- `KLayout.Filler: null`
- Ringbreite reduziert (`10um`), Ringspacing erhöht (`4.0um`)

Ergebnis:

- `Magic DRC`: 15411 (nur moderat besser)
- `Magic Illegal Overlap`: 1224 (praktisch unverändert)
- `KLayout density`: 58 Fehler

Interpretation:

- Die große Magic-Fehlermenge kommt **nicht nur** von SealRing/Filler.
- Das Abschalten von Filler/SealRing erzeugt erwartbar neue Density-Probleme und ist daher nur als Diagnosemodus geeignet.
- Overlap-Thematik sitzt weiterhin systematisch im obsm/metal-Bereich des Padframe-Kontexts.

## Wichtige Einordnung

- Hohe absolute Fehlerzahl bedeutet hier nicht automatisch viele unabhängige Layout-Bugs.
- Es sind überwiegend wenige Fehlerklassen mit sehr hoher Replikation.
- `top-run` war ein älterer `Classic`-Run für `ir_recorder_replay_chip_top` und nicht der aktuelle Padframe-Signoff.

## Was bereits vorbereitet wurde

- `config_signoff.yaml` (strikt, für vollständige Checks)
- `config_signoff_quick.yaml` (schnellere Iteration)
- `config_drc_debug.yaml` (Diagnose von SealRing/Filler/PDN-Ring-Effekten)
- `config_magic_isolation.yaml` (zusätzliche Isolierung: `RUN_FILL_INSERTION: false`)
- Makefile-Targets:
  - `librelane-signoff-quick`
  - `librelane-drc-debug`
  - `librelane-magic-isolation`
  - `librelane-tapeout`

## Nächster notwendiger Messschritt

`magic-isolation`-Run ausführen:

```bash
cd /home/maik/HM/Semester_5/IR-Remote-Decoder/librelane
nix-shell
cd /home/maik/HM/Semester_5/IR-Remote-Decoder/TopLevel/src
make librelane-magic-isolation
```

Danach vergleichen:

- Magic DRC Gesamtzahl
- Illegal Overlap Gesamtzahl
- Top-Regelklassen aus `drc.magic.rpt`

Ziel:

- Quantifizieren, wie viel `Slt.c` durch Fill-Insertion getrieben ist.
- Danach gezielt entscheiden: geometrische Anpassung vs. formaler Waiver-Prozess (abhängig von MPW/Foundry-Signoff-Regeln).

## Produktionsrelevante Entscheidung

Für Einreichung gilt:

- Entweder alle vom MPW/Foundry geforderten Signoff-Checks sind clean,
- oder offene Punkte sind offiziell als Waiver akzeptiert.

Ohne diese Absicherung ist die Einreichung technisch riskant.
