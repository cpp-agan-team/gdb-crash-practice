set debuginfod enabled off
set disable-randomization off
set pagination off
set confirm off
set print pretty on
set breakpoint pending off
handle SIGINT stop print nopass
break deadlock_ready
run
set scheduler-locking off
delete breakpoints
python
import gdb
import os
import signal
import threading

_deadlock_stop_signal = None
def _deadlock_on_stop(event):
    global _deadlock_stop_signal
    _deadlock_stop_signal = getattr(event, "stop_signal", None)

gdb.events.stop.connect(_deadlock_on_stop)
_deadlock_pid = gdb.selected_inferior().pid
assert _deadlock_pid > 0, "No live inferior"
# No GDB API calls occur in the timer thread. Signal only this inferior.
_deadlock_timer = threading.Timer(0.25, os.kill, args=(_deadlock_pid, signal.SIGINT))
_deadlock_timer.daemon = True
_deadlock_timer.start()
end
continue
info threads
thread apply all bt
python
assert _deadlock_stop_signal == "SIGINT", "Expected an actual SIGINT stop"
assert int(gdb.parse_and_eval("worker_a.held")) == int(gdb.parse_and_eval("&left_mutex"))
assert int(gdb.parse_and_eval("worker_a.waiting_for")) == int(gdb.parse_and_eval("&right_mutex"))
assert int(gdb.parse_and_eval("worker_b.held")) == int(gdb.parse_and_eval("&right_mutex"))
assert int(gdb.parse_and_eval("worker_b.waiting_for")) == int(gdb.parse_and_eval("&left_mutex"))

_deadlock_workers = {}
for _thread in gdb.selected_inferior().threads():
    _thread.switch()
    _frame = gdb.newest_frame()
    _names = []
    _worker_frame = None
    while _frame is not None:
        _name = _frame.name() or ""
        _names.append(_name)
        if _name.startswith("deadlock_worker"):
            _worker_frame = _frame
        _frame = _frame.older()
    if _worker_frame is None:
        continue
    assert any("pthread_mutex_lock" in name or "__lll_lock_wait" in name
               or "futex_wait" in name for name in _names), (
        "Worker has not stopped in an actual mutex wait", _names)
    _worker_frame.select()
    _worker_id = int(gdb.parse_and_eval("evidence->worker_id"))
    _held = int(gdb.parse_and_eval("first"))
    _waiting = int(gdb.parse_and_eval("second"))
    _deadlock_workers[_worker_id] = (_thread.ptid[1], _held, _waiting)
    print("worker=%d GDB-thread=%d Linux-TID=%d held=%#x waiting=%#x" %
          (_worker_id, _thread.num, _thread.ptid[1], _held, _waiting))

assert set(_deadlock_workers) == {1, 2}
_a = _deadlock_workers[1]
_b = _deadlock_workers[2]
assert _a[1] == _b[2] and _b[1] == _a[2] and _a[1] != _a[2], "No two-lock cycle"

# Optional extra evidence for libstdc++ + glibc, not a portable mutex API.
try:
    _left_owner = int(gdb.parse_and_eval("left_mutex._M_mutex.__data.__owner"))
    _right_owner = int(gdb.parse_and_eval("right_mutex._M_mutex.__data.__owner"))
except gdb.error:
    print("glibc owner fields unavailable; actual wait stacks and program evidence verified.")
else:
    assert _left_owner == _a[0] and _right_owner == _b[0], "Owner/TID mismatch"
    print("glibc owners verified: left=%d right=%d" % (_left_owner, _right_owner))

gdb.events.stop.disconnect(_deadlock_on_stop)
_deadlock_timer.cancel()
end
kill
echo [PASS] 02_deadlock\n
