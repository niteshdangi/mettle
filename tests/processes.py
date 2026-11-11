"""Subprocess execution with timeout ownership of ordinary child process trees.

Like Rust's test harness, a child without an explicit timeout is never killed
for being slow; one still running after SLOW_SECONDS is reported once.
"""

import os
import signal
import subprocess
import sys

SLOW_SECONDS = 60


def kill(child):
    try:
        if os.name == "posix":
            os.killpg(child.pid, signal.SIGKILL)
        else:
            child.kill()
    except ProcessLookupError:
        pass


def run(arguments, *, timeout=None, input=None, check=False,
        capture_output=False, **options):
    if input is not None:
        if options.get("stdin") is not None:
            raise ValueError("stdin and input cannot both be supplied")
        options["stdin"] = subprocess.PIPE
    if capture_output:
        if options.get("stdout") is not None or options.get("stderr") is not None:
            raise ValueError("capture_output conflicts with stdout or stderr")
        options.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with subprocess.Popen(arguments, start_new_session=os.name == "posix",
                          **options) as child:
        try:
            if timeout is None:
                try:
                    stdout, stderr = child.communicate(input, timeout=SLOW_SECONDS)
                except subprocess.TimeoutExpired:
                    print(f"warning: {arguments!r} has been running for over "
                          f"{SLOW_SECONDS} seconds", file=sys.stderr, flush=True)
                    stdout, stderr = child.communicate()
            else:
                stdout, stderr = child.communicate(input, timeout=timeout)
        except BaseException as error:
            kill(child)
            stdout, stderr = child.communicate()
            if isinstance(error, subprocess.TimeoutExpired):
                error.output, error.stderr = stdout, stderr
            raise
        result = subprocess.CompletedProcess(arguments, child.returncode,
                                             stdout, stderr)
        if check:
            result.check_returncode()
        return result
