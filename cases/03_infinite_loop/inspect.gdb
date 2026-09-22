set debuginfod enabled off
set disable-randomization off
set pagination off
set confirm off
set print pretty on
set breakpoint pending off
handle SIGINT stop print nopass
break infinite_loop_ready
run
set scheduler-locking off
delete breakpoints
python
import gdb
import os
import signal
import threading

_loop_signal = None
def _loop_on_stop(event):
    global _loop_signal
    _loop_signal = getattr(event, "stop_signal", None)

def _loop_snapshot():
    frame = gdb.newest_frame()
    while frame is not None and not (frame.name() or "").startswith("process_items"):
        frame = frame.older()
    assert frame is not None, "Expected process_items on the active stack"
    frame.select()
    return (int(gdb.parse_and_eval("index")),
            int(gdb.parse_and_eval("checksum")),
            int(gdb.parse_and_eval("zero_hits")))

def _loop_interrupt_after_delay():
    pid = gdb.selected_inferior().pid
    assert pid > 0, "No live inferior"
    # Only the captured inferior PID is signalled; no GDB API in this thread.
    timer = threading.Timer(0.20, os.kill, args=(pid, signal.SIGINT))
    timer.daemon = True
    timer.start()
    return timer

gdb.events.stop.connect(_loop_on_stop)
_loop_timer = _loop_interrupt_after_delay()
end
continue
bt
python
assert _loop_signal == "SIGINT", "Expected actual SIGINT stop"
_loop_first = _loop_snapshot()
assert _loop_first[0] == 3 and _loop_first[1] == 28 and _loop_first[2] > 0, _loop_first
print("first actual interrupt: index=%d checksum=%d zero_hits=%d" % _loop_first)
_loop_signal = None
_loop_timer = _loop_interrupt_after_delay()
end
continue
bt
python
assert _loop_signal == "SIGINT", "Expected a second actual SIGINT stop"
_loop_second = _loop_snapshot()
assert _loop_second[0] == 3 and _loop_second[1] == 28, _loop_second
assert _loop_second[2] > _loop_first[2], "The loop did not execute additional iterations"
print("second actual interrupt: index=%d checksum=%d zero_hits=%d" % _loop_second)
print("Progress stayed at index 3 while zero_hits increased.")
gdb.events.stop.disconnect(_loop_on_stop)
_loop_timer.cancel()
end
kill
echo [PASS] 03_infinite_loop\n
