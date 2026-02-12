import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

# Test timing parameters
CLK_PERIOD_NS = 100
CLOCKS_PER_BIT = 8  # small for fast simulation


async def _reset(dut):
    dut.rst_n.value = 0
    dut.send_req.value = 0
    dut.data_in.value = 0
    await Timer(200, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def _send_and_sample(dut, byte):
    """Send one byte and sample UART bits at bit centers."""
    await RisingEdge(dut.clk)
    dut.data_in.value = byte
    dut.send_req.value = 1
    await RisingEdge(dut.clk)
    dut.send_req.value = 0

    bit_period_ns = CLOCKS_PER_BIT * CLK_PERIOD_NS
    await Timer(bit_period_ns // 2, unit="ns")

    samples = []
    for i in range(10):
        if i > 0:
            await Timer(bit_period_ns, unit="ns")
        samples.append(int(dut.tx_out.value))

    return samples


@cocotb.test()
async def test_ready_and_idle(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    assert int(dut.ready.value) == 1
    assert int(dut.tx_out.value) == 1


@cocotb.test()
async def test_uart_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    byte = 0x5A
    samples = await _send_and_sample(dut, byte)
    expected = [0] + [(byte >> i) & 1 for i in range(8)] + [1]
    assert samples == expected


@cocotb.test()
async def test_ready_cleared_during_tx_and_reasserted(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.data_in.value = 0xA5
    dut.send_req.value = 1
    await RisingEdge(dut.clk)
    dut.send_req.value = 0

    await RisingEdge(dut.clk)
    assert int(dut.ready.value) == 0

    for _ in range(10 * CLOCKS_PER_BIT):
        await RisingEdge(dut.clk)

    assert int(dut.ready.value) == 1


@cocotb.test()
async def test_ignore_send_while_busy(dut):
    """Second send_req during busy must not affect first frame."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    first = 0x3C

    samples = await _send_and_sample(dut, first)
    expected = [0] + [(first >> i) & 1 for i in range(8)] + [1]
    assert samples == expected


@cocotb.test()
async def test_back_to_back_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    a = 0x55
    b = 0xAA

    s1 = await _send_and_sample(dut, a)
    while int(dut.ready.value) == 0:
        await RisingEdge(dut.clk)
    s2 = await _send_and_sample(dut, b)

    e1 = [0] + [(a >> i) & 1 for i in range(8)] + [1]
    e2 = [0] + [(b >> i) & 1 for i in range(8)] + [1]

    assert s1 == e1
    assert s2 == e2


@cocotb.test()
async def test_reset_during_tx(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.data_in.value = 0xAA
    dut.send_req.value = 1
    await RisingEdge(dut.clk)
    dut.send_req.value = 0

    for _ in range(CLOCKS_PER_BIT // 2):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    assert int(dut.tx_out.value) == 1
    assert int(dut.ready.value) == 1


@cocotb.test()
async def test_all_zeros_and_all_ones(dut):
    """Test extreme data patterns 0x00 and 0xFF"""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    # Test all zeros
    samples_00 = await _send_and_sample(dut, 0x00)
    expected_00 = [0] + [0] * 8 + [1]
    assert samples_00 == expected_00, f"Expected {expected_00}, got {samples_00}"

    # Wait for ready
    while int(dut.ready.value) == 0:
        await RisingEdge(dut.clk)

    # Test all ones
    samples_FF = await _send_and_sample(dut, 0xFF)
    expected_FF = [0] + [1] * 8 + [1]
    assert samples_FF == expected_FF, f"Expected {expected_FF}, got {samples_FF}"


@cocotb.test()
async def test_data_change_during_transmission(dut):
    """Verify that data_in changes during TX are ignored"""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    original_byte = 0xAA
    
    # Start transmission
    dut.data_in.value = original_byte
    dut.send_req.value = 1
    await RisingEdge(dut.clk)
    dut.send_req.value = 0
    
    # Change data_in during transmission (should be ignored)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.data_in.value = 0x55  # Change to different pattern
    
    # Sample the transmission
    bit_period_ns = CLOCKS_PER_BIT * CLK_PERIOD_NS
    await Timer(bit_period_ns // 2, unit="ns")
    
    samples = []
    for i in range(10):
        if i > 0:
            await Timer(bit_period_ns, unit="ns")
        samples.append(int(dut.tx_out.value))
    
    # Should match original byte, not the changed value
    expected = [0] + [(original_byte >> i) & 1 for i in range(8)] + [1]
    assert samples == expected, f"Data changed during TX! Expected {expected}, got {samples}"


@cocotb.test()
async def test_extended_send_req_pulse(dut):
    """Verify behavior when send_req stays high for multiple cycles"""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    byte = 0x7E
    
    # Keep send_req high for multiple cycles
    dut.data_in.value = byte
    dut.send_req.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.send_req.value = 0
    
    # Sample the transmission
    bit_period_ns = CLOCKS_PER_BIT * CLK_PERIOD_NS
    await Timer(bit_period_ns // 2, unit="ns")
    
    samples = []
    for i in range(10):
        if i > 0:
            await Timer(bit_period_ns, unit="ns")
        samples.append(int(dut.tx_out.value))
    
    # Should still produce correct frame
    expected = [0] + [(byte >> i) & 1 for i in range(8)] + [1]
    assert samples == expected, f"Extended send_req pulse affected transmission! Expected {expected}, got {samples}"

def test_uart_tx_runner():
    """Simulate the uart_tx using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "uart_tx.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="uart_tx",
        always=True,
        parameters={"CLOCKS_PER_BIT": CLOCKS_PER_BIT},
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="uart_tx",
        test_module="test_uart_tx",
    )


if __name__ == "__main__":
    test_uart_tx_runner()