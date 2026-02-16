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
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, NextTimeStep, ReadOnly, RisingEdge


def _mask(width):
    return (1 << width) - 1


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())


async def _reset_dut(dut, cycles=4):
    dut.rst_n.value = 0
    dut.wr_en.value = 0
    dut.wr_addr.value = 0
    dut.wr_data.value = 0
    dut.rd_en.value = 0
    dut.rd_addr.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)


async def _write_slot(dut, addr, data):
    dut.wr_addr.value = addr
    dut.wr_data.value = data
    dut.wr_en.value = 1
    dut.rd_en.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    await NextTimeStep()
    dut.wr_en.value = 0


async def _read_slot(dut, addr):
    dut.rd_addr.value = addr
    dut.rd_en.value = 1
    dut.wr_en.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    valid = int(dut.rd_valid.value)
    data = int(dut.rd_data.value)
    await NextTimeStep()
    dut.rd_en.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    valid_next = int(dut.rd_valid.value)
    await NextTimeStep()
    return valid, data, valid_next


async def _single_cycle_activity(dut, wr_en=0, wr_addr=0, wr_data=0, rd_en=0, rd_addr=0):
    dut.wr_en.value = wr_en
    dut.wr_addr.value = wr_addr
    dut.wr_data.value = wr_data
    dut.rd_en.value = rd_en
    dut.rd_addr.value = rd_addr
    await RisingEdge(dut.clk)
    await ReadOnly()
    valid = int(dut.rd_valid.value)
    data = int(dut.rd_data.value)
    await NextTimeStep()
    return valid, data


# Checks that reset leaves the read-valid output deasserted.
@cocotb.test()
async def test_bram_reset_deasserts_rd_valid(dut):
    await _start_clock(dut)
    await _reset_dut(dut)
    assert int(dut.rd_valid.value) == 0, "rd_valid must be 0 after reset release"


