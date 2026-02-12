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
    IDLE --> SEND_A: valid_in
    SEND_A --> SEND_COLON1: uart_ready
    SEND_COLON1 --> SEND_ADDR_HIGH: uart_ready
    SEND_ADDR_HIGH --> SEND_ADDR_LOW: uart_ready
    SEND_ADDR_LOW --> SEND_SPACE: uart_ready
    SEND_SPACE --> SEND_C: uart_ready
    SEND_C --> SEND_COLON2: uart_ready
    SEND_COLON2 --> SEND_CMD_HIGH: uart_ready
    SEND_CMD_HIGH --> SEND_CMD_LOW: uart_ready
    SEND_CMD_LOW --> SEND_NEWLINE: uart_ready
    SEND_NEWLINE --> IDLE: uart_ready
:::