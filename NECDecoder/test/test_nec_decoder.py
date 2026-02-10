import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_nec_decode_valid_frame(dut):
    """Test decoding of a valid NEC frame."""
    # TODO: Implement test
    pass

@cocotb.test()
async def test_nec_checksum_error(dut):
    """Test handling of invalid checksum."""
    # TODO: Implement test
    pass
