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
	echo -n '' > "$ERRFILE"
	echo -n '' > "$INFILE"
	echo -n '' > "$OUTFILE"
	echo -n '' > "$STDOUTFILE"
	# printf "%5s: %s" "[   ]" "$TEST_TEXT"
}

print_log() {
	printf "exit-status: $WSTAT\n"
	if [ -f "$INFILE" ]; then
		echo "infile: mode: $(ls -l "$INFILE" | awk '{print $1}')"
		cat "$INFILE"
	fi
	if [ -f "$OUTFILE" ]; then
		echo "outfile: mode: $(ls -l "$OUTFILE" | awk '{print $1}')"
		cat "$OUTFILE"
	fi
	echo "stderr:"
	cat "$ERRFILE"
	echo "stdout:"
	cat "$STDOUTFILE"
}

validate_test() {
	TEST_STAT="$?"
	if [ -n "$TLE" ]; then
		printf "\n%5s: %s\n" "[TLE]" "$TEST_TEXT"
		print_log
	elif [ $TEST_STAT -ne 0 ]; then
		printf "\n%5s: %s\n" "[NG]" "$TEST_TEXT"
		print_log
	else
		printf "%5s" "[OK]"
	fi
}

ERRFILE="$(mktemp)"
unlink "$ERRFILE"
INFILE="$(mktemp)"
unlink "$INFILE"
OUTFILE="$(mktemp)"
unlink "$OUTFILE"
STDOUTFILE="$(mktemp)"
unlink "$STDOUTFILE"

# Tests

test_header "mandatory: unexpected param (please check yourself)"
rm -f "$INFILE" "$OUTFILE"
nm -u pipex | 2> "$ERRFILE" > "$STDOUTFILE" grep -v \
	-e open \
	-e close \
	-e read \
	-e write \
	-e malloc \
	-e free \
	-e perror \
	-e	strerror \
	-e access \
	-e dup \
	-e dup2 \
	-e execve \
	-e exit \
	-e fork \
	-e pipe \
	-e unlink \
	-e wait \
	-e waitpid \
	-e errno \
	-e '^\n' & be_end
validate_test $(
	test $(echo "$STDOUTFILE" | wc -l) -gt 2 && exit 1
	exit 0
)

test_header "mandatory: runable no params"
rm -f "$INFILE" "$OUTFILE"
./pipex 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

test_header "mandatory: runable 1 param"
rm -f "$INFILE" "$OUTFILE"
./pipex "" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

test_header "mandatory: runable 2 param"
rm -f "$INFILE" "$OUTFILE"
./pipex "" "" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

test_header "mandatory: runable 3 param"
rm -f "$INFILE" "$OUTFILE"
./pipex "" "" "" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

echo ""
