"""
Datei: test_helpers.py
Zweck:
  Gemeinsame Helper fuer Cocotb-Tests des IRRecorder_Replay-Blocks.
Rein:
  DUT-Handle und Testparameter.
Raus:
  Reproduzierbare Stimuli/Pruef-Helfer (async functions).
"""

from cocotb.triggers import ClockCycles


async def reset_dut(dut, cycles=5):
    """TODO: Einheitliches Reset-Verhalten fuer alle Tests."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def send_decoded_word(dut, address, command, flags=0):
    """TODO: Decoder-Ausgang fuer Record-Test treiben."""
    _ = (address, command, flags)


async def trigger_replay(dut, slot):
    """TODO: Replay-Anforderung fuer Zielslot ausloesen."""
    _ = slot
