set pagination off
set confirm off
set debuginfod enabled off
set print pretty on
break divide_total
break display_result
run
info args
whatis total
whatis count
print total / count
print (double)total / count
bt
python
import gdb
assert int(gdb.parse_and_eval('total')) == 47
assert int(gdb.parse_and_eval('count')) == 4
assert int(gdb.parse_and_eval('total / count')) == 11
assert float(gdb.parse_and_eval('(double)total / count')) == 11.75
assert gdb.newest_frame().name() == 'divide_total'
end
finish
continue
print actual
python
assert gdb.newest_frame().name() == 'display_result'
assert float(gdb.parse_and_eval('actual')) == 11.0
end
continue
python
assert int(gdb.parse_and_eval('$_exitcode')) == 0
end
echo [PASS] 04_wrong_result\n
quit
