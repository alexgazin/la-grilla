#!/usr/bin/env python3
"""Bound a real native command and retain its original output and exit status.

The child owns a fresh process group. A timeout interrupts that entire group,
then escalates to TERM/KILL so CI can upload a partial result before job expiry.
Optional required test IDs reject an empty/mistyped focused selection; original
individual XCTest outcomes and subprocess exit codes remain in the receipt.
"""
import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time
import traceback
from native_scope import functional_inventory, observed_outcomes


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def positive_number(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be finite and greater than zero")
    return number


class ConsoleMirror:
    """Console backpressure must never stop supervision or the original log.

    The complete bytes always go to the artifact log. Console output is a
    best-effort mirror: an unread CI pipe can accept only part of a write.
    Account for every omitted console byte explicitly in the process receipt.
    """
    def __init__(self, state):
        self.state, self.fd, self.original_blocking = state, None, None
        state.update(consoleMirroringMode="disabled", consoleBytesWritten=0, consoleBytesDropped=0)
        try:
            self.fd = sys.stdout.fileno()
            self.original_blocking = os.get_blocking(self.fd)
            os.set_blocking(self.fd, False)
            state["consoleMirroringMode"] = "nonblocking-best-effort"
        except (OSError, ValueError):
            self.fd = None

    def __enter__(self):
        return self

    def write(self, payload):
        written = 0
        if self.fd is not None:
            try:
                written = os.write(self.fd, payload)
            except OSError:
                pass  # The authoritative original file is still retained.
        self.state["consoleBytesWritten"] += written
        self.state["consoleBytesDropped"] += len(payload) - written

    def __exit__(self, *_):
        if self.fd is not None and self.original_blocking is not None:
            try:
                os.set_blocking(self.fd, self.original_blocking)
            except OSError:
                pass


def run(arguments):
    log_path, status_path = Path(arguments.log), Path(arguments.status)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    status_path.parent.mkdir(parents=True, exist_ok=True)
    began = time.monotonic()
    effective_limit = arguments.timeout_seconds
    if arguments.deadline_env:
        try:
            deadline = float(os.environ[arguments.deadline_env])
            if not math.isfinite(deadline):
                raise ValueError()
        except (KeyError, ValueError):
            raise ValueError("The configured evidence-preservation deadline is absent or invalid.") from None
        effective_limit = min(effective_limit, deadline - time.time())
    state = {
        "schemaVersion": 1, "label": arguments.label,
        "executable": Path(arguments.command[0]).name,
        "argumentCount": len(arguments.command) - 1,
        "startedAtUTC": utc_now(), "status": "starting",
        "timeoutSeconds": arguments.timeout_seconds,
        "effectiveTimeoutSeconds": max(0, effective_limit),
        "timedOut": False, "receivedSignal": None,
        "terminationPhase": None, "descendantCleanupRequired": False,
        "subprocessExitCode": None, "exitCode": None,
        "repository": os.environ.get("GITHUB_REPOSITORY"), "sourceSHA": os.environ.get("GITHUB_SHA"),
        "runID": os.environ.get("GITHUB_RUN_ID"), "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "scope": arguments.scope, "scopeStatus": "not-accepted", "functionalInventoryVerified": False,
        "expectedFunctionalTests": functional_inventory(arguments.functional_inventory) if arguments.functional_inventory else [],
    }

    def persist():
        state["elapsedSeconds"] = time.monotonic() - began
        temporary = status_path.with_name(status_path.name + ".tmp")
        temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
        temporary.replace(status_path)

    persist()
    process = None
    received_signal = None
    previous_handlers = {}

    def receive(number, _frame):
        nonlocal received_signal
        if received_signal is None:
            received_signal = number

    def signal_group(number):
        if process is not None:
            try:
                os.killpg(process.pid, number)
            except ProcessLookupError:
                pass

    with ConsoleMirror(state) as console, log_path.open("wb") as log:
        def diagnostic(message):
            payload = (message + "\n").encode("utf-8")
            log.write(payload)
            log.flush()
            console.write(payload)

        if effective_limit <= 0:
            state.update(timedOut=True, status="completed", terminationPhase="deadline-before-start", exitCode=124, endedAtUTC=utc_now())
            diagnostic("Native command was not started: evidence-preservation deadline expired.")
            persist()
            return 124
        try:
            for number in (signal.SIGINT, signal.SIGTERM):
                previous_handlers[number] = signal.signal(number, receive)
            process = subprocess.Popen(arguments.command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
            state.update(status="running", subprocessPID=process.pid, processGroupID=process.pid)
            persist()
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            pipe_open = True
            phase = None
            next_signal = None
            hard_close = None
            parent_ended = None
            while True:
                now = time.monotonic()
                code = process.poll()
                if code is not None and parent_ended is None:
                    parent_ended = now
                if code is not None and not pipe_open:
                    break
                if phase is None and (received_signal is not None or now - began >= effective_limit):
                    state["timedOut"] = received_signal is None
                    state["receivedSignal"] = received_signal
                    phase = "interrupt" if received_signal is None else "external-signal"
                    signal_group(signal.SIGINT if received_signal is None else received_signal)
                    next_signal = now + arguments.interrupt_grace_seconds
                    state["terminationPhase"] = phase
                    diagnostic("Native command termination started: " + phase + "; preserving partial evidence.")
                    persist()
                elif phase is None and parent_ended is not None and now - parent_ended >= 0.5:
                    # A child that inherited stdout must not keep a completed
                    # command hanging until the overall deadline.
                    state["descendantCleanupRequired"] = True
                    phase = "terminate"
                    signal_group(signal.SIGTERM)
                    next_signal = now + arguments.terminate_grace_seconds
                    state["terminationPhase"] = phase
                    persist()
                elif next_signal is not None and now >= next_signal:
                    if phase in ("interrupt", "external-signal"):
                        phase = "terminate"
                        signal_group(signal.SIGTERM)
                        next_signal = now + arguments.terminate_grace_seconds
                    else:
                        phase = "kill"
                        signal_group(signal.SIGKILL)
                        next_signal = None
                        hard_close = now + 1
                    state["terminationPhase"] = phase
                    persist()
                if hard_close is not None and now >= hard_close:
                    break
                for key, _ in selector.select(timeout=0.1):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if chunk:
                        log.write(chunk)
                        log.flush()
                        console.write(chunk)
                    else:
                        selector.unregister(key.fileobj)
                        pipe_open = False
            selector.close()
            signal_group(signal.SIGKILL)
            code = process.wait(timeout=5)
            exit_code = 124 if state["timedOut"] else (128 + received_signal if received_signal is not None else (128 - code if code < 0 else code))
            required = set(arguments.require_test) | set(state["expectedFunctionalTests"])
            if required:
                outcomes = observed_outcomes(log_path.read_text(errors="replace"))
                required_outcomes = {identifier: outcomes.get(identifier, "not-observed") for identifier in sorted(required)}
                state["requiredTestOutcomes"] = required_outcomes
                if exit_code == 0 and any(outcome != "passed" for outcome in required_outcomes.values()):
                    exit_code = 1
                    diagnostic("Focused native selection did not pass every required test; original process exit retained.")
            if exit_code == 0 and state["expectedFunctionalTests"] and arguments.scope in ("full", "ui-only"):
                state.update(functionalInventoryVerified=True, scopeStatus="full-functional-pass")
            elif exit_code == 0 and required:
                state["scopeStatus"] = "focused-pass"
            state.update(status="completed", receivedSignal=received_signal, subprocessExitCode=code, exitCode=exit_code, endedAtUTC=utc_now())
            persist()
            return exit_code
        except OSError as error:
            # The command can contain paths; expose the error class without
            # echoing credentials or arbitrary OS exception text into receipts.
            diagnostic("Native subprocess failed: " + type(error).__name__ + " (errno=" + str(error.errno) + ")")
            frames = [{"function": frame.name, "line": frame.lineno}
                      for frame in traceback.extract_tb(error.__traceback__)[-4:]]
            state.update(status="completed", errorType=type(error).__name__, errorErrno=error.errno,
                         errorOperation="start-subprocess" if process is None else "supervise-subprocess",
                         errorFrames=frames, exitCode=127, endedAtUTC=utc_now())
            persist()
            return 127
        finally:
            signal_group(signal.SIGKILL)
            if process is not None:
                process.stdout.close()
                process.wait(timeout=5)
            for number, handler in previous_handlers.items():
                signal.signal(number, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=positive_number, required=True)
    parser.add_argument("--deadline-env", help="Optional epoch-seconds environment variable reserving time for evidence upload")
    parser.add_argument("--interrupt-grace-seconds", type=positive_number, default=20)
    parser.add_argument("--terminate-grace-seconds", type=positive_number, default=10)
    parser.add_argument("--log", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--label", default="native-tests")
    parser.add_argument("--require-test", action="append", default=[], help="Required actual XCTest Class/method PASS; rejects zero-test focused success")
    parser.add_argument("--scope", choices=("full", "ui-only", "integration-only", "input-diagnostic", "ru-capture", "focused"), default="focused")
    parser.add_argument("--functional-inventory", type=Path, help="Require every functional XCTest declared by this source directory")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if arguments.command[:1] == ["--"]:
        arguments.command.pop(0)
    if not arguments.command:
        parser.error("a real subprocess command is required after --")
    if Path(arguments.log).resolve() == Path(arguments.status).resolve():
        parser.error("log and status must be different files")
    if arguments.scope in ("full", "ui-only") and not arguments.functional_inventory:
        parser.error("full scope requires an actual functional source inventory")
    try:
        return run(arguments)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
