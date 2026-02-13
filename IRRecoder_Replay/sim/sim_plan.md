# sim_plan

## Zweck
Dokumentiert, was in der Simulation erzeugt und abgelegt wird.

## Rein
- Build-Inputs: `../src/*.sv`, `../test/*.py`
- Parameter: Taktfrequenz, NEC-Timing, Slot-Anzahl

## Raus
- Logfiles (Testergebnisse)
- Waveforms (z. B. VCD/FST)
- Optional: dekodierte/encodierte Vergleichsvektoren

## TODO
- Konkreten Simulator festlegen
- Dateinamenkonvention fuer Wavefiles festlegen
- Cleanup-Regeln definieren
