SHELL:=/bin/bash
.DEFAULT_GOAL := _help

.PHONY: _help
_help:
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'

PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_SYSTEM  := $(COV_ROOT)/system
WRAPPER_DIR := $(COV_ROOT)/wrapper

.PHONY: cov-sys
cov-sys: check-deps	##H Run system tests using a wrapper to capture coverage safely
	@echo "🚀 [System] Preparing coverage..."
	@rm -rf $(COV_SYSTEM) $(WRAPPER_DIR)
	@mkdir -p $(COV_SYSTEM) $(WRAPPER_DIR)

	@# --- CREATE WRAPPER ---
	@# We create a fake 'git-remote-gcrypt' that actually runs kcov on the real script.
	@# This avoids kcov messing up the test script's shell or pipes.
	@echo '#!/bin/bash' > $(WRAPPER_DIR)/git-remote-gcrypt
	@echo 'exec kcov --include-pattern=git-remote-gcrypt --exclude-path=.git,tests $(COV_SYSTEM) $(PWD)/git-remote-gcrypt "$$@"' >> $(WRAPPER_DIR)/git-remote-gcrypt
	@chmod +x $(WRAPPER_DIR)/git-remote-gcrypt
	@# ---------------------

	@echo "🧪 Running system-test-multikey.sh with wrapper..."
	@# We inject our wrapper into the PATH so git uses IT instead of the real one.
	@# We export GPG_TTY so GPG works without patches.
	@export PATH="$(WRAPPER_DIR):$$PATH"; \
	 export GPG_TTY=$$(tty); \
	 ./tests/system-test-multikey.sh

	@echo "✅ [System] Done. Report: file://$(COV_SYSTEM)/index.html"

.PHONY: check-deps
check-deps:	##H Check for kcov
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }

.PHONY: clean
clean:	##H Clean artifacts
	rm -rf .coverage
