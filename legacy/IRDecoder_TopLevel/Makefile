WORK_DIR=$(shell pwd)
TOP=ir_decoder_top
TAG=ir_decoder_run

PDK_ROOT ?= $(WORK_DIR)/../../pdk
PDK = ihp-sg13g2

.PHONY: test
test:
	# Run all tests in the repository
	pytest ../../


.PHONY: clean
clean:
	rm -rf sim_build
	rm -rf __pycache__
	rm -rf runs

.PHONY: librelane
librelane:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG) --overwrite config.yaml

.PHONY: view-results
view-results:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml
