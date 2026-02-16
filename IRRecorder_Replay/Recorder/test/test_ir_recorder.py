"""
Datei: test_ir_recorder.py
Zweck:
  Unit-Test fuer ir_recorder + Speicher-Schreibpfad.
Rein:
  Stimuli fuer record_req, dec_valid, dec_address, dec_command.
Raus:
  Assertions auf mem_wr_en/mem_wr_addr/mem_wr_data, done/error.
"""

import cocotb


@cocotb.test()
async def test_record_single_code(dut):
    """TODO: Einen gueltigen Code aufzeichnen und Write-Word pruefen."""
    raise NotImplementedError("TODO: Test implementieren")


@cocotb.test()
async def test_record_without_valid_frame(dut):
    """TODO: Fehlerpfad pruefen, wenn kein gueltiger Decoder-Frame anliegt."""
    raise NotImplementedError("TODO: Test implementieren")
