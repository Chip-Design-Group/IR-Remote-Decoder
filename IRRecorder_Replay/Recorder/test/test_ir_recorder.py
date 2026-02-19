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
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, NextTimeStep, ReadOnly, RisingEdge


IR_FLAG_WIDTH = 8
IR_FRAME_BITS_WIDTH = 6
IR_PROTOCOL_ID_WIDTH = 5
PROTOCOL_SHIFT = IR_FLAG_WIDTH
FRAME_BITS_SHIFT = PROTOCOL_SHIFT + IR_PROTOCOL_ID_WIDTH
FRAME_DATA_SHIFT = FRAME_BITS_SHIFT + IR_FRAME_BITS_WIDTH

def _build_frame_data(address, command):
    addr = address & 0xFF
    cmd = command & 0xFF
    return (((~cmd & 0xFF) << 24) |
            (cmd << 16) |
            ((~addr & 0xFF) << 8) |
            addr)

def _pack_payload(address, command, flags, protocol_id=0x01, frame_bits=32):
    frame_data = _build_frame_data(address, command) & ((1 << 32) - 1)
    word = ((frame_data << FRAME_DATA_SHIFT) |
            ((frame_bits & ((1 << IR_FRAME_BITS_WIDTH) - 1)) << FRAME_BITS_SHIFT) |
            ((protocol_id & ((1 << IR_PROTOCOL_ID_WIDTH) - 1)) << PROTOCOL_SHIFT) |
            (flags & 0xFF))
    return word


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())


async def _reset_dut(dut, cycles=4):
    dut.rst_n.value = 0
    dut.record_req.value = 0
    dut.target_slot.value = 0
    dut.dec_valid.value = 0
    dut.dec_payload.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)


async def _drive_record_request(dut, slot, address, command, flags, valid_delay_cycles=0):
    dut.target_slot.value = slot
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(address, command, flags)
    await ClockCycles(dut.clk, valid_delay_cycles)
    dut.dec_valid.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()
    await NextTimeStep()
    dut.dec_valid.value = 0
    dut.record_req.value = 0


async def _wait_for_pulse(dut, signal_name, max_cycles=256):
    sig = getattr(dut, signal_name)
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(sig.value) == 1:
            await NextTimeStep()
            return True
    return False


async def _wait_for_pulse_with_cycle_count(dut, signal_name, max_cycles=2048):
    sig = getattr(dut, signal_name)
    for cycle in range(1, max_cycles + 1):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(sig.value) == 1:
            await NextTimeStep()
            return True, cycle
    return False, max_cycles


# Checks reset drives the recorder outputs to idle defaults.
@cocotb.test()
async def test_recorder_reset_defaults(dut):
    await _start_clock(dut)
    await _reset_dut(dut)
    await ReadOnly()
    assert int(dut.mem_wr_en.value) == 0, "mem_wr_en must be 0 after reset"
    assert int(dut.done.value) == 0, "done must be 0 after reset"
    assert int(dut.error.value) == 0, "error must be 0 after reset"


