WORK_DIR=$(shell pwd)
PDK_ROOT ?= $(WORK_DIR)/../../pdk
PDK = ihp-sg13g2

.PHONY: test
test:
	SIM=icarus python test/test_uart_tx.py

.PHONY: clean
clean:
	rm -rf sim_build __pycache__ *.vcd
