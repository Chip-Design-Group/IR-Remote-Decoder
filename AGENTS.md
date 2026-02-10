# AGENTS.md - AI Agent Context für ASIC Design

**Zielgruppe**: AI Coding Assistants (GitHub Copilot, Claude, etc.)  
**Umgebung**: LibreLane 3.0 + IHP SG13G2 PDK (130nm BiCMOS)  
**Letzte Aktualisierung**: 10. Februar 2026

---

## 🎯 KRITISCHE REGELN

### Environment
```
TOOL: LibreLane (nur in nix-shell librelane/)
PDK: IHP SG13G2 (130nm)
HDL: SystemVerilog (USE_SLANG: true)
```

### Vor JEDER LibreLane-Aktion prüfen:
1. ✅ User ist in `nix-shell librelane/`
2. ✅ Alle Pfade nutzen `dir::` prefix in YAML
3. ✅ Macro-Positionen sind Vielfache von PDN_VPITCH/HPITCH
4. ✅ PDN_VSPACING >= 2.0 (TopMetal2 minimum)
5. ✅ DRT_OPT_ITERS <= 64 (höher = Fehler)

---

## 🔴 HÄUFIGE FEHLER

### 1. LibreLane nicht gefunden
**Error**: `librelane: command not found`  
**Fix**: User muss `nix-shell librelane/` ausführen

### 2. Unbekannte Config-Keys
```yaml
# ❌ FALSCH
CELL_PAD: 4
DETAILED_ROUTER_ENABLE_VIA_GEN: true
PL_TARGET_DENSITY: 0.50

# ✅ RICHTIG
GPL_CELL_PADDING: 4
PL_TARGET_DENSITY_PCT: 50
```

### 3. PDN Spacing Violations
**Error**: `[PDN-0108] Spacing < 2.0000 um`  
**Fix**: `PDN_VSPACING: 2.5` und `PDN_HSPACING: 2.5`

### 4. Power Grid Violations
**Ursache**: Macros nicht auf PDN-Grid ausgerichtet  
**Fix**: Bei PDN_VPITCH: 40 → location: [440, 600, 680] (Vielfache von 40!)

### 5. DRT Crash
**Error**: `drt.tcl, 52 Wrong number of arguments`  
**Fix**: `DRT_OPT_ITERS: 64` (MAX!)

---

## 📋 CRITICAL CONFIG PATTERNS

### Module config.yaml
```yaml
meta:
  version: 3
  flow: Classic

DESIGN_NAME: modul_name
VERILOG_FILES:
  - dir::src/modul.sv
USE_SLANG: true
CLOCK_PERIOD: 10
CLOCK_PORT: clk
FP_SIZING: relative
FP_CORE_UTIL: 30
VDD_NETS: ["VDD"]
GND_NETS: ["VSS"]
```

### Chip config.yaml (Hierarchisch)
```yaml
meta:
  version: 3
  flow: Chip  # WICHTIG: "Chip" nicht "Classic"!

# PDN - KRITISCH
PDN_CORE_RING: true
PDN_CORE_RING_CONNECT_TO_PADS: true
PDN_CORE_RING_VSPACING: 2.5  # >= 2.0!
PDN_CORE_RING_HSPACING: 2.5
PDN_VPITCH: 40
PDN_HPITCH: 40
PDN_VSPACING: 2.5  # >= 2.0!
PDN_HSPACING: 2.5
FP_PDN_ENABLE_MACROS_GRID: true

# Routing-Optimierung
PL_TARGET_DENSITY_PCT: 40  # Nicht 0.40!
GRT_OVERFLOW_ITERS: 200
DRT_OPT_ITERS: 64  # MAX 64!
GPL_CELL_PADDING: 4

# PADs - escaped brackets!
PAD_SOUTH: ["vdd_pads\\[0\\].vdd_pad"]

# Macros
MACROS:
  modul_name:
    gds: dir::../M1_Modul/final/gds/modul.gds
    lef: dir::../M1_Modul/final/lef/modul.lef
    nl: dir::../M1_Modul/final/pnl/modul.pnl.v
    lib:
      nom_typ_1p20V_25C: dir::../M1_Modul/final/lib/nom_typ_1p20V_25C/modul__nom_typ_1p20V_25C.lib
      nom_fast_1p32V_m40C: dir::../M1_Modul/final/lib/nom_fast_1p32V_m40C/modul__nom_fast_1p32V_m40C.lib
      nom_slow_1p08V_125C: dir::../M1_Modul/final/lib/nom_slow_1p08V_125C/modul__nom_slow_1p08V_125C.lib
    spef:
      nom_typ_1p20V_25C: dir::../M1_Modul/final/spef/nom/modul.nom.spef
    instances:
      u_chip.u_modul:
        location: [440, 440]  # Vielfache von PDN_VPITCH!
        orientation: N

PDN_MACRO_CONNECTIONS:
  - u_chip.u_modul VDD VSS VPWR VGND
```

