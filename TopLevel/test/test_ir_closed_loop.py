"""
Datei: test_ir_closed_loop.py
Zweck:
  Integrations-Test: Decode -> Record -> Replay -> Encode/TX.
Rein:
  Dekodierte Eingangsdaten und Steueranforderungen.
Raus:
  End-to-End Nachweis, dass replayte Daten dem Original entsprechen.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb_tools.runner import get_runner

from test_helpers import reset_dut, send_decoded_word, trigger_replay


async def _wait_for_pulse(dut, signal_name, max_cycles=256):
    sig = getattr(dut, signal_name)
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(sig.value) == 1:
            return True
    return False


@cocotb.test()
async def test_record_then_replay_same_payload(dut):
    """Record wird gehalten bis dec_valid und Replay sendet danach ein NEC-Frame."""
    cocotb.start_soon(Clock(dut.clk, 2, unit="step").start())
    await reset_dut(dut)

    # Aufnahme starten (ein kurzer Tasterpuls)
    dut.slot_sel.value = 0
    dut.record_req.value = 1
    await RisingEdge(dut.clk)
    dut.record_req.value = 0

    # Recorder muss auf gueltigen Decoder-Output warten.
    await ClockCycles(dut.clk, 4)
    assert int(dut.busy.value) == 1, "busy muss waehrend Record-Wait aktiv sein"
    assert int(dut.rec_done.value) == 0, "rec_done darf ohne dec_valid nicht kommen"

    # Jetzt gueltiges Decoded-Frame liefern.
    await send_decoded_word(dut, address=0x12AB, command=0x5C, flags=0x00)
    got_rec_done = await _wait_for_pulse(dut, "rec_done", max_cycles=32)
    assert got_rec_done, "rec_done wurde nicht erkannt"
    assert int(dut.error.value) == 0, "error darf im Record-Happy-Path nicht aktiv sein"

    # Replay ausloesen und auf TX-Aktivitaet + rep_done warten.
    await trigger_replay(dut, slot=0)

    prev = int(dut.ir_tx_npn_drive.value)
    tx_toggles = 0
    got_rep_done = False
    for _ in range(1_200_000):
        await RisingEdge(dut.clk)
        cur = int(dut.ir_tx_npn_drive.value)
        if cur != prev:
            tx_toggles += 1
        prev = cur
        if int(dut.rep_done.value) == 1:
            got_rep_done = True
            break

    assert tx_toggles > 0, "TX-Ausgang hat waehrend Replay nicht getoggelt"
    assert got_rep_done, "rep_done wurde nicht erkannt"
    assert int(dut.error.value) == 0, "error darf im Replay-Happy-Path nicht aktiv sein"


def test_ir_recorder_replay_top_runner():
    """Simulate ir_recorder_replay_top with full integration sources."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    repo_root = proj_path.parent
    rr_root = repo_root / "IRRecorder_Replay"
    sources = [
      rr_root / "Types_PKG" / "src" / "ir_types_pkg.sv",
      repo_root / "IRDecoder" / "EdgeDetector" / "src" / "edge_detector.sv",
      repo_root / "IRDecoder" / "PulseTimer" / "src" / "pulse_timer.sv",
      repo_root / "IRDecoder" / "NECDecoder" / "src" / "nec_decoder.sv",
      repo_root / "IRDecoder" / "OutputFormatter" / "src" / "output_formatter.sv",
      repo_root / "IRDecoder" / "UART_TX" / "src" / "uart_tx.sv",
      rr_root / "Recorder" / "src" / "ir_recorder.sv",
      rr_root / "STORAGE_BRAM" / "src" / "ir_storage_bram.sv",
      rr_root / "Replay_FSM" / "src" / "ir_replay_fsm.sv",
      rr_root / "nec_encoder" / "src" / "nec_encoder.sv",
      rr_root / "TX" / "src" / "ir_tx.sv",
      proj_path / "src" / "ir_recorder_replay_top.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ir_recorder_replay_top",
        defines={"SIMULATION": 1},
        always=True,
    )

    runner.test(
        hdl_toplevel="ir_recorder_replay_top",
        test_module="test_ir_closed_loop",
    )


if __name__ == "__main__":
    test_ir_recorder_replay_top_runner()
