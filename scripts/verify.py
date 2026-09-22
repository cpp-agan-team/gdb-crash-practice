#!/usr/bin/env python3
"""Run bounded GDB checks for the six deliberately faulty teaching examples."""
from pathlib import Path
import os
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CASES = (
    '01_segfault', '02_deadlock', '03_infinite_loop',
    '04_wrong_result', '05_watchpoint', '06_exception',
)


def stop_owned_session(session_id):
    # GDB may place its inferior in a separate process group within this session.
    # Only consider members of the session created by this verifier's Popen.
    members = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            if os.getsid(pid) == session_id:
                members.append(pid)
        except (ProcessLookupError, PermissionError):
            pass
    # Stop inferiors first, then the debugger if it is still present.
    for pid in sorted(members, key=lambda value: value == session_id):
        try:
            if os.getsid(pid) == session_id:
                os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def main():
    log_dir = ROOT / 'build' / 'verification'
    log_dir.mkdir(parents=True, exist_ok=True)
    failed = []
    for case in CASES:
        command = [
            'gdb', '-q', '-nx', '-batch',
            '-x', str(ROOT / 'cases' / case / 'inspect.gdb'),
            '--args', str(ROOT / 'build' / case),
        ]
        environment = os.environ.copy()
        environment['LC_ALL'] = 'C'
        process = subprocess.Popen(
            command, cwd=ROOT, env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, start_new_session=True,
        )
        timed_out = False
        try:
            output, _ = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            timed_out = True
            # This session belongs only to this teaching GDB and its inferiors.
            stop_owned_session(process.pid)
            output, _ = process.communicate()
            output += '\n[VERIFY TIMEOUT] GDB and its own session processes were stopped.\n'
        # Clean up any descendants the completed debugger accidentally left behind.
        stop_owned_session(process.pid)
        log_path = log_dir / (case + '.txt')
        log_path.write_text(output, encoding='utf-8')
        passed = (
            not timed_out and process.returncode == 0
            and '[PASS] ' + case in output
        )
        print(('PASS ' if passed else 'FAIL ') + case, flush=True)
        if not passed:
            failed.append(case)
            print(output[-6000:], flush=True)
    print('GDB logs: ' + str(log_dir))
    if failed:
        print('Failed: ' + ', '.join(failed))
        return 1
    print('All six intended failures and diagnostic evidence were verified.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
