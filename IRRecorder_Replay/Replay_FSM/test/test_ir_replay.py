"""
Datei: test_ir_replay.py
Zweck:
  Unit-Test fuer ir_replay_fsm + Lesepfad + Encoder-Start.
Rein:
  replay_req, target_slot, simulierte Speicherantwort.
Raus:
  Assertions auf mem_rd_en/addr, enc_start, enc_address/command, done/error.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge
from cocotb_tools.runner import get_runner


CLK_PERIOD_NS = 10


IR_FLAG_WIDTH = 8
IR_FRAME_BITS_WIDTH = 6
IR_PROTOCOL_ID_WIDTH = 5
FRAME_BITS_SHIFT = IR_FLAG_WIDTH
PROTOCOL_SHIFT = FRAME_BITS_SHIFT + IR_FRAME_BITS_WIDTH
FRAME_DATA_SHIFT = PROTOCOL_SHIFT + IR_PROTOCOL_ID_WIDTH

def _build_frame_data(address, command):
    addr = address & 0xFF
    cmd = command & 0xFF
    return (((~cmd & 0xFF) << 24) |
            (cmd << 16) |
            ((~addr & 0xFF) << 8) |
            addr)


def pack_ir_word(address, command, flags, protocol_id=0x01, frame_bits=32):
    """Packt das neue IR-Wortformat inklusive frame_data/protocol_id/flags."""
    frame_data = _build_frame_data(address, command) & ((1 << 32) - 1)
    word = ((frame_data << FRAME_DATA_SHIFT) |
            ((frame_bits & ((1 << IR_FRAME_BITS_WIDTH) - 1)) << PROTOCOL_SHIFT) |
            ((protocol_id & ((1 << IR_PROTOCOL_ID_WIDTH) - 1)) << FRAME_BITS_SHIFT) |
            (flags & 0xFF))
    return word


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.replay_req.value = 0
    dut.target_slot.value = 0
    dut.mem_rd_data.value = 0
    dut.mem_rd_valid.value = 0
    dut.enc_ready.value = 0
    dut.tx_ready.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def start_replay(dut, slot):
    dut.target_slot.value = slot
    dut.replay_req.value = 1
    await RisingEdge(dut.clk)
    dut.replay_req.value = 0


async def respond_memory_read(dut, word):
    dut.mem_rd_data.value = word
    dut.mem_rd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.mem_rd_valid.value = 0


async def wait_for_signal_pulse(dut, signal_name, max_cycles=16):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(getattr(dut, signal_name).value) == 1:
            return
    raise AssertionError(f"{signal_name} wurde nicht innerhalb von {max_cycles} Takten aktiv")


@cocotb.test()
async def test_replay_single_slot(dut):
    """Slot lesen, Wort entpacken und Encoder korrekt starten."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    slot = 3
    address = 0x12AB
    command = 0x7E
    flags = 0x01  # valid bit
    word = pack_ir_word(address, command, flags)

    dut.enc_ready.value = 1
    dut.tx_ready.value = 1

    await start_replay(dut, slot)
    await ReadOnly()

    assert int(dut.mem_rd_en.value) == 1, "mem_rd_en muss direkt nach replay_req aktiv sein"
    assert int(dut.mem_rd_addr.value) == slot, "mem_rd_addr muss dem angeforderten Slot entsprechen"
    assert int(dut.busy.value) == 1, "FSM sollte waehrend Replay busy sein"

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.mem_rd_en.value) == 0, "mem_rd_en darf nur ein Lese-Puls sein"

    await RisingEdge(dut.clk)
    await respond_memory_read(dut, word)

    await wait_for_signal_pulse(dut, "enc_start")
    assert int(dut.enc_payload.value) == word, "enc_payload muss zum gelesenen Slot-Wort passen"
    assert int(dut.error.value) == 0, "Fehler darf im Happy-Path nicht auftreten"

    await wait_for_signal_pulse(dut, "done")
    assert int(dut.error.value) == 0, "done-Pfad darf keinen Fehler signalisieren"

    await RisingEdge(dut.clk)
    assert int(dut.busy.value) == 0, "Nach done muss FSM wieder idle sein"


@cocotb.test()
async def test_replay_waits_for_encoder_ready(dut):
    """Sicherstellen, dass bei enc_ready=0 kein verfruehter Start erfolgt."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    slot = 1
    word = pack_ir_word(address=0x00F0, command=0x34, flags=0x01)

    dut.enc_ready.value = 0
    dut.tx_ready.value = 1

    await start_replay(dut, slot)
    await RisingEdge(dut.clk)  # ST_READ_WAIT
    await respond_memory_read(dut, word)
    await RisingEdge(dut.clk)  # ST_WAIT_ENCODER

    for _ in range(6):
        assert int(dut.enc_start.value) == 0, "enc_start darf vor enc_ready nicht aktiv werden"
        assert int(dut.done.value) == 0, "done darf vor Start nicht aktiv werden"
        assert int(dut.error.value) == 0, "Kein Fehler erwartet, nur Warten auf Encoder"
        assert int(dut.busy.value) == 1, "FSM muss waehrend WAIT_ENCODER busy bleiben"
        await RisingEdge(dut.clk)

    dut.enc_ready.value = 1
    await wait_for_signal_pulse(dut, "enc_start")
    assert int(dut.enc_payload.value) == word, "Payload muss auch nach Wartephase korrekt bleiben"

    await wait_for_signal_pulse(dut, "done")
    assert int(dut.error.value) == 0, "Nach erfolgreichem Start darf error nicht aktiv sein"


def test_replay_fsm_runner():
    """Simulate the ir_replay_fsm using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [
        proj_path.parent / "Types_PKG" / "src" / "ir_types_pkg.sv",
        proj_path / "src" / "ir_replay_fsm.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ir_replay_fsm",
        always=True,
    )

    runner.test(
        hdl_toplevel="ir_replay_fsm",
        test_module="test_ir_replay",
    )


if __name__ == "__main__":
    test_replay_fsm_runner()
