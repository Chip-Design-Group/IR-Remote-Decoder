WORK_DIR := $(shell pwd)

.PHONY: help test sim clean tree librelane

help:
	@echo "Available targets:"
	@echo "  make test       - Run Cocotb/Pytest tests in test/"
	@echo "  make sim        - Run simulation helper in sim/"
	@echo "  make librelane  - Run LibreLane flow (requires nix-shell librelane/)"
	@echo "  make clean      - Clean test and sim artifacts"
	@echo "  make tree       - Show current module structure"

test:
	$(MAKE) -C test test

sim:
	$(MAKE) -C sim run

librelane:
	@echo "TODO: LibreLane-Flow anbinden (config.yaml + make librelane)."
	@echo "Hinweis: Vorher 'nix-shell ../../librelane/' starten."

clean:
	$(MAKE) -C test clean
	@rm -rf sim/sim_build sim/*.vcd sim/*.fst sim/*.log

tree:
	@find . -maxdepth 2 -type d | sort
