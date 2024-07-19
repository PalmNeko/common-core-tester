#!/usr/bin/bash

# config
TIMEOUT=50 # 1/10 s
# for logging
TEST_TEXT=""
TLE=""
WSTAT=""
PIPEX_PID=""
IS_LEAK=""
TEST_CMD=""
# for reporting
TEST_COUNT=0
TEST_SUCSS=0
TEST_FAIL=0
TEST_TLE=0
TEST_LEAK=0
# colors
BLUE='\e[36m'
GREN='\e[32m'
REED='\e[31m'
YELO='\e[33m'
MAGE='\e[35m'
BLAK='\e[30m'
CL='\e[m'
# absolute_commands
ABS_CAT="$(which cat)"
ABS_FIND="$(which find)"
ABS_PS="$(which ps)"
ABS_GREP="$(which grep)"
ABS_TR="$(which tr)"
ABS_SLEEP="$(which sleep)"
ABS_EXPR="$(which expr)"
ABS_VALGRIND="$(which valgrind)"
ABS_CHMOD="$(which chmod)"

# files
STDINFILE="$(mktemp)"   # STDIN file
ERRFILE="$(mktemp)"     # STDERROR file
STDOUTFILE="$(mktemp)"  # STDOUT file
INFILE="$(mktemp)"      # infile file
unlink "$INFILE"
INFILE="$INFILE-infile"
OUTFILE="$(mktemp)"     # outfile file
unlink "$OUTFILE"
OUTFILE="$OUTFILE-outfile"

clean_files() {
	echo
	echo 'delete: clean tmpfiles'
	rm -f "$STDINFILE" "$ERRFILE" "$STDOUTFILE" "$INFILE" "$OUTFILE"
	clean_leak_log
}

trap clean_files 0

is_timeout() {
	PID="$1"
	ITER="$TIMEOUT"
	while [ "$ITER" -gt 0 ]; do
		"$ABS_PS" -p $PID > /dev/null || break
		"$ABS_SLEEP" 0.1
		ITER="$("$ABS_EXPR" "$ITER" - 1)"
	done
	if "$ABS_PS" -p $PID > /dev/null; then
		return 0
	else
		return 1
	fi
	return 1
}

