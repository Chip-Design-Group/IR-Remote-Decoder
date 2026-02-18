"""
CocoTB Unit Tests for output_formatter module.

Tests the ASCII hex formatting FSM in isolation:
- Correct byte sequence "P:XXXXXXXX A:xx C:yy\n"
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
FRAME_LEN_STD = 21
FRAME_LEN_S32 = 25
FRAME_LEN_S36 = 28
FRAME_LEN_S48 = 25
FRAME_LEN = FRAME_LEN_STD  # default for most tests


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
    dut.protocol_id.value = 0
    dut.valid_in.value = 0
    dut.decode_error.value = 0
    dut.uart_ready.value = 1  # UART initially ready
    dut.frame_data.value = 0
    dut.frame_bits.value = 0

    await ClockCycles(dut.clk, 5)  # Hold reset for 5 cycles
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)  # Wait a few cycles after reset


async def trigger_valid(dut, address, command, protocol_id=1, frame_data=0, frame_bits=32):
    """Pulse valid_in for 1 clock cycle with the given address and command."""
    dut.address.value = address
    dut.command.value = command
    dut.protocol_id.value = protocol_id
    dut.frame_data.value = frame_data
    dut.frame_bits.value = frame_bits
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


def protocol_label(protocol_id):
    if protocol_id == 1:
        return "NEC     "
    if protocol_id == 2:
        return "ONKYO   "
    if protocol_id == 3:
        return "APPLE   "
    if protocol_id == 8:
        return "SAM32   "
    if protocol_id == 9:
        return "SAM48   "
    return "UNK     "


def expected_standard(addr, cmd, protocol_id=1):
    """Build the expected output string for a standard NEC-style frame."""
    return (
        "P:"
        + protocol_label(protocol_id)
        + " A:"
        + f"{addr:02X}"
        + " C:"
        + f"{cmd:02X}"
        + "\n"
    )


def expected_sam32(addr16, cmd16):
    """Build the expected output string for Sam32 (full 16-bit address & command)."""
    return f"P:SAM32   A:{addr16:04X} C:{cmd16:04X}\n"


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
    """Test that sending address=0x00, command=0x45 produces NEC-prefixed output."""
    await setup(dut)
    await trigger_valid(dut, address=0x00, command=0x45)

    result = await collect_bytes(dut, FRAME_LEN)
    output = bytes_to_str(result)

    assert output == expected_standard(0x00, 0x45), f"Unexpected output {output!r}"


@cocotb.test()
async def test_output_FF_FF(dut):
    """Test maximum values: address=0xFF, command=0xFF."""
    await setup(dut)
    await trigger_valid(dut, address=0xFF, command=0xFF)

    result = await collect_bytes(dut, FRAME_LEN)
    output = bytes_to_str(result)

    assert output == expected_standard(0xFF, 0xFF), f"Unexpected output {output!r}"


@cocotb.test()
async def test_output_AB_CD(dut):
    """Test typical middle-range values: address=0xAB, command=0xCD."""
    await setup(dut)
    await trigger_valid(dut, address=0xAB, command=0xCD)

    result = await collect_bytes(dut, FRAME_LEN)
    output = bytes_to_str(result)

    assert output == expected_standard(0xAB, 0xCD), f"Unexpected output {output!r}"


@cocotb.test()
async def test_output_lower_nibbles(dut):
    """Test lower and upper nibbles: address=0x19, command=0xEF → 'A:19 C:EF\\n'."""
    await setup(dut)

    await trigger_valid(dut, address=0x19, command=0xEF)

    result = await collect_bytes(dut, FRAME_LEN)
    output = bytes_to_str(result)

    assert output == expected_standard(0x19, 0xEF), f"Got {output!r}"


@cocotb.test()
async def test_state_transitions(dut):
    """Ensure FSM transitions through all states correctly for a single frame."""
    await setup(dut)

    await trigger_valid(dut, address=0x00, command=0x00)
    await RisingEdge(dut.clk)

    # Collect all bytes - this implicitly tests state transitions
    result = await collect_bytes(dut, FRAME_LEN)
    await ClockCycles(dut.clk, 3)

    # Verify we got all bytes correctly
    assert len(result) == FRAME_LEN, f"Should have received {FRAME_LEN} bytes, got {len(result)}"


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
    r1 = await collect_bytes(dut, FRAME_LEN)
    await ClockCycles(dut.clk, 5)

    # Second frame
    await trigger_valid(dut, address=0xAB, command=0xCD)
    r2 = await collect_bytes(dut, FRAME_LEN)

    assert bytes_to_str(r1) == expected_standard(0x00, 0x45), f"First frame: {bytes_to_str(r1)!r}"
    assert bytes_to_str(r2) == expected_standard(0xAB, 0xCD), f"Second frame: {bytes_to_str(r2)!r}"


@cocotb.test()
async def test_byte_sequence_exact(dut):
    """Verify individual byte values for address=0x3F, command=0xA0 (NEC)."""
    await setup(dut)
    await trigger_valid(dut, address=0x3F, command=0xA0)

    result = await collect_bytes(dut, FRAME_LEN)
    expected = [
        0x50,  # 'P'
        0x3A,  # ':'
        0x4E,  # 'N'
        0x45,  # 'E'
        0x43,  # 'C'
        0x20,  # ' '
        0x20,  # ' '
        0x20,  # ' '
        0x20,  # ' '
        0x20,  # ' '
        0x20,  # ' '
        0x41,  # 'A'
        0x3A,  # ':'
        0x43,  # 'C'
        0x30,  # '0'
        0x33,  # '3'
        0x46,  # 'F'
        0x20,  # ' '
        0x43,  # 'C'
        0x3A,  # ':'
        0x35,  # '5'
        0x46,  # 'F'
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
            result = await collect_bytes(dut, FRAME_LEN)
            output = bytes_to_str(result)
            exp = expected_standard(addr, cmd, protocol_id=1)

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


@cocotb.test()
async def test_sam32_protocol_prefix(dut):
    """Protocol label should switch to SAM32 for protocol_id=8."""
    await setup(dut)
    await trigger_valid(dut, address=0x07, command=0x99, protocol_id=8)
    result = await collect_bytes(dut, FRAME_LEN_STD)
    output = bytes_to_str(result)
    assert output == expected_sam32(0x0000, 0x0000), f"Unexpected output {output!r}"


@cocotb.test()
async def test_sam32_full_output(dut):
    """Sam32 should emit 16-bit address and command pairs."""
    await setup(dut)
    frame_data_val = (0xAB << 24) | (0xCD << 16) | (0x12 << 8) | 0x34
    await trigger_valid(
        dut,
        address=0x34,
        command=0xCD,
        protocol_id=8,
        frame_data=frame_data_val,
        frame_bits=32
    )
    result = await collect_bytes(dut, FRAME_LEN_S32)
    output = bytes_to_str(result)
    assert output == expected_sam32(0x1234, 0xABCD), f"Unexpected Sam32 output {output!r}"


@cocotb.test()
async def test_samsung36_id_field(dut):
    """Samsung36 output should include the 4-bit ID nibble from frame_data."""
    await setup(dut)
    frame_data_val = (0x8877 << 32) | (0xA << 28)
    await trigger_valid(
        dut,
        address=0x77,
        command=0x0F,
        protocol_id=9,
        frame_data=frame_data_val,
        frame_bits=36
    )
    result = await collect_bytes(dut, FRAME_LEN_S36)
    output = bytes_to_str(result)
    assert output == "P:SAM36    A:8877 ID:A C:0F\n", f"Unexpected output {output!r}"


@cocotb.test()
async def test_onkyo_protocol_prefix(dut):
    """Protocol label should switch to ONKYO for protocol_id=2."""
    await setup(dut)
    await trigger_valid(dut, address=0x12, command=0x56, protocol_id=2)
    result = await collect_bytes(dut, FRAME_LEN_STD)
    output = bytes_to_str(result)
    assert output == expected_standard(0x12, 0x56, protocol_id=2), f"Unexpected output {output!r}"


@cocotb.test()
async def test_apple_protocol_prefix(dut):
    """Protocol label should switch to APPLE for protocol_id=3."""
    await setup(dut)
    await trigger_valid(dut, address=0xEE, command=0x50, protocol_id=3)
    result = await collect_bytes(dut, FRAME_LEN_STD)
    output = bytes_to_str(result)
    assert output == expected_standard(0xEE, 0x50, protocol_id=3), f"Unexpected output {output!r}"


@cocotb.test()
async def test_samsung48_output(dut):
    """Samsung48 should output 4-digit command from frame_data[31:16]."""
    await setup(dut)
    # frame_data layout (48-bit, LSB-first shift register after 48 bits):
    # bits[15:0]  = address bytes
    # bits[31:16] = command bytes (16-bit command for SAM48)
    # bits[47:32] = upper 16 bits (unused here)
    # Example: addr=0x07, cmd16=0xE0BF
    frame_data_val = (0x07 << 0) | (0x07 << 8) | (0xBF << 16) | (0xE0 << 24)
    await trigger_valid(
        dut,
        address=0x07,
        command=0xBF,  # lower 8 bits of cmd16
        protocol_id=9,  # PROTO_SAMSUNG48
        frame_data=frame_data_val,
        frame_bits=48
    )
    result = await collect_bytes(dut, FRAME_LEN_S48)
    output = bytes_to_str(result)
    assert output == "P:SAM48    A:07 C:E0BF\n", f"Unexpected SAM48 output {output!r}"

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
