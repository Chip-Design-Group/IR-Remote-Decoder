"""
CocoTB Unit Tests for output_formatter module.

Tests the ASCII hex formatting FSM in isolation:
- Correct byte sequence "A:xx C:yy\n"
- Handshake with UART (uart_ready / uart_tx_req)
- Multiple frames in sequence
- Various address/command values

The test simulates a fake UART by toggling uart_ready.
"""

import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 100  # 10 MHz


# ============================================================
# Helpers
# ============================================================
async def setup(dut):
    """Start clock and reset DUT."""
    # Start the clock
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # Apply reset and initialize inputs
    dut.rst_n.value = 0
    dut.address.value = 0
    dut.command.value = 0
    dut.valid_in.value = 0
    dut.decode_error.value = 0
    dut.uart_ready.value = 1  # UART initially ready

    await ClockCycles(dut.clk, 5)  # Hold reset for 5 cycles
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)  # Wait a few cycles after reset


async def trigger_valid(dut, address, command):
    """Pulse valid_in for 1 clock cycle with the given address and command."""
    dut.address.value = address
    dut.command.value = command
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0


async def collect_bytes(dut, num_bytes):
    """Collect bytes sent via uart_tx_req / uart_data handshake.

    Simulates a UART that is always ready (uart_ready stays HIGH).
    Captures data on each uart_tx_req pulse.
    Returns a list of integer byte values.
    """
    result = []
    for _ in range(num_bytes):
        timeout = 0
        # Wait for uart_tx_req to go high
        while int(dut.uart_tx_req.value) == 0:
            await RisingEdge(dut.clk)
            timeout += 1
            if timeout > 500:
                raise TimeoutError(f"Timeout waiting for byte {len(result)}")

        # Capture the data byte when uart_tx_req is asserted
        result.append(int(dut.uart_data.value))

        # Wait for uart_tx_req to deassert before capturing the next byte
        await RisingEdge(dut.clk)

    return result


def bytes_to_str(byte_list):
    """Convert list of ints to string."""
    return "".join(chr(b) for b in byte_list)


def nibble_to_hex_char(n):
    """Convert a 4-bit nibble to its ASCII hex character."""
    return chr(0x30 + n) if n < 10 else chr(0x41 + n - 10)


def expected_string(addr, cmd):
    """Build the expected output string for a given address and command."""
    return (
        "A:"
        + nibble_to_hex_char((addr >> 4) & 0xF)
        + nibble_to_hex_char(addr & 0xF)
        + " C:"
        + nibble_to_hex_char((cmd >> 4) & 0xF)
        + nibble_to_hex_char(cmd & 0xF)
        + "\n"
    )


# ============================================================
# Tests
# ============================================================

@cocotb.test()
async def test_reset(dut):
    """Check that after reset, uart_tx_req is 0 and nothing is being transmitted."""
    await setup(dut)
    assert int(dut.uart_tx_req.value) == 0, "uart_tx_req should be 0 after reset"


@cocotb.test()
async def test_basic_output_00_45(dut):
    """Test that sending address=0x00, command=0x45 produces 'A:00 C:45\\n'."""
    await setup(dut)
    await trigger_valid(dut, address=0x00, command=0x45)

    result = await collect_bytes(dut, 10)
    output = bytes_to_str(result)

    assert output == "A:00 C:45\n", f"Expected 'A:00 C:45\\n', got {output!r}"


@cocotb.test()
async def test_output_FF_FF(dut):
    """Test maximum values: address=0xFF, command=0xFF → 'A:FF C:FF\\n'."""
    await setup(dut)
    await trigger_valid(dut, address=0xFF, command=0xFF)

    result = await collect_bytes(dut, 10)
    output = bytes_to_str(result)

    assert output == "A:FF C:FF\n", f"Expected 'A:FF C:FF\\n', got {output!r}"


@cocotb.test()
async def test_output_AB_CD(dut):
    """Test typical middle-range values: address=0xAB, command=0xCD."""
    await setup(dut)
    await trigger_valid(dut, address=0xAB, command=0xCD)

    result = await collect_bytes(dut, 10)
    output = bytes_to_str(result)

    assert output == "A:AB C:CD\n", f"Expected 'A:AB C:CD\\n', got {output!r}"


@cocotb.test()
async def test_output_lower_nibbles(dut):
    """Test lower and upper nibbles: address=0x19, command=0xEF → 'A:19 C:EF\\n'."""
    await setup(dut)

    await trigger_valid(dut, address=0x19, command=0xEF)

    result = await collect_bytes(dut, 10)
    output = bytes_to_str(result)

    assert output == "A:19 C:EF\n", f"Got {output!r}"


