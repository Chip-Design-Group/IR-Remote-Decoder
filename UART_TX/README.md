# UART Transmitter (uart_tx)

Dieses Modul implementiert einen einfachen UART-Transmitter (8N1) für das
IR-Remote-Decoder-Projekt.

Der UART-Transmitter ist verantwortlich für das serielle Senden einzelner Bytes
über eine TX-Leitung mit fester Baudrate. Er wird vom Output-Formatter (Modul C1)
angesteuert und stellt eine einfache Handshake-Schnittstelle bereit.

## Eigenschaften
- UART-Modus: 8 Datenbits, keine Parität, 1 Stopbit (8N1)
- Feste Baudrate (z. B. 9600 bps)
- LSB-first Übertragung
- TX-Leitung ist im Idle-Zustand HIGH
- Vollständig synchron zum System-Clock

## Schnittstelle

### Inputs
- `clk`  
  System Clock (z. B. 10 MHz)

- `rst_n`  
  Active-low Reset

- `send`  
  1-Takt-Impuls zum Starten einer Übertragung (nur gültig, wenn `ready == 1`)

- `data[7:0]`  
  Zu sendendes Byte

### Outputs
- `tx`  
  UART TX-Leitung (serieller Ausgang)

- `ready`  
  HIGH, wenn das Modul bereit ist, ein neues Byte anzunehmen

- `busy`  
  HIGH während einer laufenden Übertragung

## Funktionsweise (Kurzfassung)
- Im Idle-Zustand ist `tx = 1` und `ready = 1`
- Bei `send == 1` wird das Byte übernommen und gesendet:
  - Startbit (0)
  - 8 Datenbits (LSB zuerst)
  - Stopbit (1)
- Währenddessen ist `busy = 1`
- Nach dem Stopbit kehrt das Modul in den Idle-Zustand zurück

## Test & Verwendung
- Das Modul kann vollständig in Simulation getestet werden
- Keine Hardware erforderlich
- Typische Testdaten: `0x55`, `0xAA`, ASCII-Zeichen

Dieses Modul ist unabhängig von den IR-spezifischen Teilen des Projekts und kann
frühzeitig entwickelt und getestet werden.