# WiFi Button – ESP32-C3 IR Remote FPGA Slot Controller

Ein ESP32-C3 Projekt, das einen WLAN-Hotspot aufspannt und eine Web-UI bereitstellt, über die IR-Remote-Slots auf einem FPGA gesteuert werden können.

---

## Übersicht

Der ESP32-C3 betreibt sich als **SoftAP** (eigener WLAN-Hotspot). Verbindet man sich mit diesem Netz, kann man über einen Browser die FPGA-Slots auswählen und **PLAY** oder **REC** Kommandos absenden. Die Kommandos werden seriell (Software-SPI) über zwei GPIOs an das FPGA übertragen.

---

## WLAN-Verbindung

| Parameter | Wert |
|-----------|------|
| SSID | `IR-Remote` |
| Passwort | `12345678` |
| IP-Adresse | `192.168.4.1` |
| Max. Verbindungen | 4 |

Einfach mit dem WLAN `IR-Remote` verbinden und im Browser `http://192.168.4.1` öffnen.

---

## Hardware

### Pinbelegung

| GPIO | Funktion | Bemerkung |
|------|----------|-----------|
| GPIO 4 | `FPGA_DATA` | Serieller Datenpin |
| GPIO 5 | `FPGA_CLK` | Clock (steigende Flanke = Bit sampeln) |
| GND | Gemeinsame Masse | Muss mit FPGA GND verbunden sein |

> ⚠️ **Wichtig:** GPIO2 und GPIO3 sind Strapping-Pins am ESP32-C3 und werden daher **nicht** verwendet.

---

## Serielles Protokoll (Software-SPI)

### Rahmenformat

```
Bit:  7   6   5   4   3   2   1   0
    [  slot[2:0]  ][cmd[1:0]][magic ]
```

| Bits | Bedeutung | Werte |
|------|-----------|-------|
| `[7:5]` | Slot-Adresse | 0–7 |
| `[4:3]` | Kommando | `01` = PLAY, `10` = REC |
| `[2:0]` | Magic (Validierung) | immer `0b101` |

### Frame-Formel

```
frame = (slot << 5) | (cmd << 3) | 0x05
```

### Beispielframes

| Slot | PLAY | REC |
|------|------|-----|
| 0 | `0x0D` | `0x15` |
| 1 | `0x2D` | `0x35` |
| 2 | `0x4D` | `0x55` |
| 3 | `0x6D` | `0x75` |
| 4 | `0x8D` | `0x95` |
| 5 | `0xAD` | `0xB5` |
| 6 | `0xCD` | `0xD5` |
| 7 | `0xED` | `0xF5` |

### Timing

```
         ____      ____      ____
CLK  ___|    |____|    |____|    |___
     _________
DATA X  Bit 7  X  Bit 6  X  Bit 5  X ...
         ↑           ↑           ↑
       sample      sample      sample
```

| Parameter | Wert |
|-----------|------|
| `CLK_HALF_MS` | 1 ms |
| Bitdauer | 2 ms |
| Frame-Dauer (8 Bit) | ~17 ms |
| Baudrate | ~500 Baud |

- Übertragung: **MSB zuerst**
- CLK und DATA im Idle-Zustand: **LOW**
- FPGA sampelt an der **steigenden Flanke** von CLK

---

## Web-UI

### Startseite (`/`)

Zeigt 4 Remote-Karten. Jede Karte repräsentiert 2 FPGA-Slots.

| Remote | Slot A | Slot B |
|--------|--------|--------|
| Remote 1 | Slot 0 | Slot 1 |
| Remote 2 | Slot 2 | Slot 3 |
| Remote 3 | Slot 4 | Slot 5 |
| Remote 4 | Slot 6 | Slot 7 |

### Detailseite (`/remote/<N>`)

Zeigt **PLAY** und **REC** Buttons für die zwei Slots des gewählten Remotes.

### Aktions-Endpunkte

| URL | Aktion |
|-----|--------|
| `/replay/<slot>` | Sendet PLAY-Frame für den Slot |
| `/record/<slot>` | Sendet REC-Frame für den Slot |

Nach der Übertragung erfolgt ein Redirect zurück zur Detailseite des jeweiligen Remotes.

---

## FPGA-Empfänger (Anforderungen)

Das FPGA muss folgende Logik implementieren:

1. **2-FF Synchronizer** für `clk_in` und `data_in`
2. **Rising-Edge-Detektor** auf synchronisiertem `clk_in`
3. **8-Bit Schieberegister** (MSB first), Einlesen bei steigender Flanke
4. **Magic-Prüfung**: `frame[2:0] == 3'b101` → Frame verwerfen, wenn ungültig
5. **Ausgabe** als 1-Takt-Impuls:
   - `replay_req` wenn `cmd == 2'b01`
   - `record_req` wenn `cmd == 2'b10`
   - `slot_addr[2:0]` = `frame[7:5]`

---

## Projektstruktur

```
wifi_button/
├── main/
│   ├── wifi_button.c    # Hauptfirmware
│   └── CMakeLists.txt
├── CMakeLists.txt
└── sdkconfig
```

---

## Build & Flash

```bash
# Projekt konfigurieren
idf.py menuconfig

# Bauen und flashen
idf.py build flash monitor

# Monitor (ohne neu flashen)
idf.py monitor
```

---

## Defines (Konfiguration)

Alle wichtigen Parameter sind als `#define` in `wifi_button.c` oben definiert:

```c
#define WIFI_SSID        "IR-Remote"  // WLAN-Name
#define WIFI_PASS        "12345678"   // WLAN-Passwort (min. 8 Zeichen)
#define WIFI_AP_CHANNEL  1
#define WIFI_AP_MAX_CONN 4

#define FPGA_DATA_PIN    4            // GPIO für DATA
#define FPGA_CLK_PIN     5            // GPIO für CLK

#define CLK_HALF_MS      1            // Halbperiode in ms → ~500 Baud
#define CMD_PLAY         0x01
#define CMD_REC          0x02
#define FRAME_MAGIC      0x05         // 0b101
#define SLOT_COUNT       8
```

---

## Framework

- **ESP-IDF** (Espressif IoT Development Framework)
- **FreeRTOS**
- **ESP HTTP Server** (`esp_http_server`)
