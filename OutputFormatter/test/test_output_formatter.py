"""
CocoTB Unit Tests for output_formatter module.

Tests the ASCII hex formatting FSM:
- Correct byte sequence "A:xx C:yy\n"
- UART handshake (uart_ready / uart_tx_req)
- Busy signal behavior
- Multiple frames
- Backpressure
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
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.address.value = 0
    dut.command.value = 0
    dut.valid_in.value = 0
    dut.uart_ready.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def trigger_valid(dut, address, command):
    dut.address.value = address
    dut.command.value = command
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0


async def collect_bytes(dut, num_bytes):
    result = []
    for _ in range(num_bytes):
        timeout = 0
        while int(dut.uart_tx_req.value) == 0:
            await RisingEdge(dut.clk)
            timeout += 1
            if timeout > 1000:
                raise TimeoutError("Timeout waiting for uart_tx_req")

        result.append(int(dut.uart_data.value))
        await RisingEdge(dut.clk)

    return result


def bytes_to_str(byte_list):
    return "".join(chr(b) for b in byte_list)


def nibble_to_hex_char(n):
    return chr(0x30 + n) if n < 10 else chr(0x41 + n - 10)


def expected_string(addr, cmd):
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
    await setup(dut)
    assert int(dut.uart_tx_req.value) == 0


@cocotb.test()
async def test_basic_output(dut):
    await setup(dut)
    await trigger_valid(dut, 0x00, 0x45)
    result = await collect_bytes(dut, 10)
    assert bytes_to_str(result) == "A:00 C:45\n"


@cocotb.test()
async def test_output_ff_ff(dut):
    await setup(dut)
    await trigger_valid(dut, 0xFF, 0xFF)
    result = await collect_bytes(dut, 10)
    assert bytes_to_str(result) == "A:FF C:FF\n"


@cocotb.test()
async def test_output_ab_cd(dut):
    await setup(dut)
    await trigger_valid(dut, 0xAB, 0xCD)
    result = await collect_bytes(dut, 10)
    assert bytes_to_str(result) == "A:AB C:CD\n"


@cocotb.test()
async def test_waits_for_uart_ready(dut):
    await setup(dut)
    dut.uart_ready.value = 0

    await trigger_valid(dut, 0x00, 0x00)
    await ClockCycles(dut.clk, 10)

    assert int(dut.uart_tx_req.value) == 0

    dut.uart_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.uart_tx_req.value) == 1


@cocotb.test()
async def test_two_consecutive_outputs(dut):
    await setup(dut)

    await trigger_valid(dut, 0x00, 0x45)
    r1 = await collect_bytes(dut, 10)
    await ClockCycles(dut.clk, 5)

    await trigger_valid(dut, 0xAB, 0xCD)
    r2 = await collect_bytes(dut, 10)

    assert bytes_to_str(r1) == "A:00 C:45\n"
    assert bytes_to_str(r2) == "A:AB C:CD\n"


@cocotb.test()
async def test_uart_tx_req_pulse_width(dut):
    await setup(dut)
    await trigger_valid(dut, 0x00, 0x00)

    pulses = 0
    prev = 0

    while pulses < 10:
        await RisingEdge(dut.clk)
        cur = int(dut.uart_tx_req.value)

        if cur == 1 and prev == 1:
            raise AssertionError("uart_tx_req wider than 1 cycle")

        if cur == 1:
            pulses += 1

        prev = cur


@cocotb.test()
async def test_exact_bytes(dut):
    await setup(dut)
    await trigger_valid(dut, 0x3F, 0xA0)
    result = await collect_bytes(dut, 10)

    expected = [0x41,0x3A,0x33,0x46,0x20,0x43,0x3A,0x41,0x30,0x0A]
    assert result == expected

@cocotb.test(timeout_time=300, timeout_unit="sec")
async def test_all_256x256_combinations(dut):
    """Exhaustive test: all 65536 address/command combinations."""
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
    assert fail_count == 0, \
        f"{fail_count} failures! First: addr=0x{first_fail[0]:02X} cmd=0x{first_fail[1]:02X} " \
        f"got {first_fail[2]!r}, expected {first_fail[3]!r}"

# ============================================================
# Runner
# ============================================================
def test_output_formatter_runner():
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
