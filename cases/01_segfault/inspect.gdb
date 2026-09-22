set pagination off
set confirm off
set debuginfod enabled off
set print pretty on
break calculate_total
run
info args
print order
bt
python
import gdb
assert int(gdb.parse_and_eval('order')) == 0, 'expected nullptr at function entry'
names = []
frame = gdb.newest_frame()
while frame:
    names.append(frame.name())
    frame = frame.older()
assert names[:3] == ['calculate_total', 'process_request', 'main'], names
end
continue
bt
print order
python
assert int(gdb.parse_and_eval('$_siginfo.si_signo')) == 11, 'expected SIGSEGV on Linux'
assert gdb.newest_frame().name() == 'calculate_total'
assert int(gdb.parse_and_eval('order')) == 0
end
echo [PASS] 01_segfault\n
quit
