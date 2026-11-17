#!/usr/bin/env python3
"""Retain the original Simulator gesture-service stream around two diagnostic tests.

This is diagnostic evidence, never full functional or release acceptance.
The existing run_native.py owns the 600-second native budget and case outcomes;
this wrapper owns only bounded provenance capture and its own log-stream group.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


PREDICATE = ('process == "LaGrilla" OR process == "druid" OR '
             'process == "SpringBoard" OR process == "backboardd" OR '
             'subsystem CONTAINS[c] "DragUI" OR subsystem CONTAINS[c] "DragDrop"')


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def stop_owned(process, grace_periods=(3, 2, 2)):
    """Bound cleanup of this wrapper's separately owned child process group."""
    if process is None:
        return None
    for number, grace in zip((signal.SIGINT, signal.SIGTERM, signal.SIGKILL), grace_periods):
        if process.poll() is not None:
            break
        try:
            os.killpg(process.pid, number)
        except ProcessLookupError:
            break
        try:
            return process.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            pass
    return process.poll()


def capture(arguments):
    folder = Path(arguments.output_dir)
    folder.mkdir(parents=True, exist_ok=True)
    receipt_path = folder / "capture-status.json"
    state = dict(schemaVersion=1, diagnosticOnly=True, scope="input-diagnostic",
                 acceptance="not-full-functional-or-release-acceptance", status="starting",
                 repository=os.environ.get("GITHUB_REPOSITORY"), sourceSHA=os.environ.get("GITHUB_SHA"),
                 runID=os.environ.get("GITHUB_RUN_ID"), runAttempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                 deviceID=arguments.device, startedAtUTC=utc_now(),
                 hostWallClockNanoseconds=time.time_ns(), hostMonotonicNanoseconds=time.monotonic_ns(),
                 predicate=PREDICATE, logLevel="info", provenanceCommands=[],
                 nativeWrapperExitCode=None, wrapperTimedOut=False, receivedSignal=None)

    def persist():
        temporary = receipt_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
        temporary.replace(receipt_path)

    def provenance(name, command):
        result = dict(name=name, command=command, startedAtUTC=utc_now())
        raw = b""
        try:
            completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
            raw, result["exitCode"] = completed.stdout, completed.returncode
        except subprocess.TimeoutExpired as error:
            raw = error.stdout or b""
            result.update(exitCode=124, timedOut=True)
        except OSError as error:
            result.update(exitCode=127, errorType=type(error).__name__)
        path = folder / name
        path.write_bytes(raw)
        result.update(endedAtUTC=utc_now(), byteCount=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        state["provenanceCommands"].append(result)
        persist()

    received_signal = None
    previous_handlers = {}

    def receive(number, _frame):
        nonlocal received_signal
        if received_signal is None:
            received_signal = number

    stream = native = None
    stream_path = folder / "simulator-gesture-services.log"
    stream_output = None
    exit_code = 127
    persist()
    try:
        for number in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[number] = signal.signal(number, receive)
        for name, command in (
            ("devices-before-test.json", ["xcrun", "simctl", "list", "devices", "--json"]),
            ("runtimes-before-test.json", ["xcrun", "simctl", "list", "runtimes", "--json"]),
        ):
            if received_signal is not None:
                break
            provenance(name, command)
        if received_signal is not None:
            exit_code = 128 + received_signal
            return exit_code
        stream_output = stream_path.open("wb", buffering=0)
        stream_command = ["xcrun", "simctl", "spawn", arguments.device, "log", "stream",
                          "--style", "compact", "--level", "info", "--predicate", PREDICATE]
        state.update(streamCommand=stream_command, streamStartedAtUTC=utc_now())
        try:
            stream = subprocess.Popen(stream_command, stdout=stream_output, stderr=subprocess.STDOUT, start_new_session=True)
            state["streamPID"] = stream.pid
        except OSError as error:
            state["streamStartErrorType"] = type(error).__name__
        persist()
        native = subprocess.Popen(arguments.command, start_new_session=True)
        state.update(status="running", nativeWrapperPID=native.pid, nativeStartedAtUTC=utc_now())
        persist()
        # Secondary boundary only: run_native retains its original 600-second
        # limit plus its original bounded partial-xcresult cleanup.
        deadline = time.monotonic() + 650
        while native.poll() is None:
            if received_signal is not None or time.monotonic() >= deadline:
                state["wrapperTimedOut"] = received_signal is None
                # Let run_native finish its existing 20s/10s cleanup and
                # signal its own separately owned xcodebuild group first.
                stop_owned(native, (40, 10, 2))
                break
            time.sleep(0.1)
        code = native.poll()
        state["nativeWrapperExitCode"] = code
        state["streamEndedBeforeNativeCompletion"] = stream is None or stream.poll() is not None
        exit_code = (128 + received_signal if received_signal is not None else
                     124 if state["wrapperTimedOut"] else
                     127 if code is None else 128 - code if code < 0 else code)
        # A missing/failed stream must remain a visible diagnostic failure even
        # if both tests happened to pass. Original native status stays separate.
        if exit_code == 0 and state["streamEndedBeforeNativeCompletion"]:
            exit_code = 1
        return exit_code
    except OSError as error:
        state["errorType"] = type(error).__name__
        return exit_code
    finally:
        for number in previous_handlers:
            signal.signal(number, signal.SIG_IGN)
        stop_owned(native, (40, 10, 2))
        state["streamExitCode"] = stop_owned(stream)
        if stream_output is not None:
            stream_output.close()
        if stream_path.exists():
            raw = stream_path.read_bytes()
            state.update(streamByteCount=len(raw), streamSHA256=hashlib.sha256(raw).hexdigest())
        state.update(status="completed", receivedSignal=received_signal,
                     endedAtUTC=utc_now(), exitCode=exit_code)
        persist()
        for number, handler in previous_handlers.items():
            signal.signal(number, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output-dir", default="GestureDiagnostics")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if arguments.command[:1] == ["--"]:
        arguments.command.pop(0)
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", arguments.device) or not arguments.command:
        parser.error("an actual Simulator UUID and command after -- are required")
    return capture(arguments)


if __name__ == "__main__":
    sys.exit(main())
