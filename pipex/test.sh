#!/usr/bin/bash

# config

TIMEOUT=50 # 1/10 s
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

print_mode() {
	FILE="$1"
	test -f "$FILE" && ls -l "$FILE" | awk '{print $1}'
}

BLUE='\e[36m'
GREN='\e[32m'
REED='\e[31m'
YELO='\e[33m'
CL='\e[m'
print_log() {
	printf "exit-status: $WSTAT\n"
	if [ -f "$INFILE" ]; then
		printf "$BLUE%b$CL - %s\n" "$(print_mode "$INFILE")" "infile:"
		cat "$INFILE"
	fi
	if [ -f "$OUTFILE" ]; then
		printf "$BLUE%b$CL - %s\n" "$(print_mode "$OUTFILE")" "outfile: "
		cat "$OUTFILE"
	fi
	echo "stderr:"
	cat "$ERRFILE"
	echo "stdout:"
	cat "$STDOUTFILE"
}

TEST_COUNT=0
TEST_SUCSS=0
TEST_FAIL=0
TEST_TLE=0
validate_test() {
	TEST_STAT="$?"
	TEST_COUNT="$(expr "$TEST_COUNT" + 1)"
	if [ -n "$TLE" ]; then
		printf "\n$YELO%5s$CL: %s\n" "[TLE]" "$TEST_TEXT"
		print_log
		TEST_TLE="$(expr "$TEST_TLE" + 1)"
		return 1
	elif [ $TEST_STAT -ne 0 ]; then
		printf "\n$REED%5s$CL: %s\n" "[NG]" "$TEST_TEXT"
		print_log
		TEST_FAIL="$(expr "$TEST_FAIL" + 1)"
		return 2
	else
		printf "$GREN%5s$CL" "[OK]"
		TEST_SUCSS="$(expr "$TEST_SUCSS" + 1)"
		return 0
	fi
	return 0
}

ERRFILE="$(mktemp)"
unlink "$ERRFILE"
INFILE="$(mktemp)"
unlink "$INFILE"
INFILE="$INFILE-infile"
OUTFILE="$(mktemp)"
unlink "$OUTFILE"
OUTFILE="$OUTFILE-infile"
STDOUTFILE="$(mktemp)"
unlink "$STDOUTFILE"

printf "infile: %s\n" "$INFILE"
printf "outfile: %s\n" "$OUTFILE"

# Tests

test_header "must compile with make"
validate_test $(make) || exit 1

test_header "No such file or directory: pipex"
validate_test $(test -f ./pipex) || exit 1

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

#
# test 4 argument
#
ABS_CAT="$(which cat)"

test_header "mandatory: must be runnable for absolute path"
rm -f "$INFILE" "$OUTFILE"
echo 'Hello fork' > "$INFILE"
./pipex "$INFILE" "$ABS_CAT" "$ABS_CAT" "$OUTFILE" & be_end
validate_test $(
	test "$WSTAT" -ne 0 && exit 1
	exit 0
)

test_header "mandatory: must be (infile = outfile)"
rm -f "$INFILE" "$OUTFILE"
echo 'Hello fork' > "$INFILE"
ABS_CAT="$(which cat)"
./pipex "$INFILE" "$ABS_CAT" "$ABS_CAT" "$OUTFILE" & be_end
validate_test $(
	diff "$INFILE" "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to implement path resolution"
rm -f "$INFILE" "$OUTFILE"
echo 'Hello fork' > "$INFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" & be_end
validate_test $(
	diff "$INFILE" "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to truncate outfile"
rm -f "$INFILE" "$OUTFILE"
echo "Nick Hello" > "$OUTFILE"
echo "Fits Hello" > "$INFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" & be_end
validate_test $(
	diff "$INFILE" "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to resolve current directory before PATH"
rm -f "$INFILE" "$OUTFILE"
cp $(which yes) cat
touch "$INFILE"
./pipex "$INFILE" "./cat" "head" "$OUTFILE" & be_end
validate_test $(
	yes | head | diff /dev/fd/0 "$OUTFILE" || exit 1
	exit 0
)
unlink cat

test_header "mandatory: have to resolve parent directory before PATH"
rm -f "$INFILE" "$OUTFILE"
BIG_PARENT_YES="../../../../../../../../../../../../../../../../../../../../../../$(which yes)"
touch "$INFILE"
./pipex "$INFILE" "$BIG_PARENT_YES" "head" "$OUTFILE" & be_end
validate_test $(
	yes | head | diff /dev/fd/0 "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to be able to use option."
rm -f "$INFILE" "$OUTFILE"
echo "" > "$INFILE"
./pipex "$INFILE" "cat" "cat -e" "$OUTFILE" & be_end
validate_test $(
	grep -E '^\$$' "$OUTFILE" || exit 1
	exit 0
)

test_header "mandatory: have to exit 2 secound.(you may not use fork)(1)"
rm -f "$INFILE" "$OUTFILE"
echo "" > "$INFILE"
start=$(date +%s)
./pipex "$INFILE" "sleep 1" "sleep 2" "$OUTFILE" & be_end
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
rm -f "$INFILE" "$OUTFILE"
echo "" > "$INFILE"
start=$(date +%s)
./pipex "$INFILE" "sleep 2" "sleep 1" "$OUTFILE" & be_end
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
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "./no_file" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 127 || exit 1
	exit 0
)

test_header "mandatory: have to set exit-status 126 when found but not executable. (2)"
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "$INFILE" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 126 || exit 1
	exit 0
)

test_header "mandatory: have to set exit-status 1 when infile found but not access."
rm -f "$INFILE" "$OUTFILE"
touch "$OUTFILE"
chmod 000 "$OUTFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 1 || exit 1
	exit 0
)
chmod u+w "$OUTFILE"

test_header "mandatory: have to set exit-status 0 when succeed last command.(1)"
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "wefoij" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

test_header "mandatory: have to set exit-status 0 when succeed last command.(2)"
rm -f "$INFILE" "$OUTFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

#
# outfile permissions
#
test_header "mandatory: have to open the file after fork so exists outfile (infile-outfile)."
rm -f "$INFILE" "$OUTFILE"
./pipex "$INFILE" "wefoij" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test -f "$OUTFILE" || exit 1
	exit 0
)