---

## 🧮 WICHTIGE BERECHNUNGEN

### Macro-Positionen auf PDN-Grid
```python
# Bei PDN_VPITCH: 40
valid_positions = [360, 400, 440, 480, 520, 560, 600, 640, 680, 720, 760, 800]
# Formel: position % 40 == 0 ODER (position - CORE_START) % 40 == 0
```

### DRC-Regeln (IHP SG13G2)
- **Cnt.b**: Min Contact Spacing = 0.18µm
- **TM1.b**: Min TopMetal1 Spacing = 1.64µm  
- **TM2**: Min TopMetal2 Spacing = 2.00µm

---

## 🔧 WORKFLOW

### Modul-Entwicklung
```bash
cd M1_ModulName
# 1. src/modul.sv schreiben
# 2. test/test_modul.py schreiben
# 3. cd test && make
# 4. config.yaml erstellen
# 5. nix-shell ../../librelane/
# 6. make librelane
```

### Chip-Integration
```bash
cd Chip
# 1. top.sv mit PADs erstellen
# 2. chip.sv mit Macro-Instantiierungen
# 3. config.yaml mit MACROS-Sektion
# 4. Macro-Positionen berechnen (PDN-Grid!)
# 5. nix-shell ../../librelane/
# 6. make librelane
```

---

## 📊 ERFOLGS-KRITERIEN

### Modul-Synthese
```bash
# Nach make librelane:
ls final/gds/*.gds      # GDS vorhanden
ls final/lef/*.lef      # LEF vorhanden
ls final/lib/*/*.lib    # 3 LIB-Files (3 Corners)
```

### Chip-Synthese
```json
// Erwartete Metriken:
{
  "design__lint_error__count": 0,              // MUSS 0 sein
  "openroad__psm__violations": 0,              // MUSS 0 sein (Power Grid)
  "klayout__drc_error__count": 50-100,         // Akzeptabel für 1. Chip
  "clock__skew__worst_hold": 0,                // MUSS 0 sein
  "clock__skew__worst_setup": 0                // MUSS 0 sein
}
```

---

## �� AGENT DECISION TREE

### User fragt: "Create/Design Module"
1. ✅ Verzeichnis-Struktur anlegen
2. ✅ SystemVerilog schreiben
3. ✅ cocotb Test schreiben
4. ✅ config.yaml erstellen
5. ⚠️ **INSTRUIERE** User: `cd test && make` ausführen
6. ⚠️ **INSTRUIERE** User: `nix-shell` starten, dann `make librelane`

### User fragt: "Integrate into Chip"
1. ✅ Prüfe: Alle Module haben `final/` Verzeichnisse
2. ✅ chip.sv mit Macro-Instantiierungen
3. ✅ top.sv mit PAD-Ring
4. ✅ Berechne Macro-Positionen (PDN-Grid!)
5. ✅ config.yaml mit MACROS-Sektion
6. ⚠️ **WARNE**: Nix-Shell erforderlich

### User berichtet: "make librelane failed"
1. ✅ Frage nach letzten 50 Zeilen
2. ✅ Identifiziere Fehlertyp:
   - "librelane: not found" → nix-shell
   - "Unknown key" → ungültiger Parameter
   - "[PDN-0108]" → PDN_SPACING zu klein
   - "drt.tcl error" → DRT_OPT_ITERS zu hoch
   - "power grid violations" → Macro-Fehlausrichtung
3. ✅ Gib spezifischen Fix

---

## 💡 WICHTIGE PATTERNS

### Pattern: Immer `dir::`
```yaml
# ❌ FALSCH
gds: ../M1_Modul/final/gds/modul.gds

# ✅ RICHTIG
gds: dir::../M1_Modul/final/gds/modul.gds
```

### Pattern: PAD Instanz-Namen
```yaml
# In top.sv:
sg13g2_IOPadIn x_pads[0] (.p_pad(X_PAD[0]), ...);

# In config.yaml:
# ❌ FALSCH (Port-Name)
PAD_SOUTH: ["X_PAD[0]"]

# ✅ RICHTIG (Instanz-Name mit escaped brackets)
PAD_SOUTH: ["x_pads\\[0\\].x_pad"]
```

### Pattern: Power Pin Mapping
```yaml
# Chip top-level nutzt: VDD, VSS
# Module intern nutzen: VPWR, VGND

PDN_MACRO_CONNECTIONS:
  - u_chip.u_modul VDD VSS VPWR VGND
  #                ↑   ↑   ↑    ↑
  #                Chip │ Module
```

---

**End of AGENTS.md**

*Diese Datei bei Projekt-Start lesen und bei Fehlern konsultieren.*
