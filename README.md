# IR Remote Decoder Project

Willkommen im **IR Remote Decoder** Projekt!

Dieses Repository enthält den kompletten Quellcode für einen hardwarebasierten Infrarot-Empfänger, optimiert für FPGAs (speziell für die IHP SG13G2 Technologie, aber generisch verwendbar).

## 🚀 Features

- **Vollständige Hardware-Dekodierung** des NEC-Infrarot-Protokolls.
- **Micro-UART** zur Ausgabe der Daten an einen PC.
- **Modulares Design** mit sauber getrennten Komponenten.
- **Umfassende Testsuite** basierend auf Python und CocoTB.

## 📂 Struktur

Das Projekt ist modular aufgebaut. Jedes Modul befindet sich in einem eigenen Unterordner mit Quellcode, Tests und Dokumentation.

| Modul | Beschreibung |
| :--- | :--- |
| [**TopLevel**](TopLevel/README.md) | Das Hauptmodul, das alle Komponenten verbindet. |
| [**NECDecoder**](NECDecoder/README.md) | Kernlogik zur Dekodierung des NEC-Protokolls. |
| [**EdgeDetector**](EdgeDetector/README.md) | Signalaufbereitung und Flankenerkennung. |
| [**PulseTimer**](PulseTimer/README.md) | Präzise Zeitmessung der IR-Pulse. |
| [**OutputFormatter**](OutputFormatter/README.md) | Konvertierung in menschenlesbaren Text. |
| [**UART_TX**](UART_TX/README.md) | Serielle Schnittstelle zum PC. |

## 🛠️ Schnellstart

### Voraussetzungen
- Icarus Verilog (Simulator)
- Python 3
- `cocotb`, `cocotb-test`, `pytest`

### Tests ausführen

Um sicherzustellen, dass alles funktioniert, können Sie alle Tests im Repository auf einmal ausführen:

```bash
pytest
```

Dies führt Hunderte von Tests über alle Module hinweg aus, von einfachen Unit-Tests bis hin zu komplexen System-Integrationstests.

## 📝 Lizenz

Dieses Projekt ist Open Source. Fühlen Sie sich frei, es zu forkem, zu verbessern und Pull Requests zu senden!
