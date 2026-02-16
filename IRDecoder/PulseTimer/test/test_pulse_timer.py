import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, ReadWrite, RisingEdge, Timer
from cocotb_tools.runner import get_runner

@cocotb.test()
async def test_pulse_measurement(dut):
    """Test pulse width measurement correctness."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    async def tick_sample():
        await RisingEdge(dut.clk)
        await ReadOnly()

    async def tick_drive():
        await RisingEdge(dut.clk)
        await ReadWrite()

    dut.rst_n.value = 0
    dut.ir_in_sync.value = 0
    dut.edge_rise.value = 0
    dut.edge_fall.value = 0
    await tick_sample()
    await tick_drive()
    dut.rst_n.value = 1

    # Start a HIGH pulse: rising edge (aligned to clock)
    await tick_drive()
    dut.ir_in_sync.value = 1
    dut.edge_rise.value = 1

    await tick_sample()
    await tick_drive()
    dut.edge_rise.value = 0

    # Wait N full cycles while pulse is high
    high_cycles = 6
    for _ in range(high_cycles):
        await tick_sample()

    # End HIGH pulse: falling edge (aligned to clock)
    await tick_drive()
    dut.ir_in_sync.value = 0
    dut.edge_fall.value = 1

    await tick_sample()
    assert int(dut.pulse_done.value) == 1
    assert int(dut.timeout.value) == 0
    assert int(dut.pulse_level.value) == 1
    assert int(dut.pulse_width.value) == high_cycles

    await tick_drive()
    dut.edge_fall.value = 0

    await tick_sample()
    assert int(dut.pulse_done.value) == 0

@cocotb.test()
async def test_pulse_timeout(dut):
    """Test timeout logic."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    async def tick_sample():
        await RisingEdge(dut.clk)
        await ReadOnly()

    async def tick_drive():
        await RisingEdge(dut.clk)
        await ReadWrite()

    dut.rst_n.value = 0
    dut.ir_in_sync.value = 0
    dut.edge_rise.value = 0
    dut.edge_fall.value = 0
    await tick_sample()
    await tick_drive()
    dut.rst_n.value = 1

    # Start pulse and let it run past timeout
    await tick_drive()
    await Timer(2, "ns")
    dut.ir_in_sync.value = 1
    dut.edge_rise.value = 1

    await tick_sample()
    await tick_drive()
    dut.edge_rise.value = 0

    for _ in range(100_005):
        await tick_sample()
        if int(dut.pulse_done.value) == 1:
            break

    assert int(dut.pulse_done.value) == 1
    assert int(dut.timeout.value) == 1


def test_pulse_timer_runner():
    """Simulate the pulse_timer using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "pulse_timer.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="pulse_timer",
        always=True,
    )

    runner.test(
        hdl_toplevel="pulse_timer",
        test_module="test_pulse_timer",
    )


if __name__ == "__main__":
    test_pulse_timer_runner()
