WORK_DIR=$(shell pwd)
TOP=top
TAG=top-run

PDK_ROOT ?= $(WORK_DIR)/../pdk
PDK = ihp-sg13g2

.PHONY: librelane
librelane:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG) --overwrite config_fast.yaml

.PHONY: librelane-drc-debug
librelane-drc-debug:
	cd src && PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag drc-debug --overwrite config_drc_debug.yaml

.PHONY: librelane-signoff-quick
librelane-signoff-quick:
	cd src && PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag signoff-quick --overwrite config_signoff_quick.yaml

.PHONY: librelane-tapeout
librelane-tapeout:
	cd src && PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag tapeout --overwrite config_tapeout.yaml

.PHONY: view-results
view-results:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml
