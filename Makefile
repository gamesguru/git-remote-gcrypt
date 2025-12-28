.ONESHELL:
SHELL:=/bin/bash
.DEFAULT_GOAL := _help

# -- Config --
PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_SYSTEM  := $(COV_ROOT)/system
COV_INSTALL := $(COV_ROOT)/installer

.PHONY: _help
_help:
	@printf "\nUsage: make <command>, valid commands:\n\n"
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'



.PHONY: cov/inst
cov/inst: check-deps	##H Coverage run for installer logic
	@echo "🚀 [Installer] Preparing coverage..."
	@rm -rf $(COV_INSTALL)
	@mkdir -p $(COV_INSTALL)
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=$(PWD)/.git,$(PWD)/tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh
	@echo "✅ [Installer] Done. Report: file://$(COV_INSTALL)/index.html"


.PHONY: cov/sys
cov/sys: check-deps	##H Run all system tests (Standard, Multi-key, Failures)
	@echo "🚀 [System] Preparing coverage..."
	@rm -rf $(COV_SYSTEM)
	@mkdir -p $(COV_SYSTEM)

	@export GPG_TTY=$$(tty); \
	 export GIT_CONFIG_PARAMETERS="'gcrypt.gpg-args=--pinentry-mode loopback --no-tty'"; \
	 for test_script in tests/system-test*.sh; do \
	     echo "🧪 Running $$test_script..."; \
	     kcov --include-path=$(PWD) \
	          --include-pattern=git-remote-gcrypt \
	          --exclude-path=$(PWD)/.git,$(PWD)/tests \
	          $(COV_SYSTEM) \
	          ./$$test_script || echo "⚠️  $$test_script returned error (likely expected)"; \
	 done

	@echo "✅ [System] Done. Report: file://$(COV_SYSTEM)/index.html"
	@echo "👉 Run 'make missed' to see which lines are not covered."


.PHONY: cov/missed
cov/missed:	##H Show missing lines for all coverage reports
	@echo "🔍 Scanning for uncovered lines..."
	for DIR in $(COV_SYSTEM) $(COV_INSTALL); do \
		[ ! -d "$$DIR" ] && continue; \
		[[ "$$DIR" == *"installer"* ]] && PATT="install.sh" || PATT="git-remote-gcrypt"; \
		XML=$$(find $$DIR -name "cobertura.xml" | grep "merged" | head -n 1); \
		[ -z "$$XML" ] && XML=$$(find $$DIR -name "cobertura.xml" | head -n 1); \
		if [ -f "$$XML" ]; then \
			REPORT_DIR=$$(dirname "$$XML"); \
			printf "\n🔍 Analyzing $$PATT in $$DIR...\n"; \
			printf "🌐 Report: file://$$REPORT_DIR/index.html\n"; \
			python3 -c "import xml.etree.ElementTree as E, textwrap; m = [l.get('number') for c in E.parse('$$XML').findall('.//class') if '$$PATT' in c.get('filename') for l in c.findall('.//line') if l.get('hits') == '0']; print(f'❌ \033[1m{len(m)} MISSING LINES\033[0m in $$PATT:'); print(textwrap.fill(', '.join(m), width=72, initial_indent='  ', subsequent_indent='  ')) if m else None"; \
		fi; \
	done



.PHONY: install
install:	##H Install the tool
	./install.sh


.PHONY: inst/pretest
inst/pretest:	##H Run installer logic tests
	bash ./tests/test-install-logic.sh


.PHONY: inst/verify
inst/verify:	##H Verify install and version
	bash ./tests/verify-system-install.sh


.PHONY: check-deps
check-deps:	##H Check for kcov
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }
	@echo "OK."


.PHONY: clean
clean:	##H Clean artifacts
	rm -rf .coverage
