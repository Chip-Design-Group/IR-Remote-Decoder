"""
CocoTB Tests for nec_decoder module.

Tests the NEC protocol FSM including:
- Valid frame decoding (address + command)
- Checksum validation
- Timeout handling
- Multiple frames in sequence
- Error recovery
- Repeat codes

pulse_width unit: 1 count = 1 clock cycle @ 10 MHz (100ns)
"""

import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles
from cocotb_tools.runner import get_runner

# ============================================================
# Timing Constants
# pulse_width in clock cycles @ 10 MHz (1 cycle = 100ns)
# ============================================================
CLK_PERIOD_NS = 100  # 10 MHz

# NEC protocol timings in clock cycles
AGC_BURST    = 90000   # 9.0 ms
AGC_SPACE    = 45000   # 4.5 ms
REPEAT_SPACE = 22500   # 2.25 ms
BIT_BURST    = 5600    # 560 µs
BIT0_SPACE   = 5600    # 560 µs  (logical 0)
BIT1_SPACE   = 16900   # 1.69 ms (logical 1)


# ============================================================
# Result Monitor
# ============================================================
class NecResult:
    """Captures decode results including transient pulses."""
    def __init__(self):
        self.data_valid = False
        self.decode_error = False
        self.address = 0
        self.command = 0

    def reset(self):
        self.data_valid = False
        self.decode_error = False
        self.address = 0
        self.command = 0


async def monitor_results(dut, result):
    """Monitor data_valid, decode_error and repeat_valid, capturing single-cycle pulses."""
    while True:
        await RisingEdge(dut.clk)
        if dut.data_valid.value == 1:
            result.data_valid = True
            result.address = int(dut.address.value)
            result.command = int(dut.command.value)
        if dut.decode_error.value == 1:
            result.decode_error = True