umask 022
test_header "mandatory: outfile must be permission 644 when umask 022."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	print_mode "$OUTFILE" | grep '\-rw-r--r--' || exit 1
	exit 0
)
test -f "$OUTFILE" && chmod u+w "$OUTFILE"
umask 022

umask 000
test_header "mandatory: outfile must be permission 666 when umask 000."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	print_mode "$OUTFILE" | grep '\-rw-rw-rw-' || exit 1
	exit 0
)
test -f "$OUTFILE" && chmod u+w "$OUTFILE"
umask 022

umask 777
test_header "mandatory: outfile must be permission 000 when umask 777."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	print_mode "$OUTFILE" | grep '\----------' || exit 1
	exit 0
)
umask 022
test -f "$INFILE" && chmod u+w "$INFILE"
test -f "$OUTFILE" && chmod u+w "$OUTFILE"

# Error print

test_header "mandatory - sub: have to print error 'No such file or directory' when not found infile."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "./no_file" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	grep "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to print error 'command not found' when not found command (1)"
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "./no_file" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	grep "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to print error 'command not found' when not found command (2)"
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "./no_file" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	grep "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to print error 'permission denied' when not accessable infile."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
chmod 000 "$INFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "$INFILE"

test_header "mandatory - sub: have to print error 'permission denied' when not accessable command.(1)"
rm -f "$INFILE" "$OUTFILE"
cp $ABS_CAT cotable
touch "$INFILE"
chmod 000 cotable
./pipex "$INFILE" "./cotable" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "cotable" ; rm -f cotable

test_header "mandatory - sub: have to print error 'permission denied' when not accessable command.(2)"
rm -f "$INFILE" "$OUTFILE"
cp $ABS_CAT cotable
touch "$INFILE"
chmod 000 cotable
./pipex "$INFILE" "cat" "./cotable" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	grep -e "permission denied" -e "Permission denied" "$ERRFILE" || exit 1
	exit 0
)
chmod u+w "cotable" ; rm -f cotable

test_header "mandatory - sub: have to print error 'permission denied' when not accessable outfile."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
touch "$OUTFILE"
chmod 000 "$OUTFILE"
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
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
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
unset PATH
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" &
export PATH="$DUP_PATH"
be_end
validate_test $(
	grep -e "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

test_header "mandatory - sub: have to not print 'No such file or directory' when PATH length is 0."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
unset PATH
export PATH=""
./pipex "$INFILE" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" &
export PATH="$DUP_PATH"
be_end
validate_test $(
	grep -e "No such file or directory" "$ERRFILE" || exit 1
	exit 0
)

#
# bonus
#
test_header "bonus: must be able to use more command."
rm -f "$INFILE" "$OUTFILE"
touch "$INFILE"
./pipex "$INFILE" "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

#
# here doc check
#
test_header "bonus: must be able to use here_doc."
rm -f "$INFILE" "$OUTFILE"
echo -ne "test\nEOF\n" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	test "$WSTAT" -eq 0 || exit 1
	exit 0
)

test_header "bonus: must be able to be processed by DELIMINATOR\n."
rm -f "$INFILE" "$OUTFILE"
echo -ne "test\nEOF\n" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	echo -en 'test\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be able to be processed by DELIMINATOR."
rm -f "$INFILE" "$OUTFILE"
echo -en "test\nEOF" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	echo -en 'test\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be processed only when there is an exact match with DELIMINATOR. (check \"E O F\")"
rm -f "$INFILE" "$OUTFILE"
echo -ne "test\nE O F\nEOF\n" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	echo -ne 'test\nE O F\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be processed only when there is an exact match with DELIMINATOR. (check \" EOF\")"
rm -f "$INFILE" "$OUTFILE"
echo -ne "test\n EOF\nEOF\n" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	echo -ne 'test\n EOF\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be processed only when there is an exact match with DELIMINATOR. (check \"EOF \")"
rm -f "$INFILE" "$OUTFILE"
echo -ne "test\nEOF \nEOF\n" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	echo -ne 'test\nEOF \n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: must be append"
rm -f "$INFILE" "$OUTFILE"
echo "Hello" > "$OUTFILE"
echo -ne "test\nEOF\n" | ./pipex here_doc EOF "cat" "cat" "cat" "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
validate_test $(
	echo -ne 'Hello\ntest\n' | diff "/dev/fd/0" "$OUTFILE" || exit 1
	exit 0
)

test_header "bonus: you have to pipe with every fork and close pipe fds."
rm -f "$INFILE" "$OUTFILE"
NOW_ULIMIT="$(ulimit -n)"
ulimit -n 30 || (echo 'please up hardlimit for file descriptor' ; exit 1)
touch "$INFILE"
./pipex "$INFILE" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
  "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" "cat" \
    "$OUTFILE" 2> "$ERRFILE" > "$STDOUTFILE" & be_end
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
printf "Total $REED%-5s$CL  ... $TEST_FAIL\n" "NG"
printf "Total $GREN%-5s$CL  ... $TEST_SUCSS\n" "OK"

rm -f "$INFILE" "$OUTFILE"

echo ""
