.PHONY: librelane view-results

librelane:
	librelane --pdk ihp-sg13g2 --run-tag Chip_run --overwrite config.yaml

view-results:
	librelane --pdk ihp-sg13g2 --last-run --flow OpenInOpenROAD config.yaml
