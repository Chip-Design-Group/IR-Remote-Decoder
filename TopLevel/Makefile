WORK_DIR=$(shell pwd)
PDK_ROOT ?= $(WORK_DIR)/../pdk
PDK = ihp-sg13g2

.PHONY: librelane-fast
librelane-fast:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag fast --overwrite config_fast.yaml

.PHONY: librelane-signoff
librelane-signoff:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag signoff --overwrite config_signoff.yaml

.PHONY: view-results
view-results:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml
