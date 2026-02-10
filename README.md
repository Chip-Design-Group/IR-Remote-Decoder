# 📡 IR Remote Decoder (ASIC)

Ein dedizierter ASIC zur Dekodierung von Infrarot-Fernbedienungen (NEC-Protokoll), entwickelt für den IHP SG13G2 Prozess.

---

## 📖 Projekt-Beschreibung

Dieses Projekt implementiert einen Hardware-Decoder für das weit verbreitete **NEC-Infrarot-Protokoll** (genutzt von Samsung, LG, etc.). Der Chip empfängt Signale von einem IR-Empfänger (z.B. TSOP38238), dekodiert die Befehle in Echtzeit und gibt sie über eine **UART-Schnittstelle** aus.

Das Design ist für die Fertigung als ASIC ausgelegt und nutzt den **OpenLane/Librelane** Flow.

### 🚀 Hauptfunktionen

*   **NEC-Dekodierung:** Echtzeit-Dekodierung von 32-Bit NEC-Frames (Address + Command).
*   **UART-Interface:** Serielle Ausgabe der dekodierten Daten (9600 Baud, 8N1).
*   **Präzises Timing:** Hardware-basierte Pulse-Width-Messung (±0.1µs Genauigkeit).
*   **Fehlererkennung:** Checksum-Validierung und Timeout-Erkennung.
*   **Status-LEDs:** Visuelles Feedback für gültige Signale oder Fehler.

---

## 📂 Projekt-Status & Dokumentation

Dieses Repository befindet sich in der Aufbauphase. Detaillierte Informationen zur Architektur, den Modulen, dem Zeitplan und der Test-Strategie finden sich in der Projektbeschreibung:

👉 **[Detaillierte Projektbeschreibung & Spezifikation ansehen](PROJECT_IR_REMOTE_DECODER.md)**

### Geplante Struktur
Das Projekt wird modular aufgebaut sein (siehe `PROJECT_IR_REMOTE_DECODER.md` für Details):

*   `src/`: SystemVerilog Quellcode (`edge_detector`, `nec_decoder`, `uart_tx`, etc.)
*   `test/`: Python/CocoTB Testbenches
*   `librelane/`: ASIC Build-Flow Submodule
*   `pdk/`: Process Design Kit (IHP SG13G2)

---

## 🛠️ Voraussetzungen

Um das Projekt zu simulieren und zu bauen, werden folgende Tools benötigt:

1.  **Simulation:** [Icarus Verilog](http://iverilog.icarus.com/) & [GTKWave](http://gtkwave.sourceforge.net/)
2.  **Testing:** [Python 3](https://www.python.org/) & [CocoTB](https://www.cocotb.org/)
3.  **ASIC Flow:** [Librelane](https://github.com/The-OpenROAD-Project/OpenLane) (via Docker oder Nix)

### Installation (Ubuntu/Debian)

```bash
# Simulation & Tools
sudo apt install iverilog gtkwave python3-pip git

# Python Dependencies
pip3 install cocotb pytest coverage
```

---

## 🚀 Erste Schritte

1.  **Repository klonen:**
    ```bash
    git clone --recursive <repo-url>
    cd IR-Remote-Decoder
    ```

2.  **Umgebung prüfen:**
    Stellen Sie sicher, dass alle Submodule (`librelane`, `pdk`) initialisiert sind:
    ```bash
    git submodule update --init --recursive
    ```

3.  **Entwicklung:**
    Folgen Sie dem 10-Tage-Plan in der [Projektbeschreibung](PROJECT_IR_REMOTE_DECODER.md), um die Module zu implementieren.

---

## 👥 Team & Lizenz

Entwickelt im Rahmen des Moduls "ASIC Design" (Semester 5).
Siehe `PROJECT_IR_REMOTE_DECODER.md` für die detaillierte Team-Aufteilung.
