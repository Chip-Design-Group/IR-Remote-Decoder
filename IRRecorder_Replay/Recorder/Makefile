TOPLEVEL_LANG = verilog
SIM ?= icarus

# DUT / test configuration
TOPLEVEL = ir_recorder
COCOTB_TEST_MODULES = test_ir_recorder
export PYTHONPATH := $(PWD)/test:$(PYTHONPATH)

# SystemVerilog sources (package first)
VERILOG_SOURCES = \
	$(PWD)/../Types_PKG/src/ir_types_pkg.sv \
	$(PWD)/src/ir_recorder.sv

# Icarus needs SV-2012 for package/import support.
COMPILE_ARGS += -g2012

.PHONY: test clean-local

HAVE_IVERILOG := $(shell command -v iverilog 2>/dev/null)
HAVE_VVP := $(shell command -v vvp 2>/dev/null)

test:
	$(MAKE) sim

clean-local:
	rm -rf sim_build test/__pycache__ __pycache__ *.vcd *.fst results.xml

ifeq ($(strip $(HAVE_IVERILOG)),)
sim:
	@echo "ERROR: iverilog not found in PATH."
	@echo "Run inside nix-shell (e.g. from librelane/) or install Icarus Verilog."
	@exit 1
else ifeq ($(strip $(HAVE_VVP)),)
sim:
	@echo "ERROR: vvp not found in PATH."
	@echo "Run inside nix-shell (e.g. from librelane/) or install Icarus Verilog."
	@exit 1
else
include $(shell cocotb-config --makefiles)/Makefile.sim
endif
