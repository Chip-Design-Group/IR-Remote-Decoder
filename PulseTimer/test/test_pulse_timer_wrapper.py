import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer
from cocotb_tools.runner import get_runner


async def wait_pulse(dut):
    await RisingEdge(dut.pulse_done)
    await ReadOnly()
    return int(dut.pulse_width.value), int(dut.pulse_level.value), int(dut.timeout.value)


@cocotb.test()
async def test_measure_short_pulse(dut):
    """Test short pulse width (560 us) through edge_detector + pulse_timer."""
    cocotb.start_soon(Clock(dut.clk, 100, "ns").start())

    dut.rst_n.value = 0
    dut.ir_in_async.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # Let the synchronizer settle high
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Low pulse for 560 us (IR active low)
    dut.ir_in_async.value = 0
    await Timer(560, "us")
    dut.ir_in_async.value = 1

    width, level, timeout = await wait_pulse(dut)
    assert timeout == 0
    assert level == 0
    assert 4480 <= width <= 6720


@cocotb.test()
async def test_measure_long_pulse(dut):
    """Test long pulse width (1690 us) through edge_detector + pulse_timer."""
    cocotb.start_soon(Clock(dut.clk, 100, "ns").start())

    dut.rst_n.value = 0
    dut.ir_in_async.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # Let the synchronizer settle high
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.ir_in_async.value = 0
    await Timer(1690, "us")
    dut.ir_in_async.value = 1

    width, level, timeout = await wait_pulse(dut)
    assert timeout == 0
    assert level == 0
    assert 13520 <= width <= 20280


@cocotb.test()
async def test_timeout_detection(dut):
    """Test timeout when pulse exceeds 10 ms."""
    cocotb.start_soon(Clock(dut.clk, 100, "ns").start())

    dut.rst_n.value = 0
    dut.ir_in_async.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # Let the synchronizer settle high
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.ir_in_async.value = 0
    await Timer(11, "ms")

    width, level, timeout = await wait_pulse(dut)
    assert timeout == 1
    assert level == 0
    assert width >= 100_000


def test_pulse_timer_wrapper_runner():
    """Simulate edge_detector + pulse_timer via wrapper."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [
        proj_path / "src" / "edge_pulse_wrapper.sv",
        proj_path / "src" / "pulse_timer.sv",
        proj_path / ".." / "EdgeDetector" / "src" / "edge_detector.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="edge_pulse_wrapper",
        always=True,
    )

    runner.test(
        hdl_toplevel="edge_pulse_wrapper",
        test_module="test_pulse_timer_wrapper",
    )


if __name__ == "__main__":
    test_pulse_timer_wrapper_runner()
