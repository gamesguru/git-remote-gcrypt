SHELL:=/bin/bash
.DEFAULT_GOAL := _help

# NOTE: must put a <TAB> character and two pound with an "H",
#       i.e., "\t##H" to show up in this list.  Keep it brief! IGNORE_ME
.PHONY: _help
_help:
	@printf "\nUsage: make <command>, valid commands:\n\n"
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'


# Absolute path needed for kcov
PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_INSTALL := $(COV_ROOT)/installer
COV_SYSTEM  := $(COV_ROOT)/system

.PHONY: cov
cov: cov-inst cov-sys	##H Run full coverage suite
	@echo "📊 Full coverage suite complete."
	@echo "   Installer: file://$(COV_INSTALL)/index.html"
	@echo "   System:    file://$(COV_SYSTEM)/index.html"

.PHONY: cov-inst
cov-inst: check-deps	##H Run installer logic tests
	@echo "🚀 [Installer] Preparing coverage..."
	@mkdir -p $(COV_INSTALL)
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=.git,tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh
	@echo "✅ [Installer] Done."

.PHONY: cov-sys
cov-sys: check-deps    ##H Run multikey system test (Patched for kcov safety)
	@echo "🚀 [System] Preparing coverage..."
	@mkdir -p $(COV_SYSTEM)

	@echo "🔧 Patching system-test-multikey.sh..."
	@cp ./tests/system-test-multikey.sh ./tests/tmp_multi.sh
	@chmod +x ./tests/tmp_multi.sh

	@# Inject anti-hang GPG config using '#' as delimiter to handle pipes correctly
	@sed -i 's#chmod 700 "$$GNUPGHOME"#chmod 700 "$$GNUPGHOME"; echo "no-tty" >> "$$GNUPGHOME/gpg.conf"; echo "pinentry-mode loopback" >> "$$GNUPGHOME/gpg.conf"; echo "allow-loopback-pinentry" >> "$$GNUPGHOME/gpg-agent.conf"; gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true;#' ./tests/tmp_multi.sh

	@echo "🧪 Running kcov on multikey test..."
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=git-remote-gcrypt \
	     --exclude-path=.git,tests \
	     $(COV_SYSTEM) \
	     ./tests/tmp_multi.sh

	@rm -f ./tests/tmp_multi.sh
	@echo "✅ [System] Done."

.PHONY: check-deps
check-deps:	##H Check for kcov/rst2man
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }
	@command -v rst2man >/dev/null 2>&1 || command -v rst2man.py >/dev/null 2>&1 || { \
		echo "⚠️  Warning: 'rst2man' is missing (install python3-docutils)."; \
	}

.PHONY: clean
clean:	##H Clean artifacts
	rm -rf .coverage
