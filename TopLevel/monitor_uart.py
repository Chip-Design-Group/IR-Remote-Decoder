#!/usr/bin/env python3
import argparse
import re
import serial
import serial.tools.list_ports
import sys

FRAME_RE = re.compile(rb"^A:[0-9A-F]{2} C:[0-9A-F]{2}\n$")

def find_serial_ports():
    """Lists availables serial ports cross-platform."""
    ports = [p.device for p in serial.tools.list_ports.comports()]
    return ports

def read_from_port(port, baudrate=9600, verbose=False):
    try:
        ser = serial.Serial(port, baudrate, timeout=0.1)
        print(f"Connected to {port} at {baudrate} baud.")
        print("Waiting for data... (Press Ctrl+C to stop)")
        frame_buf = bytearray()
        dropped_bytes = 0
        
        while True:
            # Read all currently available bytes to avoid overrun.
            n = ser.in_waiting
            data = ser.read(n if n > 0 else 1)
            if not data:
                continue

            for b in data:
                if verbose:
                    ch = chr(b) if 32 <= b <= 126 else "."
                    print(f"Received: 0x{b:02x} ({ch})")

                # Frame sync: only start collecting on 'A'.
                if not frame_buf:
                    if b == ord("A"):
                        frame_buf.append(b)
                    else:
                        dropped_bytes += 1
                    continue

                frame_buf.append(b)

                # Prevent runaway if stream is corrupted.
                if len(frame_buf) > 32:
                    frame_buf.clear()
                    dropped_bytes += 1
                    continue

                # End of frame on newline.
                if b == 0x0A:
                    frame = bytes(frame_buf)
                    if FRAME_RE.match(frame):
                        frame_text = frame.decode("ascii").replace("\n", "\\n")
                        print(f"Frame: {frame_text}")
                    else:
                        dropped_bytes += len(frame)
                        if verbose:
                            print(f"Dropped invalid frame: {frame!r}")
                    frame_buf.clear()

            if dropped_bytes >= 32:
                print(f"Warning: dropped {dropped_bytes} unsynced/invalid bytes")
                dropped_bytes = 0

    except serial.SerialException as e:
        print(f"Error opening serial port {port}: {e}")
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UART monitor with frame sync for A:xx C:yy\\n")
    parser.add_argument("port", nargs="?", help="Serial port (e.g. /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=9600, help="Baud rate (default: 9600)")
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
