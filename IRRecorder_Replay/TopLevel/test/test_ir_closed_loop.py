"""
Datei: test_ir_closed_loop.py
Zweck:
  Integrations-Test: Decode -> Record -> Replay -> Encode/TX.
Rein:
  Dekodierte Eingangsdaten und Steueranforderungen.
Raus:
  End-to-End Nachweis, dass replayte Daten dem Original entsprechen.
"""

import cocotb


@cocotb.test()
async def test_record_then_replay_same_payload(dut):
    """TODO: Vollstaendigen Datenpfad in einem Szenario pruefen."""
    raise NotImplementedError("TODO: Test implementieren")
