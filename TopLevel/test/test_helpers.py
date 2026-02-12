"""
Helper functions for ir_decoder_top integration testing.

Simulates real IR pulses on ir_in_PAD and captures UART output
from uart_tx_PAD.

Clock: 10 MHz (100ns period)
1 µs = 10 clock cycles
"""

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

CLK_PERIOD_NS = 100  # 10 MHz


def us_to_ns(us):
    """Convert microseconds to nanoseconds."""
    return int(us * 1000)


async def send_ir_mark(dut, duration_us):
    """Drive IR input LOW (active) for the given duration.

    NEC protocol: IR LED ON = receiver output LOW.
    """
    dut.ir_in_PAD.value = 0
    await Timer(us_to_ns(duration_us), unit="ns")


async def send_ir_space(dut, duration_us):
    """Drive IR input HIGH (idle) for the given duration.

    NEC protocol: IR LED OFF = receiver output HIGH.
    """
    dut.ir_in_PAD.value = 1
    await Timer(us_to_ns(duration_us), unit="ns")


async def send_nec_ir_frame(dut, address, command):
    """Send a complete NEC IR frame as real pulse transitions.

    Frame: AGC burst (9ms LOW) + AGC space (4.5ms HIGH)
           + 32 data bits + stop burst (560µs LOW) + idle HIGH

    Each data bit: 560µs LOW burst + space HIGH
      - Logical 0: 560µs space
      - Logical 1: 1690µs space

    Data order: address(8) + ~address(8) + command(8) + ~command(8), LSB first
    """
    addr_inv = (~address) & 0xFF
    cmd_inv = (~command) & 0xFF
    data_32 = address | (addr_inv << 8) | (command << 16) | (cmd_inv << 24)

    # AGC burst: 9ms LOW
    await send_ir_mark(dut, 9000)

    # AGC space: 4.5ms HIGH
    await send_ir_space(dut, 4500)

    # 32 data bits (LSB first)
    for i in range(32):
        bit = (data_32 >> i) & 1
        # Burst: 560µs LOW
        await send_ir_mark(dut, 560)
        # Space: 560µs (bit=0) or 1690µs (bit=1) HIGH
        if bit == 0:
            await send_ir_space(dut, 560)
        else:
            await send_ir_space(dut, 1690)

    # Stop burst: 560µs LOW
    await send_ir_mark(dut, 560)

    # Return to idle HIGH
    dut.ir_in_PAD.value = 1


async def send_nec_repeat(dut):
    """Send a NEC repeat code as real pulse transitions.

    Repeat: AGC burst (9ms LOW) + repeat space (2.25ms HIGH) + stop burst (560µs LOW)
    """
    await send_ir_mark(dut, 9000)
    await send_ir_space(dut, 2250)
    await send_ir_mark(dut, 560)
    dut.ir_in_PAD.value = 1


async def collect_uart_byte(dut, clocks_per_bit):
    """Wait for UART start bit and sample one full byte from uart_tx_PAD.

    UART 8N1: Start(0) + 8 data bits (LSB first) + Stop(1)

    Returns: int (the received byte)
    """
    # Wait for start bit (falling edge on tx line)
    while int(dut.uart_tx_PAD.value) == 1:
        await RisingEdge(dut.clk_PAD)

    # Sample at center of start bit
    await ClockCycles(dut.clk_PAD, clocks_per_bit // 2)
    assert int(dut.uart_tx_PAD.value) == 0, "Start bit should be 0"

    # Sample 8 data bits at center
    byte_val = 0
    for i in range(8):
        await ClockCycles(dut.clk_PAD, clocks_per_bit)
        bit = int(dut.uart_tx_PAD.value)
        byte_val |= (bit << i)

    # Sample stop bit
    await ClockCycles(dut.clk_PAD, clocks_per_bit)
    assert int(dut.uart_tx_PAD.value) == 1, "Stop bit should be 1"

    return byte_val


async def collect_uart_string(dut, clocks_per_bit, num_bytes):
    """Collect multiple UART bytes and return as string.

    Args:
        dut: Device under test
        clocks_per_bit: UART baud rate divider
        num_bytes: Number of bytes to collect

    Returns: str (decoded ASCII string)
    """
    chars = []
    for _ in range(num_bytes):
        byte_val = await collect_uart_byte(dut, clocks_per_bit)
        chars.append(chr(byte_val))
    return "".join(chars)