be_end() {
	PID="$!"
	PIPEX_PID="$PID"
	WSTAT=""
	RET=""
	TLE=""
	if is_timeout "$PID"; then
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

run_test() {
	TEST_CMD="$*"
	PROG="$1"
	IS_LEAK=""
	shift
	clean_leak_log
	"$ABS_VALGRIND" \
		--log-file="tmp.memlog-%p.log" \
		--leak-check=full \
		--leak-resolution=high \
		--show-reachable=yes \
		"$PROG" "$@" < "$STDINFILE" 2> "$ERRFILE" > "$STDOUTFILE" &
	be_end
	if is_leak; then
		IS_LEAK="leaks!"
	fi
	# read
}

is_leak() {
	if cat_leak_log | "$ABS_GREP" 'LEAK' > /dev/null; then
		return 0
	else
		return 1
	fi
}

clean_leak_log() {
	"$ABS_FIND" . -type f -name "tmp.memlog-*.log" -delete
	IS_LEAK=""
}

cat_leak_log() {
	LOGS=($("$ABS_FIND" . -type f -name "tmp.memlog-*.log" | "$ABS_TR" '\n' ' '))
	"$ABS_CHMOD" u+r "${LOGS[@]}"
	"$ABS_CAT" "${LOGS[@]}"
}

test_header() {
	TEST_TEXT="$1"
	echo -n '' > "$STDINFILE"
	echo -n '' > "$ERRFILE"
	echo -n '' > "$STDOUTFILE"
	test -f "$INFILE" && chmod u+w "$INFILE"
	test -f "$OUTFILE" && chmod u+w "$OUTFILE"
	rm -f "$INFILE" "$OUTFILE"
	# printf "%5s: %s" "[   ]" "$TEST_TEXT"
}

print_mode() {
	FILE="$1"
	test -f "$FILE" && ls -l "$FILE" | awk '{print $1}'
}

print_log() {
	printf "test command: $TEST_CMD\n"
	printf "pipex pid   : $PIPEX_PID\n"
	printf "exit-status : $WSTAT\n"
	if [ -f "$INFILE" ]; then
		printf "$BLUE%b$CL - %s\n" "$(print_mode "$INFILE")" "infile: ------------------- "
		chmod u+r "$INFILE"
		cat "$INFILE"
		echo -e "$BLAK[EOF]$CL"
	fi
	if [ -f "$OUTFILE" ]; then
		printf "$BLUE%b$CL - %s\n" "$(print_mode "$OUTFILE")" "outfile: ------------------- "
		chmod u+r "$OUTFILE"
		cat "$OUTFILE"
		echo -e "$BLAK[EOF]$CL"
	fi
	echo "stdin: ------------------- "
	cat "$STDINFILE"
	echo -e "$BLAK[EOF]$CL"
	echo "stderr: ------------------- "
	cat "$ERRFILE"
	echo -e "$BLAK[EOF]$CL"
	echo "stdout: ------------------- "
	cat "$STDOUTFILE"
	echo -e "$BLAK[EOF]$CL"
}

validate_test() {
	TEST_STAT="$?"
	TEST_COUNT="$(expr "$TEST_COUNT" + 1)"
	if [ -n "$TLE" ]; then
		printf "\n$YELO%5s$CL: %s\n" "[TLE]" "$TEST_TEXT"
		print_log
		TEST_TLE="$(expr "$TEST_TLE" + 1)"
		return 1
	elif [ -n "$IS_LEAK" ]; then
		printf "\n$MAGE%5s$CL: %s\n" "[LEAK]" "$TEST_TEXT"
		print_log
		printf " ------- $MAGE%s$CL -------\n" "LEAKS"
		cat_leak_log | sed -E 's/(LEAK)/'"\\$MAGE"'\1'"\\$CL"'/g' | xargs --null printf "%b"
		TEST_LEAK="$(expr "$TEST_LEAK" + 1)"
		return 2
	elif [ $TEST_STAT -ne 0 ]; then
		printf "\n$REED%5s$CL: %s\n" "[NG]" "$TEST_TEXT"
		print_log
		TEST_FAIL="$(expr "$TEST_FAIL" + 1)"
		return 3
	else
		printf "$GREN%5s$CL" "[OK]"
		TEST_SUCSS="$(expr "$TEST_SUCSS" + 1)"
		return 0
	fi
	return 0
}

printf "infile: %s\n" "$INFILE"
printf "outfile: %s\n" "$OUTFILE"

# Tests

test_header "must compile with make"
validate_test $(make) || exit 1

test_header "No such file or directory: pipex"
validate_test $(test -f ./pipex) || exit 1

test_header "mandatory: unexpected param (please check yourself)"
nm -u pipex | 2> "$ERRFILE" > "$STDOUTFILE" grep -v \
	-e open \
	-e close \
	-e read \
	-e write \
	-e malloc \
	-e free \
	-e perror \
	-e strerror \
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
run_test ./pipex
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

test_header "mandatory: runable 1 param"
run_test ./pipex ""
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

test_header "mandatory: runable 2 param"
run_test ./pipex "" ""
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

test_header "mandatory: runable 3 param"
run_test ./pipex "" "" ""
validate_test $(
	test "$WSTAT" -gt 128 && exit 1
	grep "coredump" "$ERRFILE" && exit 1
	exit 0
)

#
# test 4 argument
#
test_header "mandatory: must be runnable for absolute path"
echo 'Hello fork' > "$INFILE"
run_test ./pipex "$INFILE" "$ABS_CAT" "$ABS_CAT" "$OUTFILE"
validate_test $(
	test "$WSTAT" -ne 0 && exit 1
	exit 0
)

test_header "mandatory: must be (infile = outfile)"
echo 'Hello fork' > "$INFILE"
ABS_CAT="$(which cat)"
run_test ./pipex "$INFILE" "$ABS_CAT" "$ABS_CAT" "$OUTFILE"
validate_test $(
	diff "$INFILE" "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to implement path resolution"
echo 'Hello fork' > "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	diff "$INFILE" "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to truncate outfile"
echo "Nick Hello" > "$OUTFILE"
echo "Fits Hello" > "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	diff "$INFILE" "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to resolve current directory before PATH"
cp $(which yes) cat
touch "$INFILE"
run_test ./pipex "$INFILE" "./cat" "head" "$OUTFILE"
validate_test $(
	yes | head | diff /dev/fd/0 "$OUTFILE" || exit 1
	exit 0
)
unlink cat

test_header "mandatory: have to resolve parent directory before PATH"
BIG_PARENT_YES="../../../../../../../../../../../../../../../../../../../../../../$(which yes)"
touch "$INFILE"
run_test ./pipex "$INFILE" "$BIG_PARENT_YES" "head" "$OUTFILE"
validate_test $(
	yes | head | diff /dev/fd/0 "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to be able to use option."
echo "" > "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat -e" "$OUTFILE"
validate_test $(
	grep -E '^\$$' "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to exit 2 secound.(you may not use fork)(1)"
echo "" > "$INFILE"
start=$(date +%s)
run_test ./pipex "$INFILE" "sleep 1" "sleep 2" "$OUTFILE"
end=$(date +%s)
validate_test $(
	if [ "$(expr $end - $start)" -eq 2 ]; then
		exit 0
	else
		exit 1
	fi
	exit 0
)

test_header "mandatory: have to exit 2 secound.(you may not use fork)(2)"
echo "" > "$INFILE"
start=$(date +%s)
run_test ./pipex "$INFILE" "sleep 2" "sleep 1" "$OUTFILE"
end=$(date +%s)
validate_test $(
	if [ "$(expr $end - $start)" -eq 2 ]; then
		exit 0
	else
		exit 1
	fi
	exit 0
)

#
# exit statuses
#
test_header "mandatory: have to set exit-status 127 when 'No such file or directory'(1)"
touch "$INFILE"
run_test ./pipex "$INFILE" "cat" "./no_file" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 127 || exit 1
	exit 0
)

test_header "mandatory: have to set exit-status 126 when found but not executable. (2)"
touch "$INFILE"
run_test ./pipex "$INFILE" "cat" "$INFILE" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 126 || exit 1
	exit 0
)

test_header "mandatory: have to set exit-status 1 when infile found but not access."
touch "$OUTFILE"
chmod 000 "$OUTFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 1 || exit 1
	exit 0
)
chmod u+w "$OUTFILE"

test_header "mandatory: have to set exit-status 0 when succeed last command.(1)"
touch "$INFILE"
run_test ./pipex "$INFILE" "wefoij" "cat" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

test_header "mandatory: have to set exit-status 0 when succeed last command.(2)"
rm -f "$INFILE" "$OUTFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

#
# outfile permissions
#
test_header "mandatory: have to open the file after fork so exists outfile (infile-outfile)."
run_test ./pipex "$INFILE" "wefoij" "cat" "$OUTFILE"
validate_test $(
	test -f "$OUTFILE" || exit 1
	exit 0
)

umask 022
test_header "mandatory: outfile must be permission 644 when umask 022."touch "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	print_mode "$OUTFILE" | grep '\-rw-r--r--' || exit 1
	exit 0
)
test -f "$OUTFILE" && chmod u+w "$OUTFILE"
umask 022

