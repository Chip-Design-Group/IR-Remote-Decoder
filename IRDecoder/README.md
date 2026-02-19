# IR Decoder Modules

This directory contains the core modules for decoding NEC infrared signals plus the Samsung 32-bit and 36-bit variants, along with the helpers that turn the decoded frames into formatted text and UART characters.

## Submodules

| Module | Description |
| :--- | :--- |
| [**NECDecoder**](NECDecoder/README.md) | Core logic for decoding NEC, Samsung32, and Samsung36 infrared frames. |
| [**EdgeDetector**](EdgeDetector/README.md) | Signal conditioning and edge detection. |
| [**PulseTimer**](PulseTimer/README.md) | Precise timing of IR pulses. |
| [**OutputFormatter**](OutputFormatter/README.md) | Converts decoded data into human-readable text, including protocol IDs for Samsung variants. |
| [**UART_TX**](UART_TX/README.md) | Serial interface for PC communication. |

## Tests

Each submodule has its own tests. You can run them individually or all together from the root using `pytest`.
