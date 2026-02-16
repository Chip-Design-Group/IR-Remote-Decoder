"""
Datei: test_ir_storage_bram.py
Zweck:
  Unit-Test fuer ir_storage_bram (Read/Write-Verhalten je Slot).
Rein:
  mem_wr_en, mem_wr_addr, mem_wr_data, mem_rd_addr.
Raus:
  Assertions auf mem_rd_data, mem_rd_valid und Datenpersistenz.
"""

import cocotb


@cocotb.test()
async def test_bram_write_then_read_same_slot(dut):
    """TODO: In einen Slot schreiben und denselben Slot wieder auslesen."""
    raise NotImplementedError("TODO: Test implementieren")


@cocotb.test()
async def test_bram_slots_are_independent(dut):
    """TODO: Sicherstellen, dass verschiedene Slots getrennte Inhalte halten."""
    raise NotImplementedError("TODO: Test implementieren")