# Checks write followed by read from the same slot returns the written word.
@cocotb.test()
async def test_bram_write_then_read_same_slot(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    slot = min(1, (1 << addr_w) - 1)
    payload = 0xA5A5_1234 & _mask(data_w)

    await _write_slot(dut, slot, payload)
    valid, data, valid_next = await _read_slot(dut, slot)

    assert valid == 1, "rd_valid must assert for a read"
    assert data == payload, f"read data mismatch: got 0x{data:X}, expected 0x{payload:X}"
    assert valid_next == 0, "rd_valid should pulse for one cycle"


# Checks that two different slots keep independent values.
@cocotb.test()
async def test_bram_slots_are_independent(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    max_slot = (1 << addr_w) - 1
    slot_a = 0
    slot_b = 1 if max_slot >= 1 else 0

    data_a = 0x1111_00AA & _mask(data_w)
    data_b = 0x2222_00BB & _mask(data_w)

    await _write_slot(dut, slot_a, data_a)
    await _write_slot(dut, slot_b, data_b)

    valid_a, read_a, _ = await _read_slot(dut, slot_a)
    valid_b, read_b, _ = await _read_slot(dut, slot_b)

    assert valid_a == 1 and valid_b == 1, "rd_valid must assert for both reads"
    assert read_a == data_a, "slot A data corrupted"
    assert read_b == data_b, "slot B data corrupted"


# Checks that rewriting one slot updates only that slot.
@cocotb.test()
async def test_bram_overwrite_updates_target_slot_only(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    max_slot = (1 << addr_w) - 1
    slot_x = min(2, max_slot)
    slot_y = 0

    first = 0x0F0F_0F0F & _mask(data_w)
    second = 0xF0F0_F0F0 & _mask(data_w)
    other = 0x1234_5678 & _mask(data_w)

    await _write_slot(dut, slot_x, first)
    await _write_slot(dut, slot_y, other)
    await _write_slot(dut, slot_x, second)

    valid_x, read_x, _ = await _read_slot(dut, slot_x)
    valid_y, read_y, _ = await _read_slot(dut, slot_y)

    assert valid_x == 1 and valid_y == 1, "rd_valid must assert on reads"
    assert read_x == second, "overwrite did not update target slot"
    assert read_y == other, "overwrite modified a different slot unexpectedly"


# Checks rd_valid is high for one cycle and low again afterwards.
@cocotb.test()
async def test_bram_rd_valid_is_single_cycle_pulse(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    slot = min(1, (1 << addr_w) - 1)
    payload = 0xDEAD_BEEF & _mask(data_w)

    await _write_slot(dut, slot, payload)
    valid, _, valid_next = await _read_slot(dut, slot)

    assert valid == 1, "rd_valid should assert on read response"
    assert valid_next == 0, "rd_valid should deassert the cycle after response"


# Checks that rd_valid stays low when no read request is issued.
@cocotb.test()
async def test_bram_no_read_request_keeps_rd_valid_low(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    for _ in range(4):
        valid, _ = await _single_cycle_activity(dut, wr_en=0, rd_en=0)
        assert valid == 0, "rd_valid must stay low if rd_en is not asserted"


# Checks read-before-write behavior by confirming a valid pulse and stable output.
@cocotb.test()
async def test_bram_read_before_first_write(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    slot = min(1, (1 << addr_w) - 1)

    valid, _, valid_next = await _read_slot(dut, slot)
    assert valid == 1, "rd_valid must assert for read-before-write as well"
    assert valid_next == 0, "rd_valid should still be a single-cycle pulse"


# Checks back-to-back writes and reads across multiple cycles.
@cocotb.test()
async def test_bram_back_to_back_writes_and_reads(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    max_slot = (1 << addr_w) - 1

    slots = [0, min(1, max_slot), min(2, max_slot)]
    payloads = [
        0x0102_0304 & _mask(data_w),
        0x1122_3344 & _mask(data_w),
        0x5566_7788 & _mask(data_w),
    ]

    for slot, payload in zip(slots, payloads):
        await _write_slot(dut, slot, payload)

    for slot, payload in zip(slots, payloads):
        valid, data, valid_next = await _read_slot(dut, slot)
        assert valid == 1, "rd_valid must assert for each back-to-back read"
        assert data == payload, f"unexpected data for slot {slot}"
        assert valid_next == 0, "rd_valid must deassert after each read response"


# Checks address boundary handling for first and last slot.
@cocotb.test()
async def test_bram_boundary_addresses_first_and_last_slot(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    first = 0
    last = (1 << addr_w) - 1

    data_first = 0x0000_00A1 & _mask(data_w)
    data_last = 0xFFFF_FF5E & _mask(data_w)

    await _write_slot(dut, first, data_first)
    await _write_slot(dut, last, data_last)

    v0, d0, _ = await _read_slot(dut, first)
    v1, d1, _ = await _read_slot(dut, last)

    assert v0 == 1 and v1 == 1, "rd_valid must assert for both boundary reads"
    assert d0 == data_first, "first slot data mismatch"
    assert d1 == data_last, "last slot data mismatch"


# Checks simultaneous read/write in one cycle and verifies data consistency afterwards.
@cocotb.test()
async def test_bram_simultaneous_read_write_consistency(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    max_slot = (1 << addr_w) - 1
    slot_read = 0
    slot_write = 1 if max_slot >= 1 else 0

    pre = 0xAAAA_0001 & _mask(data_w)
    new = 0xBBBB_0002 & _mask(data_w)

    await _write_slot(dut, slot_read, pre)
    valid, _ = await _single_cycle_activity(
        dut,
        wr_en=1,
        wr_addr=slot_write,
        wr_data=new,
        rd_en=1,
        rd_addr=slot_read,
    )
    assert valid == 1, "rd_valid must assert when rd_en is high in simultaneous access"

    v_r, d_r, _ = await _read_slot(dut, slot_read)
    v_w, d_w, _ = await _read_slot(dut, slot_write)
    assert v_r == 1 and v_w == 1, "both post-check reads must be valid"
    assert d_r == pre, "simultaneous write must not corrupt read slot"
    assert d_w == new, "simultaneous write data was not stored correctly"


# Checks reset during ongoing access clears rd_valid and allows clean recovery.
@cocotb.test()
async def test_bram_reset_during_activity_recovers_cleanly(dut):
    await _start_clock(dut)
    await _reset_dut(dut)

    addr_w = len(dut.wr_addr)
    data_w = len(dut.wr_data)
    slot = min(1, (1 << addr_w) - 1)
    payload = 0x0BAD_C0DE & _mask(data_w)

    await _write_slot(dut, slot, payload)
    dut.rd_en.value = 1
    dut.rd_addr.value = slot
    await RisingEdge(dut.clk)
    dut.rst_n.value = 0
    dut.rd_en.value = 0
    dut.wr_en.value = 0
    await ClockCycles(dut.clk, 2)
    await ReadOnly()
    assert int(dut.rd_valid.value) == 0, "rd_valid must be low during reset"

    await NextTimeStep()
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    valid, data, valid_next = await _read_slot(dut, slot)
    assert valid == 1, "read should work again after reset release"
    assert data == payload, "stored payload should remain readable after reset"
    assert valid_next == 0, "rd_valid should keep pulse behavior after recovery"
