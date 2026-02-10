import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotb_tools.runner import get_runner

@cocotb.test()
async def test_edge_detection_basic(dut):
    """Test basic edge detection."""
    # TODO: Implement test
    pass

def test_edge_detector_runner():
    """Simulate the edge_detector using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "src" / "edge_detector.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="edge_detector",
        always=True,
    )

    runner.test(
        hdl_toplevel="edge_detector",
        test_module="test_edge_detector",
    )

if __name__ == "__main__":
    test_edge_detector_runner()