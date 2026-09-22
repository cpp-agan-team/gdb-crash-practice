set pagination off
set confirm off
set debuginfod enabled off
set print pretty on
break demo::ready_for_watch
run
python
assert gdb.selected_frame().name() == "demo::ready_for_watch", "did not reach initialized checkpoint"
assert int(gdb.parse_and_eval("invoice.total")) == 300
assert int(gdb.parse_and_eval("invoice.quantity")) == 3
end
print invoice
set $total_address = &invoice.total
watch -location *$total_address
continue
python
assert int(gdb.parse_and_eval("*$total_address")) == 30, "wrong total not observed"
frame = gdb.newest_frame()
names = []
while frame is not None:
    names.append(frame.name())
    frame = frame.older()
assert "demo::apply_discount" in names, names
assert "main" in names, names
assert gdb.selected_frame().name() == "demo::apply_discount"
assert int(gdb.parse_and_eval("discount")) == 30
assert int(gdb.parse_and_eval("invoice.quantity")) == 3
assert int(gdb.parse_and_eval("invoice.unit_price")) == 100
end
backtrace
info args
list
# Delete the frozen-address watchpoint before the object leaves its lifetime.
delete breakpoints
continue
python
assert int(gdb.parse_and_eval("$_exitcode")) == 1, "buggy program should report mismatch"
end
echo [PASS] 05_watchpoint\n
