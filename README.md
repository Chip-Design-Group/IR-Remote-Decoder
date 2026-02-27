# IR Remote Decoder Project

![CI Status](https://github.com/MaikUnglert/IR-Remote-Decoder/actions/workflows/ci.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Welcome to the **IR Remote Decoder** project!

This repository contains the complete source code for a hardware-based Infrared Receiver/Decoder and Recorder/Replay system, optimized for FPGAs (specifically strictly designed for usage with IHP SG13G2 technology, but generally usable).

## 🚀 Features

- **Full Hardware Decoding** of NEC, Samsung variants, and NEC-like N8X2 IR protocols.
- **Micro-UART** for data output to a PC.
- **Modular Design** with cleanly separated components.
- **Comprehensive Test Suite** based on Python and CocoTB.
- **IR Recording & Replay** capabilities.

## 📂 Structure

The project is modular. Each module resides in its own subdirectory with source code, tests, and documentation.

| Module | Description |
| :--- | :--- |
| [**TopLevel**](TopLevel/README.md) | **Canonical Entry Point**. The main integration module for the board. |
| [**IRDecoder**](IRDecoder/README.md) | Decoder modules (NEC Decoder, Edge Detector, etc.). |
| [**IRRecorder_Replay**](IRRecorder_Replay/README.md) | Recorder and Replay modules. |
| [**legacy**](legacy/) | Archived legacy code (e.g., old `IRDecoder/TopLevel`). |

## 🛠️ Quick Start

### Prerequisites
- Icarus Verilog (Simulator)
- Python 3
- `cocotb`, `cocotb-test`, `pytest`

### Running Tests

To ensure everything is working, you can run all tests in the repository at once:

```bash
pytest
```

This runs hundreds of tests across all modules, from simple unit tests to complex system integration tests.

## 📝 License

This project is Open Source. Feel free to fork it, improve it, and send Pull Requests!