# ============================================================
# Helper Functions
# ============================================================
async def setup_clock(dut):
    """Create and start a 10 MHz clock."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())


async def setup_test(dut):
    """Setup clock, reset, and start result monitor. Returns NecResult."""
    await setup_clock(dut)
    result = NecResult()
    cocotb.start_soon(monitor_results(dut, result))
    await reset_dut(dut)
    return result


async def reset_dut(dut):
    """Apply reset and initialize all inputs."""
    dut.rst_n.value = 0
    dut.pulse_done.value = 0
    dut.pulse_width.value = 0
    dut.pulse_level.value = 0
    dut.timeout.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def send_pulse(dut, width, level):
    """Send a single pulse event to the decoder.

    Args:
        dut: Device under test
        width: Pulse width in clock cycles
        level: 0=LOW pulse, 1=HIGH pulse
    """
    dut.pulse_done.value = 1
    dut.pulse_width.value = width
    dut.pulse_level.value = level
    await RisingEdge(dut.clk)
    dut.pulse_done.value = 0
    dut.pulse_width.value = 0
    dut.pulse_level.value = 0
    await RisingEdge(dut.clk)


async def send_nec_frame(dut, address, command):
    """Send a complete valid NEC frame.

    Args:
        dut: Device under test
        address: 8-bit address (0x00 - 0xFF)
        command: 8-bit command (0x00 - 0xFF)
    """
    # 1. AGC Burst (LOW pulse, 9ms)
    await send_pulse(dut, AGC_BURST, 0)

    # 2. AGC Space (HIGH pulse, 4.5ms)
    await send_pulse(dut, AGC_SPACE, 1)

    # Build 32-bit data: address + ~address + command + ~command
    addr_inv = (~address) & 0xFF
    cmd_inv = (~command) & 0xFF
    data_32 = address | (addr_inv << 8) | (command << 16) | (cmd_inv << 24)

    # 3. Send 32 data bits (LSB first)
    for i in range(32):
        bit = (data_32 >> i) & 1

        # Each bit: burst (LOW) + space (HIGH)
        await send_pulse(dut, BIT_BURST, 0)
        if bit == 0:
            await send_pulse(dut, BIT0_SPACE, 1)
        else:
            await send_pulse(dut, BIT1_SPACE, 1)

    # 4. Final stop burst (560µs LOW pulse)
    await send_pulse(dut, BIT_BURST, 0)

    # Wait for processing
    await ClockCycles(dut.clk, 5)


async def send_repeat_code(dut):
    """Send a NEC repeat code.

    Repeat code: AGC burst (9ms) + Short space (2.25ms) + Stop burst (560µs)
    """
    await send_pulse(dut, AGC_BURST, 0)
    await send_pulse(dut, REPEAT_SPACE, 1)
    await send_pulse(dut, BIT_BURST, 0)
    await ClockCycles(dut.clk, 5)


async def send_bad_checksum_frame(dut, address, command, bad_addr_inv, bad_cmd_inv):
    """Send a NEC frame with intentionally wrong checksum."""
    await send_pulse(dut, AGC_BURST, 0)
    await send_pulse(dut, AGC_SPACE, 1)

    data_32 = address | (bad_addr_inv << 8) | (command << 16) | (bad_cmd_inv << 24)

    for i in range(32):
        bit = (data_32 >> i) & 1
        await send_pulse(dut, BIT_BURST, 0)
        if bit == 0:
            await send_pulse(dut, BIT0_SPACE, 1)
        else:
            await send_pulse(dut, BIT1_SPACE, 1)

    await send_pulse(dut, BIT_BURST, 0)
    await ClockCycles(dut.clk, 5)


# ============================================================
# Tests
# ============================================================

@cocotb.test()
async def test_reset(dut):
    """Test that reset initializes all outputs correctly."""
    await setup_clock(dut)
    await reset_dut(dut)

    assert dut.data_valid.value == 0, "data_valid should be 0 after reset"
    assert dut.decode_error.value == 0, "decode_error should be 0 after reset"
    assert dut.address.value == 0, "address should be 0 after reset"
    assert dut.command.value == 0, "command should be 0 after reset"
    assert dut.receiving.value == 0, "receiving should be 0 after reset"


@cocotb.test()
async def test_decode_valid_frame_power_button(dut):
    """Test decoding of Samsung TV Power button (Addr=0x00, Cmd=0x45)."""
    result = await setup_test(dut)
    await send_nec_frame(dut, address=0x00, command=0x45)

    assert result.data_valid, "data_valid should have pulsed for valid frame"
    assert result.address == 0x00, f"Expected address 0x00, got {hex(result.address)}"
    assert result.command == 0x45, f"Expected command 0x45, got {hex(result.command)}"
    assert not result.decode_error, "decode_error should not have pulsed"


@cocotb.test()
async def test_decode_valid_frame_mute_button(dut):
    """Test decoding of Mute button (Addr=0x00, Cmd=0x46)."""
    result = await setup_test(dut)
    await send_nec_frame(dut, address=0x00, command=0x46)

    assert result.data_valid, "data_valid should have pulsed"
    assert result.address == 0x00, f"Expected address 0x00, got {hex(result.address)}"
    assert result.command == 0x46, f"Expected command 0x46, got {hex(result.command)}"


@cocotb.test()
async def test_decode_different_address(dut):
    """Test decoding with a non-zero address (LG TV: Addr=0x04, Cmd=0x08)."""
    result = await setup_test(dut)
    await send_nec_frame(dut, address=0x04, command=0x08)

    assert result.data_valid, "data_valid should have pulsed"
    assert result.address == 0x04, f"Expected address 0x04, got {hex(result.address)}"
    assert result.command == 0x08, f"Expected command 0x08, got {hex(result.command)}"


@cocotb.test()
async def test_decode_all_ones(dut):
    """Test with address=0xFF, command=0xFF."""
    result = await setup_test(dut)
    await send_nec_frame(dut, address=0xFF, command=0xFF)

    assert result.data_valid, "data_valid should have pulsed"
    assert result.address == 0xFF, f"Expected address 0xFF, got {hex(result.address)}"
    assert result.command == 0xFF, f"Expected command 0xFF, got {hex(result.command)}"


@cocotb.test()
async def test_checksum_error_bad_address(dut):
    """Test that a bad address checksum triggers decode_error."""
    result = await setup_test(dut)

    await send_bad_checksum_frame(dut,
        address=0x00, command=0x45,
        bad_addr_inv=0x00, bad_cmd_inv=0xBA)

    assert result.decode_error, "decode_error should have pulsed for bad checksum"
    assert not result.data_valid, "data_valid should not have pulsed for bad checksum"


@cocotb.test()
async def test_checksum_error_bad_command(dut):
    """Test that a bad command checksum triggers decode_error."""
    result = await setup_test(dut)

    await send_bad_checksum_frame(dut,
        address=0x00, command=0x45,
        bad_addr_inv=0xFF, bad_cmd_inv=0x45)

    assert result.decode_error, "decode_error should have pulsed"
    assert not result.data_valid, "data_valid should not have pulsed"


@cocotb.test()
async def test_timeout_during_data(dut):
    """Test that timeout during data reception resets the FSM."""
    await setup_clock(dut)
    await reset_dut(dut)

    await send_pulse(dut, AGC_BURST, 0)
    await send_pulse(dut, AGC_SPACE, 1)

    for _ in range(5):
        await send_pulse(dut, BIT_BURST, 0)
        await send_pulse(dut, BIT0_SPACE, 1)

    dut.timeout.value = 1
    await RisingEdge(dut.clk)
    dut.timeout.value = 0
    await ClockCycles(dut.clk, 3)

    assert dut.data_valid.value == 0, "data_valid should be 0 after timeout"
    assert dut.receiving.value == 0, "receiving should be 0 after timeout"


@cocotb.test()
async def test_receiving_signal(dut):
    """Test that receiving signal is high during active decoding."""
    await setup_clock(dut)
    await reset_dut(dut)

    assert dut.receiving.value == 0, "receiving should be 0 in IDLE"

    await send_pulse(dut, AGC_BURST, 0)
    assert dut.receiving.value == 1, "receiving should be 1 after AGC burst"

    await send_pulse(dut, AGC_SPACE, 1)
    assert dut.receiving.value == 1, "receiving should be 1 during SPACE"


@cocotb.test()
async def test_two_consecutive_frames(dut):
    """Test decoding two valid frames back-to-back."""
    result = await setup_test(dut)

    await send_nec_frame(dut, address=0x00, command=0x45)
    assert result.data_valid, "First frame: data_valid should have pulsed"
    assert result.command == 0x45, "First frame: wrong command"

    result.reset()

    await send_nec_frame(dut, address=0x00, command=0x46)
    assert result.data_valid, "Second frame: data_valid should have pulsed"
    assert result.command == 0x46, "Second frame: wrong command"


@cocotb.test()
async def test_data_valid_is_pulse(dut):
    """Test that data_valid is a single-cycle pulse, not held HIGH."""
    result = await setup_test(dut)
    await send_nec_frame(dut, address=0x00, command=0x45)

    assert result.data_valid, "data_valid should have pulsed"
    assert dut.data_valid.value == 0, "data_valid should be 0 now (was only a pulse)"


@cocotb.test()
async def test_recovery_after_error(dut):
    """Test that FSM recovers and can decode after an error."""
    result = await setup_test(dut)

    await send_bad_checksum_frame(dut,
        address=0x00, command=0x45,
        bad_addr_inv=0x00, bad_cmd_inv=0x00)

    assert result.decode_error, "Should have error"

    result.reset()

    await send_nec_frame(dut, address=0x00, command=0x45)
    assert result.data_valid, "Should decode valid frame after error"
    assert result.command == 0x45, "Command should be 0x45"


# ============================================================
# Repeat Code Tests
# ============================================================

@cocotb.test()
async def test_repeat_after_valid_frame(dut):
    """Test that repeat code works after a valid frame."""
    result = await setup_test(dut)

    # First: send a valid frame
    await send_nec_frame(dut, address=0x00, command=0x45)
    assert result.data_valid, "Frame should be valid"
    assert result.address == 0x00
    assert result.command == 0x45

    # Reset monitor
    result.reset()

    # Send repeat code
    await send_repeat_code(dut)
    assert result.data_valid, "data_valid should pulse (repeat)"
    
    # Address and command should still be the same
    assert dut.address.value == 0x00, "Address should remain from last frame"
    assert dut.command.value == 0x45, "Command should remain from last frame"


@cocotb.test()
async def test_repeat_without_prior_frame(dut):
    """Test that repeat code is ignored when no valid frame was decoded first."""
    result = await setup_test(dut)

    # Send repeat code without a prior frame
    await send_repeat_code(dut)
    assert not result.data_valid, "repeat should be ignored (no prior frame)"


@cocotb.test()
async def test_repeat_missing_final_burst_is_ignored(dut):
    """A truncated repeat (without final 560us LOW burst) must not trigger data_valid."""
    result = await setup_test(dut)

    # Seed a known last-valid frame
    await send_nec_frame(dut, address=0x00, command=0x45)
    assert result.data_valid, "Frame should be valid"

    # Clear monitor and send only AGC + repeat space (missing trailing burst)
    result.reset()
    await send_pulse(dut, AGC_BURST, 0)
    await send_pulse(dut, REPEAT_SPACE, 1)
    await ClockCycles(dut.clk, 5)

    assert not result.data_valid, "Truncated repeat must be ignored"


@cocotb.test()
async def test_multiple_repeats(dut):
    """Test multiple repeat codes in sequence (button held down)."""
    result = await setup_test(dut)

    # Send valid frame first
    await send_nec_frame(dut, address=0x04, command=0x08)
    assert result.data_valid, "Frame should be valid"

    # Send 3 repeat codes
    for i in range(3):
        result.reset()
        await send_repeat_code(dut)
        assert result.data_valid, f"Repeat {i+1}: data_valid should have pulsed"

    # Address/command should still be from original frame
    assert dut.address.value == 0x04, "Address should remain"
    assert dut.command.value == 0x08, "Command should remain"


# ============================================================
# pytest runner
# ============================================================
def test_nec_decoder_runner():
    """Simulate the nec_decoder using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "nec_decoder.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="nec_decoder",
        always=True,
    )

    runner.test(
        hdl_toplevel="nec_decoder",
        test_module="test_nec_decoder",
    )


if __name__ == "__main__":
    test_nec_decoder_runner()
