SHELL:=/bin/bash
.DEFAULT_GOAL=_help

.PHONY: test
test:
# 	kcov --include-path=./git-remote-gcrypt .kcov/ ./tests/system-test*.sh
# 	kcov --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
# 		coverage_dir
# 		./tests/system-test-multikey.sh
	kcov --include-path=$(pwd) --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
		.kcov ./tests/system-test.sh
	kcov --include-path=$(pwd) --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
		--merge .kcov ./tests/system-test-multikey.sh


.PHONY: clean
clean:
	rm -rf .kcov/*
