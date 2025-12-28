SHELL:=/bin/bash
.DEFAULT_GOAL := _help

.PHONY: _help
_help:
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'

# Absolute path needed for kcov to track source files correctly
PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_SYSTEM  := $(COV_ROOT)/system

.PHONY: cov-sys
cov-sys: check-deps	##H Run system tests (Standard kcov invocation)
	@echo "🚀 [System] Preparing coverage..."
	@mkdir -p $(COV_SYSTEM)

	@echo "🧪 Running kcov on system-test-multikey.sh..."
	@# We export GPG_TTY to give GPG the best chance of working without patches.
	@# We use --include-path=$(PWD) to ensure the source is tracked even if the script changes dirs.
	@export GPG_TTY=$$(tty); \
	kcov --bash-handle-sh-invocation \
	     --include-path=$(PWD) \
	     --include-pattern=git-remote-gcrypt \
	     --exclude-path=$(PWD)/.git,$(PWD)/tests \
	     $(COV_SYSTEM) \
	     ./tests/system-test-multikey.sh

	@echo "✅ [System] Done. Report: file://$(COV_SYSTEM)/index.html"

.PHONY: check-deps
check-deps:	##H Check for kcov
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }

.PHONY: clean
clean:	##H Clean artifacts
	rm -rf .coverage
