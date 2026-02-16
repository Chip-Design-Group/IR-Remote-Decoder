"""
Datei: test_ir_tx.py
Zweck:
  Unit-Test fuer ir_tx (38-kHz-Traeger + Modulation, NPN-Drive-Ausgang).
Rein:
  mark_active, clk, rst_n.
Raus:
  Assertions auf ir_npn_drive/ir_led_out und ready.
"""

import cocotb


@cocotb.test()
async def test_tx_generates_carrier_when_mark_active(dut):
    """TODO: Bei mark_active=1 getaktetes Ausgangssignal pruefen."""
    raise NotImplementedError("TODO: Test implementieren")


@cocotb.test()
async def test_tx_idle_level_when_mark_inactive(dut):
    """TODO: Bei mark_active=0 Idle-Pegel und ready-Verhalten pruefen."""
    raise NotImplementedError("TODO: Test implementieren")
