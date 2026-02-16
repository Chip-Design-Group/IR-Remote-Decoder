import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, ReadWrite, RisingEdge, Timer
from cocotb_tools.runner import get_runner


@cocotb.test()
async def test_edge_detection_basic(dut):
    """Test 2-stage synchronizer and edge pulses."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    async def tick_sample():
        await RisingEdge(dut.clk)
        await ReadOnly()

    async def tick_drive():
        await RisingEdge(dut.clk)
        await ReadWrite()

    dut.rst_n.value = 0
    dut.ir_in_async.value = 0
    await tick_sample()
    await tick_drive()
    dut.rst_n.value = 1

    await tick_sample()
    assert int(dut.ir_in_sync.value) == 0
    assert int(dut.edge_rise.value) == 0
    assert int(dut.edge_fall.value) == 0

    # Drive a rising edge mid-cycle
    await tick_drive()
    await Timer(3, "ns")
    dut.ir_in_async.value = 1

    saw_rise = False
    for _ in range(4):
        await tick_sample()
        if int(dut.edge_rise.value) == 1:
            assert int(dut.ir_in_sync.value) == 1
            assert int(dut.edge_fall.value) == 0
            saw_rise = True
            break
    assert saw_rise, "edge_rise never asserted after rising edge"

    await tick_sample()
    assert int(dut.edge_rise.value) == 0
    assert int(dut.edge_fall.value) == 0

    # Inject a short glitch between clock edges
    await tick_drive()
    await Timer(2, "ns")
    dut.ir_in_async.value = 1
    await Timer(2, "ns")
    dut.ir_in_async.value = 0

    rise_count = 0
    fall_count = 0
    for _ in range(4):
        await tick_sample()
        rise_count += int(dut.edge_rise.value)
        fall_count += int(dut.edge_fall.value)
        assert not (int(dut.edge_rise.value) and int(dut.edge_fall.value))
    assert rise_count <= 1
    assert fall_count <= 1

    # Restore a stable high level before testing falling edge
    await tick_drive()
    await Timer(3, "ns")
    dut.ir_in_async.value = 1

    for _ in range(4):
        await tick_sample()
        if int(dut.ir_in_sync.value) == 1:
            break

    # Drive a falling edge mid-cycle
    await tick_drive()
    await Timer(3, "ns")
    dut.ir_in_async.value = 0

    saw_fall = False
    for _ in range(4):
        await tick_sample()
        if int(dut.edge_fall.value) == 1:
            assert int(dut.ir_in_sync.value) == 0
            assert int(dut.edge_rise.value) == 0
            saw_fall = True
            break
    assert saw_fall, "edge_fall never asserted after falling edge"

    await tick_sample()
    assert int(dut.edge_rise.value) == 0
    assert int(dut.edge_fall.value) == 0

def test_edge_detector_runner():
    """Simulate the edge_detector using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "edge_detector.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="edge_detector",
        always=True,
    )

    runner.test(
        hdl_toplevel="edge_detector",
        test_module="test_edge_detector",
    )

if __name__ == "__main__":
    test_edge_detector_runner()