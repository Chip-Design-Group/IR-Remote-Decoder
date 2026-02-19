.PHONY: librelane librelane-fast librelane-signoff librelane-without-padframe view-results

# Default config if no CONFIG is provided.
CONFIG ?= config_signoff.yaml
RUN_TAG ?= Chip_run

librelane:
	librelane --pdk ihp-sg13g2 --run-tag $(RUN_TAG) --overwrite $(CONFIG)

librelane-fast:
	librelane --pdk ihp-sg13g2 --run-tag Chip_run_fast --overwrite config_fast.yaml

librelane-signoff:
	librelane --pdk ihp-sg13g2 --run-tag Chip_run_signoff --overwrite config_signoff.yaml

librelane-without-padframe:
	librelane --pdk ihp-sg13g2 --run-tag Chip_run_nopad --overwrite config_withoupadframe.yaml

view-results:
	librelane --pdk ihp-sg13g2 --last-run --flow OpenInOpenROAD $(CONFIG)
