SHELL:=/bin/bash
#.DEFAULT_GOAL=_help

#.PHONY: test
#test:
## 	kcov --include-path=./git-remote-gcrypt .kcov/ ./tests/system-test*.sh
## 	kcov --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
## 		coverage_dir
## 		./tests/system-test-multikey.sh
#	kcov --include-path=$(pwd) --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
#		.kcov ./tests/system-test.sh
#	kcov --include-path=$(pwd) --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
#		--merge .kcov ./tests/system-test-multikey.sh


#.PHONY: clean
#clean:
#	rm -rf .kcov/*

# NEW ~~~~~~~~~~~~
# Makefile for git-remote-gcrypt coverage (Local/Non-Docker)

# Get absolute path to avoid LD_PRELOAD errors
PWD := $(shell pwd)
COVERAGE_DIR := $(PWD)/.coverage/installer
TEST_SCRIPT := ./tests/test-install-logic.sh

.PHONY: coverage clean open check-deps install-deps

# Default target: Run coverage
coverage: check-deps
	@echo "🚀 Preparing coverage directory..."
	@mkdir -p $(COVERAGE_DIR)

	@echo "🧪 Running kcov locally..."
	@# We use $(PWD) for the output to ensure LD_PRELOAD works correctly
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=.git,tests \
	     $(COVERAGE_DIR) \
	     $(TEST_SCRIPT)

	@echo "✅ Done! Report generated at:"
	@echo "   file://$(COVERAGE_DIR)/index.html"

# Helper to check if tools are installed
check-deps:
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }
	@command -v rst2man >/dev/null 2>&1 || command -v rst2man.py >/dev/null 2>&1 || { \
		echo "⚠️  Warning: 'rst2man' (python3-docutils) is missing."; \
		echo "   You won't hit the 'Happy Path' for man page generation (lines 50-52)."; \
		echo "   Install it to see 100% coverage."; \
	}

# Helper to install dependencies on Ubuntu/Debian
install-deps:
	sudo apt-get update
	sudo apt-get install -y kcov python3-docutils

# Helper to open the report
open:
	@if [ "$$(uname)" = "Darwin" ]; then \
		open $(COVERAGE_DIR)/index.html; \
	elif [ -n "$$WSL_DISTRO_NAME" ]; then \
		explorer.exe `wslpath -w $(COVERAGE_DIR)/index.html`; \
	else \
		xdg-open $(COVERAGE_DIR)/index.html; \
	fi

clean:
	rm -rf .coverage
