.PHONY: test check

test:
	./tests/run_all.sh

check: bash-check test
