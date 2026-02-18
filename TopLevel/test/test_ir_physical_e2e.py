"""
File: test_ir_physical_e2e.py
Purpose:
  True End-to-End Test: Physical IR Pulses -> Decoder -> Recorder -> Replay -> IR TX.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from cocotb_tools.runner import get_runner

from test_helpers import reset_dut, send_nec_ir_frame_physical, trigger_replay


async def _wait_for_pulse(dut, signal_name, max_cycles=1000):
    sig = getattr(dut, signal_name)
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(sig.value) == 1:
            return True
    return False


@cocotb.test(timeout_time=200, timeout_unit="ms")
async def test_physical_record_replay(dut):
    """
    1. Send valid NEC frame via physical pulses on ir_in.
    2. Wait for Decoder to decode and Recorder to finish (rec_done).
    3. Trigger Replay.
    4. Verify IR TX toggles and Replay finishes (rep_done).
    """
    # 10 MHz clock (100ns period)
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    
    # Initialize
    await reset_dut(dut)
    dut.use_external_decoder_data.value = 0 # IMPORTANT: Use internal decoder! (Must be after reset_dut)

    # 1. Start Recording
    dut.slot_sel.value = 0
    dut.record_req.value = 1
    await RisingEdge(dut.clk)
    dut.record_req.value = 0

    # 2. Send physical NEC frame (Addr 0x12, Cmd 0x5C)
    # Fork the send task, because rec_done will verify shortly after the start of the stop burst,
    # which is BEFORE send_nec_ir_frame_physical returns.
    send_task = cocotb.start_soon(send_nec_ir_frame_physical(dut, address=0x12, command=0x5C))



    # 3. Wait for rec_done
    # Recorder needs to see valid flag from decoder, which happens near the end of the frame
    # Increase timeout to be safe
    got_rec_done = await _wait_for_pulse(dut, "rec_done", max_cycles=2_000_000)
    
    if not got_rec_done:
        # Debug info if failed
        dut._log.error(f"Recorder Status: Busy={dut.rec_busy.value}, Error={dut.rec_error.value}")
        dut._log.error(f"Decoder Status: Valid={dut.dec_data_valid_i.value}, Error={dut.dec_error_i.value}, State={dut.u_nec_decoder.current_state.value}")
        
    assert got_rec_done, "Recorder did not finish (rec_done not detected)"
    assert int(dut.error.value) == 0, "Error asserted during recording"

    # Wait for sender to finish strictly
    await send_task

    # 4. Trigger Replay
    await trigger_replay(dut, slot=0)

    # 5. Verify Output matches protocol (at least activity)
    prev = int(dut.ir_tx_npn_drive.value)
    tx_toggles = 0
    got_rep_done = False
    
    # Replay takes similar time to record (~70ms)
    # 70ms / 100ns = 700,000 cycles
    for _ in range(800_000):
        await RisingEdge(dut.clk)
        cur = int(dut.ir_tx_npn_drive.value)
        if cur != prev:
            tx_toggles += 1
        prev = cur
        if int(dut.rep_done.value) == 1:
            got_rep_done = True
            break

    assert tx_toggles > 100, f"IR TX should activity during replay, got {tx_toggles} toggles"
    assert got_rep_done, "Replay did not finish"
    assert int(dut.error.value) == 0, "Error asserted during replay"


def test_ir_physical_e2e_runner():
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
        test_module="test_ir_physical_e2e",
    )


if __name__ == "__main__":
    test_ir_physical_e2e_runner()
