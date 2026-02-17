"""
Datei: test_ir_tx.py
Zweck:
  Unit-Test fuer ir_tx (38-kHz-Traeger + Modulation, NPN-Drive-Ausgang).
Rein:
  mark_active, clk, rst_n.
Raus:
  Assertions auf ir_npn_drive/ir_led_out und ready.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb_tools.runner import get_runner


@cocotb.test()
async def test_tx_generates_carrier_when_mark_active(dut):
    """Prueft, dass bei mark_active ein toggelnder Traeger ausgegeben wird."""
    cocotb.start_soon(Clock(dut.clk, 2, unit="step").start())

    dut.rst_n.value = 0
    dut.mark_active.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut.mark_active.value = 1
    prev = int(dut.ir_npn_drive.value)
    toggles = 0

    for _ in range(400):
        await RisingEdge(dut.clk)
        cur = int(dut.ir_npn_drive.value)
        if cur != prev:
            toggles += 1
        prev = cur

    assert toggles >= 2, f"Zu wenige Flanken erkannt: {toggles}"
    assert int(dut.ir_led_out.value) == int(dut.ir_npn_drive.value), "Alias muss identisch sein"
    assert int(dut.ready.value) == 1, "ready sollte fuer einfache TX-Stufe 1 sein"


@cocotb.test()
async def test_tx_idle_level_when_mark_inactive(dut):
    """Prueft Idle-Pegel bei deaktiviertem mark_active."""
    cocotb.start_soon(Clock(dut.clk, 2, unit="step").start())

    dut.rst_n.value = 0
    dut.mark_active.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    for _ in range(40):
        await RisingEdge(dut.clk)
        assert int(dut.ir_npn_drive.value) == 0, "Idle sollte Low sein (NPN aus)"
        assert int(dut.ir_led_out.value) == 0, "Alias muss im Idle ebenfalls Low sein"

    assert int(dut.ready.value) == 1, "ready sollte im Idle 1 sein"


def test_ir_tx_runner():
    """Simulate ir_tx with cocotb Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [
        proj_path.parent / "Types_PKG" / "src" / "ir_types_pkg.sv",
        proj_path / "src" / "ir_tx.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ir_tx",
        always=True,
    )

    runner.test(
        hdl_toplevel="ir_tx",
        test_module="test_ir_tx",
    )


if __name__ == "__main__":
    test_ir_tx_runner()