@cocotb.test()
async def test_state_transitions(dut):
    """Ensure FSM transitions through all states correctly for a single frame."""
    await setup(dut)

    await trigger_valid(dut, address=0x00, command=0x00)
    await RisingEdge(dut.clk)

    # Collect all bytes - this implicitly tests state transitions
    result = await collect_bytes(dut, 10)
    await ClockCycles(dut.clk, 3)

    # Verify we got all bytes correctly
    assert len(result) == 10, f"Should have received 10 bytes, got {len(result)}"


@cocotb.test()
async def test_uart_tx_req_is_single_cycle(dut):
    """Verify uart_tx_req is asserted for exactly 1 clock cycle per byte."""
    await setup(dut)
    await trigger_valid(dut, address=0x00, command=0x00)

    # Wait for the first byte to be requested
    while int(dut.uart_tx_req.value) == 0:
        await RisingEdge(dut.clk)

    # Should be HIGH for 1 cycle only
    assert int(dut.uart_tx_req.value) == 1


@cocotb.test()
async def test_waits_for_uart_ready(dut):
    """Formatter should pause transmission if uart_ready is low."""
    await setup(dut)
    dut.uart_ready.value = 0  # Simulate UART busy

    await trigger_valid(dut, address=0x00, command=0x00)

    # Should not send anything while UART not ready
    await ClockCycles(dut.clk, 10)
    assert int(dut.uart_tx_req.value) == 0, "Should not send when UART not ready"

    # Make UART ready again
    dut.uart_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Now it should start sending
    assert int(dut.uart_tx_req.value) == 1, "Should send when UART becomes ready"


@cocotb.test()
async def test_two_consecutive_outputs(dut):
    """Sending two frames back-to-back should produce two complete outputs."""
    await setup(dut)

    # First frame
    await trigger_valid(dut, address=0x00, command=0x45)
    r1 = await collect_bytes(dut, 10)
    await ClockCycles(dut.clk, 5)

    # Second frame
    await trigger_valid(dut, address=0xAB, command=0xCD)
    r2 = await collect_bytes(dut, 10)

    assert bytes_to_str(r1) == "A:00 C:45\n", f"First frame: {bytes_to_str(r1)!r}"
    assert bytes_to_str(r2) == "A:AB C:CD\n", f"Second frame: {bytes_to_str(r2)!r}"


@cocotb.test()
async def test_byte_sequence_exact(dut):
    """Verify individual byte values for address=0x3F, command=0xA0."""
    await setup(dut)
    await trigger_valid(dut, address=0x3F, command=0xA0)

    result = await collect_bytes(dut, 10)
    expected = [
        0x41,  # 'A'
        0x3A,  # ':'
        0x33,  # '3'
        0x46,  # 'F'
        0x20,  # ' '
        0x43,  # 'C'
        0x3A,  # ':'
        0x41,  # 'A'
        0x30,  # '0'
        0x0A,  # '\n'
    ]

    assert result == expected, f"Expected {[hex(b) for b in expected]}, got {[hex(b) for b in result]}"


@cocotb.test(timeout_time=300, timeout_unit="sec")
async def test_all_256x256_combinations(dut):
    """Exhaustive test: verify all 65536 address/command combinations."""
    await setup(dut)

    fail_count = 0
    first_fail = None

    for addr in range(256):
        for cmd in range(256):
            await trigger_valid(dut, address=addr, command=cmd)
            result = await collect_bytes(dut, 10)
            output = bytes_to_str(result)
            exp = expected_string(addr, cmd)

            if output != exp:
                fail_count += 1
                if first_fail is None:
                    first_fail = (addr, cmd, output, exp)

        # Log progress every 16 addresses
        if addr % 16 == 15:
            dut._log.info(f"Progress: {addr+1}/256 addresses done")

    assert fail_count == 0, (
        f"{fail_count} failures! First failure: "
        f"addr=0x{first_fail[0]:02X} cmd=0x{first_fail[1]:02X} "
        f"got {first_fail[2]!r}, expected {first_fail[3]!r}"
    )
    
def test_output_formatter_runner():
    """Simulate the output_formatter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "output_formatter.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="output_formatter",
        always=True,
    )

    runner.test(
        hdl_toplevel="output_formatter",
        test_module="test_output_formatter",
    )


if __name__ == "__main__":
    test_output_formatter_runner()