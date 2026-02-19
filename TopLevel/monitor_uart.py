#!/usr/bin/env python3
import argparse
import re
import serial
import serial.tools.list_ports
import sys

FRAME_RE_OLD    = re.compile(rb"^A:[0-9A-F]{2} C:[0-9A-F]{2}")
FRAME_RE_NEW    = re.compile(
    rb"^P:[A-Z0-9 ]{8} A:[0-9A-F]{2,4} C:[0-9A-F]{1,4}"
)
FRAME_RE_SAM36  = re.compile(
    rb"^P:[A-Z0-9 ]{9}\s?A:[0-9A-F]{4}\s+ID:[0-9A-F]\s+C:[0-9A-F]{2}"
)
FRAME_RE_RAW_MS = re.compile(rb"^R L:[01] M:[0-9]{2}\.[0-9]{3} T:[01]\r?\n$")
FRAME_RE_RAW_HEX = re.compile(rb"^R L:[01] W:[0-9A-F]{5} T:[01]\r?\n$")

def find_serial_ports():
    """Lists availables serial ports cross-platform."""
    ports = [p.device for p in serial.tools.list_ports.comports()]
    return ports

def read_from_port(port, baudrate=1000000, verbose=False):
    def process_frame(frame_bytes: bytes):
        if (
            FRAME_RE_NEW.match(frame_bytes)
            or FRAME_RE_SAM36.match(frame_bytes)
            or FRAME_RE_OLD.match(frame_bytes)
            or FRAME_RE_RAW_MS.match(frame_bytes)
            or FRAME_RE_RAW_HEX.match(frame_bytes)
        ):
            frame_text = frame_bytes.decode("ascii").replace("\n", "\\n")
            print(f"Frame: {frame_text}")
            return True
        print(f"Dropped frame ({len(frame_bytes)}B): {frame_bytes!r}")
        return False

    try:
        ser = serial.Serial(port, baudrate, timeout=0.1)
        print(f"Connected to {port} at {baudrate} baud.")
        print("Waiting for data... (Press Ctrl+C to stop)")
        dropped_bytes = 0
        dropped_history = []

        def summarize_drops(history: list[bytes]) -> str:
            if not history:
                return ""
            recent = history[-4:]
            entries = "; ".join(f"{len(chunk)}B:{chunk.hex()}" for chunk in recent)
            if len(history) > len(recent):
                entries += f" (+{len(history) - len(recent)} more)"
            return f": {entries}"

        patterns = [
            FRAME_RE_SAM36,
            FRAME_RE_NEW,
            FRAME_RE_OLD,
            FRAME_RE_RAW_MS,
            FRAME_RE_RAW_HEX,
        ]

        while True:
            line = ser.readline()
            if not line:
                continue
            if verbose:
                for b in line:
                    ch = chr(b) if 32 <= b <= 126 else "."
                    print(f"Received: 0x{b:02x} ({ch})")
            line = line.replace(b"\r", b"")
            buf = line
            while buf:
                matched = False
                for pattern in patterns:
                    m = pattern.match(buf)
                    if not m:
                        continue
                    frame = buf[: m.end()]
                    if not frame.endswith(b"\n"):
                        frame = frame + b"\n"
                    if not process_frame(frame):
                        dropped_bytes += len(frame)
                        dropped_history.append(frame)
                    buf = buf[m.end() :]
                    matched = True
                    break
                if not matched:
                    newline_pos = buf.find(b"\n")
                    if newline_pos == -1:
                        break
                    dropped_fragment = buf[: newline_pos + 1]
                    dropped_bytes += newline_pos + 1
                    dropped_history.append(dropped_fragment)
                    buf = buf[newline_pos + 1 :]
            if dropped_bytes >= 32:
                summary = summarize_drops(dropped_history)
                print(f"Warning: dropped {dropped_bytes} unsynced/invalid bytes{summary}")
                dropped_bytes = 0
                dropped_history.clear()
    except serial.SerialException as e:
        print(f"Error opening serial port {port}: {e}")
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="UART monitor with frame sync for "
                    "'A:xx C:yy\\n', 'P:XXXXXXXX A:xx C:yy\\n', "
                    "'R L:x M:xx.xxx T:x\\n' and legacy 'R L:x W:hhhhh T:x\\n'. "
                    "Works with protocol labels like NEC, SAM32, SAM36, N8X2."
    )
    parser.add_argument("port", nargs="?", help="Serial port (e.g. /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=1000000, help="Baud rate (default: 1000000)")
    parser.add_argument("--verbose", action="store_true", help="Print every received byte")
    args = parser.parse_args()

    ports = find_serial_ports()
    if not ports:
        print("No /dev/ttyUSB ports found. Is the board plugged in?")
        sys.exit(1)
    
    # Arty A7 usually exposes two ports. The second one (higher number) is usually UART.
    # e.g., /dev/ttyUSB1
    ports.sort()
    target_port = ports[-1] # Put your best guess here or ask user
    
    if args.port:
        target_port = args.port
    
    print(f"Found ports: {ports}")
    print(f"Trying to read from: {target_port}")
    read_from_port(target_port, baudrate=args.baud, verbose=args.verbose)
