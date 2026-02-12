#!/usr/bin/env python3
import serial
import sys
import serial
import serial.tools.list_ports
import sys
import time

def find_serial_ports():
    """Lists availables serial ports cross-platform."""
    ports = [p.device for p in serial.tools.list_ports.comports()]
    return ports

def read_from_port(port, baudrate=9600):
    try:
        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"Connected to {port} at {baudrate} baud.")
        print("Waiting for data... (Press Ctrl+C to stop)")
        
        while True:
            if ser.in_waiting > 0:
                # Read one byte
                data = ser.read(1)
                # Print hex and ASCII representation
                hex_val = data.hex()
                try:
                    ascii_val = data.decode('ascii')
                    if not ascii_val.isprintable():
                        ascii_val = '.'
                except UnicodeDecodeError:
                    ascii_val = '.'
                
                print(f"Received: 0x{hex_val} ({ascii_val})")
                
            time.sleep(0.01)

    except serial.SerialException as e:
        print(f"Error opening serial port {port}: {e}")
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    ports = find_serial_ports()
    if not ports:
        print("No /dev/ttyUSB ports found. Is the board plugged in?")
        sys.exit(1)
    
    # Arty A7 usually exposes two ports. The second one (higher number) is usually UART.
    # e.g., /dev/ttyUSB1
    ports.sort()
    target_port = ports[-1] # Put your best guess here or ask user
    
    if len(sys.argv) > 1:
        target_port = sys.argv[1]
    
    print(f"Found ports: {ports}")
    print(f"Trying to read from: {target_port}")
    read_from_port(target_port)
