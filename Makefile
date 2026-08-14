.PHONY: check build

check:
	bash -n scripts/build-rootfs.sh
	bash -n scripts/validate-rootfs.sh
	bash -n scripts/version-summary.sh
	python3 -m py_compile scripts/package-diff.py
	awk 'NF && $$1 !~ /^#/ { if (seen[$$1]++) { print "duplicate package: " $$1 > "/dev/stderr"; bad=1 } } END { exit bad }' packages.txt

build:
	bash scripts/build-rootfs.sh
