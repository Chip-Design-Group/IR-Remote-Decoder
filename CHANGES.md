# Session Report – Samsung36 & ESP32 WiFi Button (2026-02-19)

## Problem 1 – Falsches Samsung-Protokoll (Samsung48 → Samsung36)

**Problem:** Das Remote benutzt 16 Adress-Bits + Sync-Bit + 4 ID + 8 Cmd + 8 ~Cmd = **36 Bits** total. Der Code war auf Samsung48 ausgelegt, was nicht zum echten Timing passte.

**Lösung:**
- `PROTO_SAMSUNG48` → `PROTO_SAMSUNG36` umbenannt
- VALIDATE bei `bit_counter == 35` (letztes Bit angekommen)
- Payload-Extraktion: `shift_reg[47:32]` = 16-bit Addr, `shift_reg[27:20]` = Cmd, `shift_reg[19:12]` = ~Cmd
- Neues Ausgabeformat: `P:SAM36    A:aaaa C:cc\n` (23 Bytes)
- `monitor_uart.py` Regex angepasst

**Geänderte Dateien:** `nec_decoder.sv`, `output_formatter.sv`, `monitor_uart.py`

---

## Problem 2 – ESP32 SPI-Empfänger fehlte

**Problem:** Der ESP32-C3 sendet Slot/Kommando-Informationen über Software-SPI (8-Bit-Frame: `slot[7:5] | cmd[4:3] | magic[2:0]`), das FPGA hatte keinen Empfänger dafür.

**Lösung:** Neues Modul `TopLevel/src/esp32_spi_receiver.sv`:
- 2-FF Synchronizer für CLK und DATA (Metastabilität)
- Rising-Edge-Detektor auf synchronisiertem CLK
- 8-Bit Schieberegister (MSB first)
- Magic-Check `frame[2:0] == 3'b101`, ungültige Frames werden verworfen
- `replay_req` / `record_req` als 1-Takt-Puls + `slot_addr[2:0]`

**Pinbelegung (PMOD JA):**

| Signal    | FPGA-Pin | PMOD | ESP32 GPIO |
|-----------|----------|------|------------|
| SPI_CLK   | A11      | JA3  | GPIO 5     |
| SPI_DATA  | D12      | JA4  | GPIO 4     |

**Geänderte Dateien:** `esp32_spi_receiver.sv` (neu), `ir_recorder_replay_arty_top.sv`, `arty_a7_100t_top.xdc`

---

## Problem 3 – Record-LED blinkte nicht

**Problem:** `record_hold_q` wurde nur gesetzt wenn `!busy`. Kurze ESP32-Pulse (1 Takt) wurden verschluckt wenn der Core noch beschäftigt war.

**Lösung:** `!busy`-Guard entfernt. Blink-Rate auf ~0.1s beschleunigt (Bit 20).

**Geänderte Dateien:** `ir_recorder_replay_top.sv`, `ir_recorder_replay_arty_top.sv`

---

## Problem 4 – Nur Slot 0 funktionierte (Timing-Bug)

**Problem:** `esp_slot_addr` ist ein 1-Takt-Puls. Einen Takt nach dem Puls (wenn `record_hold_q` latcht) war `combined_slot_sel` bereits auf 0 zurückgesprungen → alle Aufnahmen landeten in Slot 0.

**Lösung:** Register `esp_slot_addr_lat` das den Slot beim SPI-Puls einfriert und stabil hält:

```systemverilog
always_ff @(posedge clk_core or negedge rst_n_PAD) begin
    if (esp_record_req || esp_replay_req)
        esp_slot_addr_lat <= esp_slot_addr;
end
assign combined_slot_sel = (esp_record_req || esp_replay_req)
                           ? esp_slot_addr : esp_slot_addr_lat;
```

**Geänderte Dateien:** `ir_recorder_replay_arty_top.sv`

---

## Problem 5 – ESP32 SPI desynchronisiert nach Einschalten

**Problem:** `bit_cnt` hatte keinen Reset bei Inaktivität. Nach dem Einschalten oder einem unvollständigen Frame konnte er versetzt sein → Magic-Check schlug immer fehl → kein `record_req` → LED5 nie blinkt.

**Diagnose:** Physische Buttons funktionierten → FPGA-Logik OK → Problem nur in `esp32_spi_receiver`.

**Lösung:** CLK-Idle-Timeout (3ms = 30.000 Takte @ 10MHz). Wenn CLK zu lange LOW bleibt, wird `bit_cnt` auf 0 zurückgesetzt → automatische Re-Synchronisierung vor jedem neuen Frame.

**Geänderte Dateien:** `esp32_spi_receiver.sv`

---

## Gesamtstatus

| Feature                            | Status |
|------------------------------------|--------|
| Samsung36 Dekodierung              | ✅     |
| UART-Ausgabe `P:SAM36    A:aaaa C:cc` | ✅  |
| ESP32 SPI-Empfang (alle 8 Slots)   | ✅     |
| Record/Replay über Web-UI          | ✅     |
| LED5 blinkt während Aufnahme       | ✅     |
| Physische Buttons weiter nutzbar   | ✅     |
