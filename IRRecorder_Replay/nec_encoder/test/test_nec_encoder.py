"""
Datei: test_nec_encoder.py
Zweck:
  Unit-Test fuer nec_encoder (Leader, Datenbits, Stop und Repeat-Verhalten).
Rein:
  start, payload, tick_us.
Raus:
  Assertions auf mark_active, frame_done, busy, error.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb_tools.runner import get_runner

IR_FLAG_WIDTH = 8
IR_FRAME_BITS_WIDTH = 6
IR_PROTOCOL_ID_WIDTH = 5
PROTOCOL_SHIFT = IR_FLAG_WIDTH
FRAME_BITS_SHIFT = PROTOCOL_SHIFT + IR_PROTOCOL_ID_WIDTH
FRAME_DATA_SHIFT = FRAME_BITS_SHIFT + IR_FRAME_BITS_WIDTH


def _build_frame_data(address, command):
    addr = address & 0xFF
    cmd = command & 0xFF
    return (((~cmd & 0xFF) << 24) |
            (cmd << 16) |
            ((~addr & 0xFF) << 8) |
            addr)


def pack_payload(address, command, flags, protocol_id=0x01, frame_bits=32):
    frame_data = _build_frame_data(address, command) & ((1 << 32) - 1)
    word = ((frame_data << FRAME_DATA_SHIFT) |
            ((frame_bits & ((1 << IR_FRAME_BITS_WIDTH) - 1)) << FRAME_BITS_SHIFT) |
            ((protocol_id & ((1 << IR_PROTOCOL_ID_WIDTH) - 1)) << PROTOCOL_SHIFT) |
            (flags & 0xFF))
    return word


@cocotb.test()
async def test_encoder_emits_full_nec_frame(dut):
    """Prueft Leader + 32 Datenbits + Stop und frame_done-Puls."""
    cocotb.start_soon(Clock(dut.clk, 2, unit="step").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.payload.value = 0
    dut.tick_us.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload = pack_payload(0x00FF, 0x34, 0x01)
    dut.payload.value = payload
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.busy.value) == 1, "busy muss nach start aktiv sein"
    assert int(dut.error.value) == 0, "error darf im Happy-Path nicht aktiv sein"

    frame_done_seen = False
    mark_seen = False

    for _ in range(120_000):
        dut.tick_us.value = 1
        await RisingEdge(dut.clk)
        if int(dut.mark_active.value) == 1:
            mark_seen = True
        if int(dut.frame_done.value) == 1:
            frame_done_seen = True
            break

    dut.tick_us.value = 0
    assert mark_seen, "mark_active sollte waehrend Frame aktiv werden"
    assert frame_done_seen, "frame_done wurde nicht innerhalb des Zeitfensters aktiv"

    await RisingEdge(dut.clk)
    assert int(dut.frame_done.value) == 0, "frame_done muss ein Single-Cycle-Puls sein"
    assert int(dut.busy.value) == 0, "busy muss nach frame_done wieder 0 sein"
    assert int(dut.frame_active.value) == 0, "frame_active muss nach Ende 0 sein"


@cocotb.test()
async def test_encoder_repeat_flag_behavior(dut):
    """Prueft kuerzeren Repeat-Frame bei gesetztem Repeat-Flag."""
    cocotb.start_soon(Clock(dut.clk, 2, unit="step").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.payload.value = 0
    dut.tick_us.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    payload_repeat = pack_payload(0x1234, 0x56, 0x03)
    dut.payload.value = payload_repeat
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Repeat-Frame sollte deutlich schneller fertig sein als voller 32-Bit-Frame.
    frame_done_cycle = None
    for cycle in range(1, 20_000):
        dut.tick_us.value = 1
        await RisingEdge(dut.clk)
        if int(dut.frame_done.value) == 1:
            frame_done_cycle = cycle
            break

    dut.tick_us.value = 0
    assert frame_done_cycle is not None, "Repeat-Frame wurde nicht beendet"
    assert frame_done_cycle < 15_000, (
        f"Repeat-Frame zu lang: {frame_done_cycle} us-Ticks (erwartet < 15000)"
    )
    assert int(dut.error.value) == 0, "error darf beim Repeat nicht aktiv sein"
    assert int(dut.busy.value) == 0, "busy muss nach Repeat-Frame wieder 0 sein"


def test_nec_encoder_runner():
    """Simulate nec_encoder with cocotb Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [
        proj_path.parent / "Types_PKG" / "src" / "ir_types_pkg.sv",
        proj_path / "src" / "nec_encoder.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="nec_encoder",
        always=True,
    )

    runner.test(
        hdl_toplevel="nec_encoder",
        test_module="test_nec_encoder",
    )


if __name__ == "__main__":
    test_nec_encoder_runner()
