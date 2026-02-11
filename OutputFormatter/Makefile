TOPLEVEL_LANG = verilog
SIM = icarus

# Top-level module and testbench
TOPLEVEL = output_formatter
export PYTHONPATH := $(PWD)/test:$(PYTHONPATH)
COCOTB_TEST_MODULES = test_output_formatter
# Paths
VERILOG_SOURCES = /workspaces/IR-Remote-Decoder/OutputFormatter/src/output_formatter.sv

# Run cocotb
include $(shell cocotb-config --makefiles)/Makefile.sim