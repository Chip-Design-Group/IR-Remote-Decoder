WORK_DIR := $(shell pwd)

.PHONY: help test sim clean tree librelane

help:
	@echo "Available targets:"
	@echo "  make test       - Run Cocotb/Pytest tests in modules/*/test/"
	@echo "  make sim        - Run simulation helper in sim/"
	@echo "  make librelane  - Run LibreLane flow (requires nix-shell librelane/)"
	@echo "  make clean      - Clean pytest and sim artifacts"
	@echo "  make tree       - Show current module structure"

test:
	pytest modules/*/test

sim:
	$(MAKE) -C sim run

librelane:
	@echo "TODO: LibreLane-Flow anbinden (config.yaml + make librelane)."
	@echo "Hinweis: Vorher 'nix-shell ../../librelane/' starten."

clean:
	@find modules -type d -name __pycache__ -prune -exec rm -rf {} +
	@find modules -type d -name sim_build -prune -exec rm -rf {} +
	@rm -rf sim/sim_build sim/*.vcd sim/*.fst sim/*.log

tree:
	@find . -maxdepth 3 -type d | sort
