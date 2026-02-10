WORK_DIR=$(shell pwd)
PDK_ROOT ?= $(WORK_DIR)/../pdk
PDK = ihp-sg13g2

.PHONY: test
test:
	pytest test/

.PHONY: clean
clean:
	rm -rf sim_build
	rm -rf __pycache__
