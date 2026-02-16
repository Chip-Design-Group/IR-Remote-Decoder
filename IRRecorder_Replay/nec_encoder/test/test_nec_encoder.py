"""
Datei: test_nec_encoder.py
Zweck:
  Unit-Test fuer nec_encoder (Leader, Datenbits, Stop und Repeat-Verhalten).
Rein:
  start, payload, tick_us.
Raus:
  Assertions auf mark_active, frame_done, busy, error.
"""

import cocotb


@cocotb.test()
async def test_encoder_emits_full_nec_frame(dut):
    """TODO: Vollstaendigen NEC-Frame mit gueltigem Payload pruefen."""
    raise NotImplementedError("TODO: Test implementieren")


@cocotb.test()
async def test_encoder_repeat_flag_behavior(dut):
    """TODO: Verhalten fuer Repeat-Flag im Payload pruefen."""
    raise NotImplementedError("TODO: Test implementieren")