# Checks one valid record request writes packed payload to selected slot.
@cocotb.test()
async def test_record_single_code(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    slot = 0
    address = 0x00FF
    command = 0x34
    flags = 0x03
    expected_word = _pack_payload(address, command, flags)

    await _drive_record_request(dut, slot, address, command, flags, valid_delay_cycles=0)
    saw_wr = await _wait_for_pulse(dut, "mem_wr_en")
    assert saw_wr, "mem_wr_en pulse expected for successful recording"
    assert int(dut.mem_wr_addr.value) == slot, "mem_wr_addr mismatch"
    assert int(dut.mem_wr_data.value) == expected_word, "mem_wr_data packing mismatch"
    assert int(dut.error.value) == 0, "error must stay low on successful recording"

    saw_done = await _wait_for_pulse(dut, "done")
    assert saw_done, "done pulse expected after successful recording"


# Checks busy is asserted while waiting for dec_valid after record request.
@cocotb.test()
async def test_record_busy_while_waiting_for_valid(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 0
    dut.record_req.value = 1
    dut.dec_payload.value = _pack_payload(0x1234, 0x56, 0x01)
    dut.dec_valid.value = 0

    busy_seen = False
    for _ in range(8):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.busy.value) == 1:
            busy_seen = True
            break
    assert busy_seen, "busy must assert while waiting for valid decoded payload"

    await NextTimeStep()
    dut.dec_valid.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()
    await NextTimeStep()
    dut.dec_valid.value = 0
    dut.record_req.value = 0


# Checks no write occurs when dec_valid toggles without a record request.
@cocotb.test()
async def test_no_write_without_record_request(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 0
    dut.record_req.value = 0
    dut.dec_payload.value = _pack_payload(0xAAAA, 0x55, 0x01)
    dut.dec_valid.value = 1
    await ClockCycles(dut.clk, 4)
    await ReadOnly()

    assert int(dut.mem_wr_en.value) == 0, "must not write without record_req"
    assert int(dut.done.value) == 0, "done must stay low without record_req"
    assert int(dut.error.value) == 0, "error must stay low without request flow"

    await NextTimeStep()
    dut.dec_valid.value = 0


# Checks target_slot is forwarded to memory write address.
@cocotb.test()
async def test_target_slot_forwarded_to_mem_wr_addr(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    slot_width = len(dut.target_slot)
    slot = (1 << slot_width) - 1
    await _drive_record_request(dut, slot, 0x2222, 0x77, 0x00, valid_delay_cycles=1)
    saw_wr = await _wait_for_pulse(dut, "mem_wr_en")
    assert saw_wr, "mem_wr_en pulse expected"
    assert int(dut.mem_wr_addr.value) == slot, "write address must match requested slot"


# Checks done behaves like a one-cycle pulse for a successful record.
@cocotb.test()
async def test_done_is_single_cycle_pulse(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    await _drive_record_request(dut, 0, 0x0ACE, 0x99, 0x01, valid_delay_cycles=0)
    saw_done = await _wait_for_pulse(dut, "done")
    assert saw_done, "done pulse expected"

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.done.value) == 0, "done must deassert after one cycle"


# Checks mem_wr_en behaves like a one-cycle pulse on a successful write.
@cocotb.test()
async def test_mem_wr_en_is_single_cycle_pulse(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    await _drive_record_request(dut, 0, 0x0BEE, 0x42, 0x01, valid_delay_cycles=0)
    saw_wr = await _wait_for_pulse(dut, "mem_wr_en")
    assert saw_wr, "mem_wr_en pulse expected"

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.mem_wr_en.value) == 0, "mem_wr_en must deassert after one cycle"


# Checks busy is deasserted again after a successful record completion.
@cocotb.test()
async def test_busy_clears_after_done(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    await _drive_record_request(dut, 0, 0xABCD, 0x55, 0x01, valid_delay_cycles=2)
    saw_done = await _wait_for_pulse(dut, "done")
    assert saw_done, "done pulse expected"

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.busy.value) == 0, "busy must be low after completion"


# Checks two sequential record operations generate two independent writes.
@cocotb.test()
async def test_two_sequential_records(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    # First record
    await _drive_record_request(dut, 0, 0x1111, 0x10, 0x01, valid_delay_cycles=0)
    saw_wr_1 = await _wait_for_pulse(dut, "mem_wr_en")
    assert saw_wr_1, "first write pulse expected"
    data_1 = int(dut.mem_wr_data.value)

    # Second record
    await _drive_record_request(dut, 1, 0x2222, 0x20, 0x03, valid_delay_cycles=0)
    saw_wr_2 = await _wait_for_pulse(dut, "mem_wr_en")
    assert saw_wr_2, "second write pulse expected"
    data_2 = int(dut.mem_wr_data.value)

    assert data_1 != data_2, "sequential records should carry different payload words"


# Checks error is raised if dec_valid never arrives after a record request.
@cocotb.test()
async def test_record_without_valid_frame_sets_error(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 0
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(0x3333, 0x44, 0x00)

    saw_error = await _wait_for_pulse(dut, "error", max_cycles=1024)
    assert saw_error, "error pulse expected when no valid frame arrives"

    await NextTimeStep()
    dut.record_req.value = 0


# Checks timeout reaches error after the configured number of wait cycles.
@cocotb.test()
async def test_error_timeout_cycle_count(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    timeout_cycles = int(dut.WAIT_TIMEOUT_CYCLES.value)

    dut.target_slot.value = 0
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(0xAAAA, 0x11, 0x00)

    saw_error, cycles_to_error = await _wait_for_pulse_with_cycle_count(
        dut, "error", max_cycles=timeout_cycles + 16
    )
    assert saw_error, "error pulse expected"
    # Current FSM behavior from request edge: one cycle into WAIT_VALID, timeout window,
    # then one cycle for ST_ERROR pulse.
    assert cycles_to_error == timeout_cycles + 2, (
        f"error timing mismatch: got {cycles_to_error}, expected {timeout_cycles + 2}"
    )

    await NextTimeStep()
    dut.record_req.value = 0


# Checks error behaves like a one-cycle pulse.
@cocotb.test()
async def test_error_is_single_cycle_pulse(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 0
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(0xAAAA, 0x22, 0x00)

    saw_error = await _wait_for_pulse(dut, "error", max_cycles=2048)
    assert saw_error, "error pulse expected on timeout"

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.error.value) == 0, "error must deassert after one cycle"

    await NextTimeStep()
    dut.record_req.value = 0


# Checks busy is low once timeout/error handling has completed.
@cocotb.test()
async def test_busy_clears_after_error(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 0
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(0xABCD, 0x33, 0x00)

    saw_error = await _wait_for_pulse(dut, "error", max_cycles=2048)
    assert saw_error, "error pulse expected"

    await NextTimeStep()
    dut.record_req.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.busy.value) == 0, "busy must be low after timeout completion"


# Checks recorder can accept a new record immediately after an error event.
@cocotb.test()
async def test_back_to_back_retry_directly_after_error(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 1
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(0x1111, 0x44, 0x00)

    saw_error = await _wait_for_pulse(dut, "error", max_cycles=2048)
    assert saw_error, "error pulse expected before retry"

    # Keep record_req asserted and provide valid payload immediately for retry.
    await NextTimeStep()
    dut.dec_payload.value = _pack_payload(0x2222, 0x55, 0x01)
    dut.dec_valid.value = 1

    saw_wr = await _wait_for_pulse(dut, "mem_wr_en", max_cycles=8)
    assert saw_wr, "write pulse expected for immediate retry after error"
    assert int(dut.mem_wr_addr.value) == 1, "retry must keep requested target slot"

    saw_done = await _wait_for_pulse(dut, "done", max_cycles=8)
    assert saw_done, "done pulse expected after successful retry"

    await NextTimeStep()
    dut.dec_valid.value = 0
    dut.record_req.value = 0


# Checks reset during an active request clears recorder outputs back to idle.
@cocotb.test()
async def test_reset_during_active_request_clears_outputs(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    dut.target_slot.value = 0
    dut.record_req.value = 1
    dut.dec_valid.value = 0
    dut.dec_payload.value = _pack_payload(0x1357, 0x9B, 0x00)
    await ClockCycles(dut.clk, 3)

    await NextTimeStep()
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await ReadOnly()
    assert int(dut.mem_wr_en.value) == 0, "mem_wr_en must be low during reset"
    assert int(dut.done.value) == 0, "done must be low during reset"
    assert int(dut.error.value) == 0, "error must be low during reset"
    assert int(dut.busy.value) == 0, "busy must be low during reset"

    await NextTimeStep()
    dut.record_req.value = 0
    dut.dec_valid.value = 0
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
