"""
Datei: test_helpers.py
Zweck:
  Gemeinsame Helper fuer Cocotb-Tests des IRRecorder_Replay-Blocks.
Rein:
  DUT-Handle und Testparameter.
Raus:
  Reproduzierbare Stimuli/Pruef-Helfer (async functions).
"""

from cocotb.triggers import ClockCycles, RisingEdge


async def reset_dut(dut, cycles=5):
    """Einheitliches Reset-Verhalten fuer alle TopLevel-Tests."""
    dut.rst_n.value = 0
    dut.ir_in.value = 1
    dut.record_req.value = 0
    dut.replay_req.value = 0
    dut.slot_sel.value = 0
    dut.use_external_decoder_data.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def send_decoded_word(dut, address, command, flags=0):
    """Treibt fuer genau einen Takt ein dec_valid-Payload."""
    word = ((address & 0xFFFF) << 16) | ((command & 0xFF) << 8) | (flags & 0xFF)
    dut.dec_payload.value = word
    dut.dec_valid.value = 1
    await RisingEdge(dut.clk)
    dut.dec_valid.value = 0


async def trigger_replay(dut, slot):
    """Erzeugt einen Replay-Request-Puls fuer den gewaehlten Slot."""
    dut.slot_sel.value = slot
    dut.replay_req.value = 1
    await RisingEdge(dut.clk)
    dut.replay_req.value = 0
