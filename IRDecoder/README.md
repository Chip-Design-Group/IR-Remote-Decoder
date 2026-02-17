# IR Decoder Modules

This directory contains the core modules for decoding NEC infrared signals and formatting the output.

## Submodules

| Module | Description |
| :--- | :--- |
| [**NECDecoder**](NECDecoder/README.md) | Core logic for decoding the NEC protocol. |
| [**EdgeDetector**](EdgeDetector/README.md) | Signal conditioning and edge detection. |
| [**PulseTimer**](PulseTimer/README.md) | Precise timing of IR pulses. |
| [**OutputFormatter**](OutputFormatter/README.md) | Converts decoded data into human-readable text. |
| [**UART_TX**](UART_TX/README.md) | Serial interface for PC communication. |

## Tests

Each submodule has its own tests. You can run them individually or all together from the root using `pytest`.
