set pagination off
set confirm off
set debuginfod enabled off
python
observed_signals = []
def remember_signal(event):
    if isinstance(event, gdb.SignalEvent):
        observed_signals.append(event.stop_signal)
gdb.events.stop.connect(remember_signal)
end
catch throw
run
backtrace
python
frame = gdb.newest_frame()
names = []
throw_frame = None
while frame is not None:
    names.append(frame.name())
    if frame.name() == "demo::parse_worker_count":
        throw_frame = frame
    frame = frame.older()
assert throw_frame is not None, names
assert "demo::start_server" in names, names
assert "main" in names, names
throw_frame.select()
assert int(gdb.parse_and_eval("raw_count")) == -2
source = throw_frame.find_sal()
assert source.symtab is not None
assert source.symtab.filename.endswith("cases/06_exception/main.cpp"), source.symtab.filename
gdb.write("Business throw frame selected by function name; raw_count=-2\n")
end
info args
list
continue
python
assert observed_signals and observed_signals[-1] == "SIGABRT", observed_signals
frame = gdb.newest_frame()
names = []
while frame is not None:
    names.append(frame.name() or "")
    frame = frame.older()
assert any("terminate" in name for name in names), names
end
backtrace
# The cause is verified. Kill this inferior at SIGABRT rather than generate a core.
kill
python
assert gdb.selected_inferior().pid == 0, "inferior was not cleaned up"
end
echo [PASS] 06_exception\n
