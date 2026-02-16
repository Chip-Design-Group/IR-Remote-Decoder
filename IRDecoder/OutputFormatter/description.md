# Output Formatter – Overview

This module formats `address` and `command` (8 bits each) into a human-readable ASCII string and sends it byte-by-byte over UART.

**Output format:**

A:<addr_hex> C:<cmd_hex>\n

Example:


$$address = 8'h3F / command = 8'hA2$$

-> "A:3F C:A2\n"


---

## Transformation (Binary → ASCII)

Each 8-bit value is split into two 4-bit halves (nibbles):

These nibbles are converted

| Nibble | ASCII |
|--------|-------|
| 0–9    | '0'–'9' |
| 10–15  | 'A'–'F' |

Example:
8'h3F -> '3' and 'F'


---

##  Description (How it works)

1. The module waits in state `IDLE` for `data_valid`.
2. When `data_valid` is asserted, `address` and `command` are buffered.
3. The finite state machine then sends characters one by one:
   - `'A'`
   - `':'`
   - Address hex digits (high, low)
   - `' '`
   - `'C'`
   - `':'`
   - Command hex digits (high, low)
   - `'\n'`
4. A character is transmitted only when `uart_ready = 1`.
5. After the newline character, the FSM returns to `IDLE`.

---

##  State Diagram (Mermaid)

:::mermaid
stateDiagram-v2
    direction LR  %% LR = Left to Right, besser lesbar

    IDLE: Idle (wait for valid_in)
    SEND: Send current byte
    WAIT_ACK: 1-cycle delay for UART pulse
    WAIT_UART: Wait for UART ready

    %% Übergänge
    IDLE --> SEND : valid_in = 1
    SEND --> WAIT_ACK : uart_ready = 1
    WAIT_ACK --> WAIT_UART : uart_ready = 1

    %% Byte Index Logik
    WAIT_UART --> SEND : uart_ready = 1, more bytes (byte_idx < 9)
    WAIT_UART --> IDLE : uart_ready = 1, last byte (byte_idx = 9)

    %% Warten wenn UART nicht ready
    WAIT_ACK --> WAIT_ACK : uart_ready = 0
:::