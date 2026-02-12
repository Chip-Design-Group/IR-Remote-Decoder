"""
CocoTB Integration Tests for ir_decoder_top.

End-to-end tests: real IR pulses on ir_in_PAD → UART output on uart_tx_PAD.

Tests verify the complete pipeline:
  edge_detector → pulse_timer → nec_decoder → output_formatter → uart_tx
"""

import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles, First
from cocotb_tools.runner import get_runner

from test_helpers import (
    send_nec_ir_frame,
    send_nec_repeat,
    collect_uart_string,
    collect_uart_byte,
    CLK_PERIOD_NS,
)

# UART config: must match uart_tx parameter CLOCKS_PER_BIT
CLOCKS_PER_BIT = 1042  # 10 MHz / 9600 baud
NUM_OUTPUT_BYTES = 10   # "A:xx C:yy\n"


# ============================================================
# Setup Helpers
# ============================================================
async def setup(dut):
    """Start clock, reset DUT, set IR idle HIGH."""
    clock = Clock(dut.clk_PAD, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # IR idle = HIGH (no signal)
    dut.ir_in_PAD.value = 1

    # Reset
    dut.rst_n_PAD.value = 0
    await ClockCycles(dut.clk_PAD, 10)
    dut.rst_n_PAD.value = 1
    await ClockCycles(dut.clk_PAD, 5)


# ============================================================
# Tests
# ============================================================

@cocotb.test()
async def test_reset(dut):
    """All outputs should be in safe state after reset."""
    await setup(dut)

    assert int(dut.uart_tx_PAD.value) == 1, "UART TX should idle HIGH"
    assert int(dut.led_valid_PAD.value) == 0, "led_valid should be 0"
    assert int(dut.led_error_PAD.value) == 0, "led_error should be 0"
    assert int(dut.led_active_PAD.value) == 0, "led_active should be 0"


@cocotb.test()
async def test_led_active_during_reception(dut):
    """led_active should go HIGH when IR signal starts."""
    await setup(dut)

    assert int(dut.led_active_PAD.value) == 0, "Should be 0 before IR signal"

    # Start AGC burst (9ms LOW)
    dut.ir_in_PAD.value = 0
    # Wait long enough for edge detector + pulse timer to detect
    await Timer(9_500_000, unit="ns")  # 9.5ms
    dut.ir_in_PAD.value = 1
    await Timer(500_000, unit="ns")  # small delay for edge propagation

    assert int(dut.led_active_PAD.value) == 1, "led_active should be 1 during reception"


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def test_full_nec_to_uart(dut):
    """End-to-end: Send IR frame (addr=0x00, cmd=0x45) and verify UART output 'A:00 C:45\\n'."""
    await setup(dut)

    # Start UART collector in background
    uart_result = {"text": ""}

    async def uart_collector():
        uart_result["text"] = await collect_uart_string(dut, CLOCKS_PER_BIT, NUM_OUTPUT_BYTES)

    collector = cocotb.start_soon(uart_collector())

    # Send NEC frame
    await send_nec_ir_frame(dut, address=0x00, command=0x45)

    # Wait for UART to finish transmitting all 10 bytes
    # Each byte = (1 start + 8 data + 1 stop) * CLOCKS_PER_BIT clock cycles
    # 10 bytes × 10 bits × 1042 clocks × 100ns = ~10.42ms
    # Plus some margin for output_formatter state transitions
    await Timer(15_000_000, unit="ns")  # 15ms margin

    # Wait for collector to finish
    await collector

    expected = "A:00 C:45\n"
    assert uart_result["text"] == expected, \
        f"Expected UART output '{expected!r}', got '{uart_result['text']!r}'"


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def test_full_nec_to_uart_nonzero_addr(dut):
    """End-to-end: Send IR frame (addr=0xAB, cmd=0xCD) and verify UART output."""
    await setup(dut)

    uart_result = {"text": ""}

    async def uart_collector():
        uart_result["text"] = await collect_uart_string(dut, CLOCKS_PER_BIT, NUM_OUTPUT_BYTES)

    collector = cocotb.start_soon(uart_collector())

    await send_nec_ir_frame(dut, address=0xAB, command=0xCD)
    await Timer(15_000_000, unit="ns")
    await collector

    expected = "A:AB C:CD\n"
    assert uart_result["text"] == expected, \
        f"Expected UART output '{expected!r}', got '{uart_result['text']!r}'"


@cocotb.test(timeout_time=1, timeout_unit="sec")
async def test_two_consecutive_frames(dut):
    """Two NEC frames in sequence should produce two UART strings."""
    await setup(dut)

    # First frame
    uart1 = {"text": ""}

    async def collector1():
        uart1["text"] = await collect_uart_string(dut, CLOCKS_PER_BIT, NUM_OUTPUT_BYTES)

    c1 = cocotb.start_soon(collector1())
    await send_nec_ir_frame(dut, address=0x00, command=0x45)
    await Timer(15_000_000, unit="ns")
    await c1

    assert uart1["text"] == "A:00 C:45\n", f"First frame: got '{uart1['text']!r}'"

    # Small gap between frames
    await Timer(5_000_000, unit="ns")

    # Second frame
    uart2 = {"text": ""}

    async def collector2():
        uart2["text"] = await collect_uart_string(dut, CLOCKS_PER_BIT, NUM_OUTPUT_BYTES)

    c2 = cocotb.start_soon(collector2())
    await send_nec_ir_frame(dut, address=0x04, command=0x08)
    await Timer(15_000_000, unit="ns")
    await c2

    assert uart2["text"] == "A:04 C:08\n", f"Second frame: got '{uart2['text']!r}'"


@cocotb.test(timeout_time=1, timeout_unit="sec")
async def test_repeat_code_to_uart(dut):
    """Repeat code after valid frame should produce the same UART output again."""
    await setup(dut)

    # 1. Send a valid NEC frame
    uart1 = {"text": ""}

    async def collector1():
        uart1["text"] = await collect_uart_string(dut, CLOCKS_PER_BIT, NUM_OUTPUT_BYTES)

    c1 = cocotb.start_soon(collector1())
    await send_nec_ir_frame(dut, address=0x00, command=0x45)
    await Timer(15_000_000, unit="ns")
    await c1

    assert uart1["text"] == "A:00 C:45\n", f"Original frame: got '{uart1['text']!r}'"

    # Small gap (NEC repeat comes 110ms after frame, but we just need some space)
    await Timer(5_000_000, unit="ns")

    # 2. Send repeat code → should trigger same UART output
    uart2 = {"text": ""}

    async def collector2():
        uart2["text"] = await collect_uart_string(dut, CLOCKS_PER_BIT, NUM_OUTPUT_BYTES)

    c2 = cocotb.start_soon(collector2())
    await send_nec_repeat(dut)
    await Timer(15_000_000, unit="ns")
    await c2

    assert uart2["text"] == "A:00 C:45\n", \
        f"Repeat should produce same output, got '{uart2['text']!r}'"


# ============================================================
# pytest runner
# ============================================================
def test_ir_decoder_integration_runner():
    """Build and simulate ir_decoder_top with all sub-modules."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    root_path = proj_path.parent

    sources = [
        proj_path / "src" / "ir_decoder_top.sv",
        root_path / "EdgeDetector" / "src" / "edge_detector.sv",
        root_path / "PulseTimer" / "src" / "pulse_timer.sv",
        root_path / "NECDecoder" / "src" / "nec_decoder.sv",
        root_path / "OutputFormatter" / "src" / "output_formatter.sv",
        root_path / "UART_TX" / "src" / "uart_tx.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ir_decoder_top",
        always=True,
    )

    runner.test(
        hdl_toplevel="ir_decoder_top",
        test_module="test_ir_decoder_integration",
    )


if __name__ == "__main__":
    test_ir_decoder_integration_runner()
