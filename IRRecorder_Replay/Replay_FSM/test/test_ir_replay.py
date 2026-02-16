"""
Datei: test_ir_replay.py
Zweck:
  Unit-Test fuer ir_replay_fsm + Lesepfad + Encoder-Start.
Rein:
  replay_req, target_slot, simulierte Speicherantwort.
Raus:
  Assertions auf mem_rd_en/addr, enc_start, enc_address/command, done/error.
"""

import cocotb


@cocotb.test()
async def test_replay_single_slot(dut):
    """TODO: Slot lesen, Wort entpacken und Encoder korrekt starten."""
    raise NotImplementedError("TODO: Test implementieren")


@cocotb.test()
async def test_replay_waits_for_encoder_ready(dut):
    """TODO: Sicherstellen, dass bei enc_ready=0 kein verfruehter Start erfolgt."""
    raise NotImplementedError("TODO: Test implementieren")
