#!/usr/bin/bash

# config

TIMEOUT=30 # 1/10 s
TLE=""
WSTAT=""
be_end() {
	TLE=false
	PID="$!"
	WSTAT=""
	RET=""
	TLE=""
	ITER="$TIMEOUT"
	while [ "$ITER" -gt 0 ]; do
		ps -p $PID > /dev/null || break
		sleep 0.1
		ITER="$(expr "$ITER" - 1)"
	done
	if ps -p $PID > /dev/null; then
		kill $PID
		TLE="TLE"
		RET=1
	else
		RET=0
	fi
	wait $PID
	WSTAT="$?"
	return $RET
}

TEST_TEXT=""
test_header() {
	TEST_TEXT="$1"
	# printf "%5s: %s" "[   ]" "$TEST_TEXT"
}

validate_test() {
	TEST_STAT="$?"
	if [ -n "$TLE" ]; then
		printf "\n%5s: %s\n" "[TLE]" "$TEST_TEXT"
	elif [ $TEST_STAT -ne 0 ]; then
		printf "\n%5s: %s\n" "[NG]" "$TEST_TEXT"
	else
		printf "%5s" "[OK]"
	fi
}

ERRFILE="$(mktemp)"
unlink "$ERRFILE"
INFILE="$(mktemp)"
unlink "$INFILE"
INFILE="$(mktemp)"
unlink "$INFILE"

# Tests

test_header "sample test"
sleep 1 \
2> "$ERRFILE" & be_end
validate_test $(
	true
)

echo ""