umask 000
test_header "mandatory: outfile must be permission 666 when umask 000."
touch "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	print_mode "$OUTFILE" | grep '\-rw-rw-rw-' || exit 1
	exit 0
)
test -f "$OUTFILE" && chmod u+w "$OUTFILE"
umask 022

# Error print

test_header "mandatory - sub: have to print error 'No such file or directory' when not found infile."
touch "$INFILE"
run_test ./pipex "./no_file" "cat" "cat" "$OUTFILE"
validate_test $(
	grep "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to print error 'command not found' when not found command (1)"
touch "$INFILE"
run_test ./pipex "$INFILE" "./no_file" "cat" "$OUTFILE"
validate_test $(
	grep "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to print error 'command not found' when not found command (2)"
touch "$INFILE"
run_test ./pipex "$INFILE" "cat" "./no_file" "$OUTFILE"
validate_test $(
	grep "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to print error 'permission denied' when not accessable infile."
touch "$INFILE"
chmod 000 "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "$INFILE"

test_header "mandatory - sub: have to print error 'permission denied' when not accessable command.(1)"
cp $ABS_CAT cotable
touch "$INFILE"
chmod 000 cotable
run_test ./pipex "$INFILE" "./cotable" "cat" "$OUTFILE"
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "cotable" ; rm -f cotable

test_header "mandatory - sub: have to print error 'permission denied' when not accessable command.(2)"
cp $ABS_CAT cotable
touch "$INFILE"
chmod 000 cotable
run_test ./pipex "$INFILE" "cat" "./cotable" "$OUTFILE"
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "cotable" ; rm -f cotable

test_header "mandatory - sub: have to print error 'permission denied' when not accessable outfile."
touch "$INFILE"
touch "$OUTFILE"
chmod 000 "$OUTFILE"
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "$OUTFILE"

#
# PATH tests
#
DUP_PATH="$PATH"
test_header "mandatory - sub: have to not print 'No such file or directory' when unsetted PATH"
touch "$INFILE"
unset PATH
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
export PATH="$DUP_PATH"
validate_test $(
	grep -e "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to not print 'No such file or directory' when PATH length is 0."
touch "$INFILE"
unset PATH
export PATH=""
run_test ./pipex "$INFILE" "cat" "cat" "$OUTFILE"
export PATH="$DUP_PATH"
validate_test $(
	grep -e "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

#
# bonus
#
test_header "bonus: must be able to use more command."
touch "$INFILE"
run_test ./pipex "$INFILE" "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

#
# here doc check
#
test_header "bonus: must be able to use here_doc."
echo -ne "test\nEOF\n" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

test_header "bonus: must be able to be processed by DELIMINATOR\n."
echo -ne "test\nEOF\n" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	echo -en 'test\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be able to be processed by DELIMINATOR."
echo -ne "test\nEOF" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	echo -en 'test\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be processed only when there is an exact match with DELIMINATOR. (check \"E O F\")"
echo -ne "test\nE O F\nEOF\n" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	echo -ne 'test\nE O F\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be processed only when there is an exact match with DELIMINATOR. (check \" EOF\")"
echo -ne "test\n EOF\nEOF\n" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	echo -ne 'test\n EOF\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be processed only when there is an exact match with DELIMINATOR. (check \"EOF \")"
echo -ne "test\nEOF \nEOF\n" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	echo -ne 'test\nEOF \n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be append"
echo "Hello" > "$OUTFILE"
echo -ne "test\nEOF\n" > "$STDINFILE"
run_test ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE"
validate_test $(
	echo -ne 'Hello\ntest\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: you have to pipe with every fork and close pipe fds."
NOW_ULIMIT="$(ulimit -n)"
ulimit -n 30 || (echo 'please up hardlimit for file descriptor' ; exit 1)
touch "$INFILE"
run_test ./pipex "$INFILE" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat"
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)
# ulimit -n "$NOW_ULIMIT" # not permitted.

echo
printf "repoting.\r"
sleep 0.8
printf "repoting..\r"
sleep 0.9
echo "repoting..."
sleep 1
echo
printf "TOTAL %-5s  ... $TEST_COUNT\n" "TEST"
printf "Total $YELO%-5s$CL  ... $TEST_TLE\n" "TLE"
printf "Total $MAGE%-5s$CL  ... $TEST_LEAK\n" "LEAK"
printf "Total $REED%-5s$CL  ... $TEST_FAIL\n" "NG"
printf "Total $GREN%-5s$CL  ... $TEST_SUCSS\n" "OK"

echo ""
