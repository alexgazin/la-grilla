#!/usr/bin/env python3
"""Bounded Simulator-only DragUI readiness experiment; never app acceptance.

Discover the actual selected runtime's definitions first. Only the explicit
flag permits a normal public simctl launch of a uniquely verified Druid system
app. Daemon-only/ambiguous definitions fail closed; launchctl is read-only.
No application touch, test retry, host service mutation or TCC change occurs.
"""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time


MACH_SERVICE = "com.apple.DragUI.druid.source"
LISTENER = re.compile(r"\bdruid\[(\d+):[^\]]+\].*\[com\.apple\.DragUI:Dragging\] Listening for source and destination connections\.")
BUNDLE_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{1,254}")


class NotReady(RuntimeError):
    pass


def now():
    return datetime.now(timezone.utc).isoformat()


def contained(path, root):
    resolved = path.resolve(strict=True)
    if not resolved.is_relative_to(root):
        raise NotReady("A discovered path escapes the selected Simulator runtime.")
    return resolved


def definition_contains_service(value):
    if isinstance(value, dict):
        return MACH_SERVICE in value or any(definition_contains_service(v) for v in value.values())
    if isinstance(value, list):
        return any(definition_contains_service(v) for v in value)
    return value == MACH_SERVICE


def discover(root, deadline):
    """Read bounded, real runtime files; no label or bundle ID is guessed."""
    apps, definitions, visited = [], [], set()
    locations = ["Applications", "System/Applications", "System/Library/CoreServices", "System/Library/PrivateFrameworks/DragUI.framework",
                 "System/Library/LaunchDaemons", "System/Library/LaunchAgents", "System/Library/XPCServices"]
    for relative in locations:
        directory = root / relative
        if not directory.is_dir():
            continue
        for candidate in directory.rglob("*.plist"):
            if time.monotonic() >= deadline:
                raise NotReady("The 30-second readiness deadline expired during discovery.")
            path = contained(candidate, root)
            if path in visited:
                continue
            visited.add(path)
            if len(visited) > 4096 or path.stat().st_size > 4_000_000:
                raise NotReady("Runtime plist discovery exceeded its bounded inventory.")
            raw = path.read_bytes()
            try:
                definition = plistlib.loads(raw)
            except (ValueError, plistlib.InvalidFileException):
                continue
            if not isinstance(definition, dict):
                continue
            record = dict(path=str(path), byteCount=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                          originalPlistBase64=base64.b64encode(raw).decode("ascii"), definition=definition)
            if definition_contains_service(definition):
                definitions.append(record)
            if path.name != "Info.plist" or path.parent.suffix != ".app" or definition.get("CFBundleExecutable") != "druid":
                continue
            identifier = definition.get("CFBundleIdentifier")
            if not isinstance(identifier, str) or not BUNDLE_ID.fullmatch(identifier):
                raise NotReady("The actual Druid system app has no valid bundle identifier.")
            executable = contained(path.parent / "druid", root)
            if not executable.is_file() or executable.parent != path.parent:
                raise NotReady("The actual Druid executable is not inside its discovered system app.")
            apps.append(dict(bundleID=identifier, bundlePath=str(path.parent), executable=str(executable), info=record))
    return apps, definitions, len(visited)


def prepare(arguments):
    folder = Path(arguments.output_dir)
    folder.mkdir(parents=True, exist_ok=True)
    receipt = folder / "drag-service-readiness.json"
    if receipt.exists():
        raise NotReady("Refusing to overwrite an existing readiness receipt.")
    started = time.monotonic()
    deadline = started + 30
    state = dict(schemaVersion=1, diagnosticOnly=True, ready=False, status="starting", startedAtUTC=now(),
                 repository=os.environ.get("GITHUB_REPOSITORY"), sourceSHA=os.environ.get("GITHUB_SHA"),
                 runID=os.environ.get("GITHUB_RUN_ID"), runAttempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                 deviceID=arguments.device, deadlineSeconds=30, normalSystemAppLaunchAuthorized=arguments.start_confirmed_system_app,
                 commands={}, mutations=[], acceptance="No native, physical-device or release acceptance claimed")
    stream = stream_output = None
    exit_code = 1

    def command(name, argv, limit=6):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NotReady("The 30-second readiness deadline expired.")
        result = dict(command=argv, startedAtUTC=now())
        raw = b""
        try:
            completed = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=min(limit, remaining))
            raw = completed.stdout
            result["exitCode"] = completed.returncode
        except subprocess.TimeoutExpired as error:
            raw = error.stdout or b""
            result.update(exitCode=124, timedOut=True)
        except OSError as error:
            result.update(exitCode=127, errorType=type(error).__name__)
        path = folder / name
        path.write_bytes(raw)
        result.update(endedAtUTC=now(), byteCount=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        state["commands"][name] = result
        if result["exitCode"] != 0:
            raise NotReady("Readiness command failed; retain its original output: " + name)
        return raw.decode(errors="replace").strip()

    def scoped(*argv):
        return ["xcrun", "simctl", "spawn", arguments.device, *argv]

    try:
        if sys.platform != "darwin":
            raise NotReady("Readiness discovery requires the actual macOS Simulator host.")
        head = command("checkout-sha.txt", ["git", "rev-parse", "HEAD"], 2)
        state["checkoutSHA"] = head
        if not re.fullmatch(r"[0-9a-f]{40}", head) or (state["sourceSHA"] and state["sourceSHA"] != head):
            raise NotReady("Readiness source SHA differs from the actual checkout.")
        state["sourceSHA"] = head
        with ThreadPoolExecutor(max_workers=2) as pool:
            devices_future = pool.submit(command, "devices.json", ["xcrun", "simctl", "list", "devices", "available", "--json"])
            runtimes_future = pool.submit(command, "runtimes.json", ["xcrun", "simctl", "list", "runtimes", "--json"])
            devices, runtimes = json.loads(devices_future.result()), json.loads(runtimes_future.result())
        selected = [(runtime, device) for runtime, items in devices["devices"].items() for device in items if device["udid"] == arguments.device]
        if len(selected) != 1 or selected[0][1].get("state") != "Booted":
            raise NotReady("The exact selected Simulator is not uniquely observed Booted.")
        runtime_id, device = selected[0]
        runtime = next((item for item in runtimes["runtimes"] if item["identifier"] == runtime_id), None)
        if not runtime or not runtime.get("isAvailable") or runtime.get("version") != "26.2" or runtime.get("platform") != "iOS":
            raise NotReady("The selected available iOS 26.2 runtime could not be verified.")
        root = Path(runtime["runtimeRoot"]).resolve(strict=True)
        bundle = Path(runtime["bundlePath"]).resolve(strict=True)
        if not root.is_relative_to(bundle) or root.name != "RuntimeRoot":
            raise NotReady("The runtimeRoot is not contained in its actual selected runtime bundle.")
        state.update(selectedDevice=device, selectedRuntime=runtime, runtimeRoot=str(root))
        apps, definitions, count = discover(root, deadline)
        state.update(systemAppCandidates=apps, matchingRuntimeDefinitions=definitions, scannedPlists=count)
        if len(apps) != 1:
            # No launchctl mutation is allowed. Retain only proven Simulator
            # context and exact matching job metadata if the time budget permits.
            try:
                manager = int(command("launchctl-managerpid.txt", scoped("launchctl", "managerpid"), 3))
                state["readOnlyManagerPID"] = manager
                if manager <= 1:
                    raise NotReady("launchctl manager is not a Simulator process.")
                process = command("launchctl-manager-command.txt", ["ps", "-p", str(manager), "-o", "comm="], 2)
                if Path(process).name != "launchd_sim" or contained(Path(process), root).name != "launchd_sim":
                    raise NotReady("launchctl manager does not match this actual runtime's launchd_sim.")
                identity = command("launchctl-device-identity.txt", ["xcrun", "simctl", "getenv", arguments.device, "SIMULATOR_UDID"], 2)
                if identity != arguments.device:
                    raise NotReady("The actual Simulator launchd device identity was not verified.")
                for index, item in enumerate(definitions[:2]):
                    label = item["definition"].get("Label")
                    if isinstance(label, str) and BUNDLE_ID.fullmatch(label):
                        command(f"read-only-job-{index}.txt", scoped("launchctl", "print", f"pid/{manager}/{label}"), 2)
            except (NotReady, ValueError, OSError) as error:
                state["readOnlyManagerDiagnostic"] = str(error)
            raise NotReady("No unique confirmed runtime Druid system app; discovery retained without starting any service.")
        app = apps[0]
        if not arguments.start_confirmed_system_app:
            raise NotReady("A system app was discovered, but no normal app launch was authorized; readiness remains unverified.")
        predicate = 'process == "druid" AND subsystem == "com.apple.DragUI"'
        stream_path = folder / "drag-service-listener.log"
        stream_output = stream_path.open("wb", buffering=0)
        stream_command = scoped("log", "stream", "--style", "compact", "--level", "info", "--predicate", predicate)
        stream = subprocess.Popen(stream_command, stdout=stream_output, stderr=subprocess.STDOUT, start_new_session=True)
        state.update(streamCommand=stream_command, ownedLogStreamPID=stream.pid, streamStartedAtUTC=now())
        while time.monotonic() < deadline:
            if stream.poll() is not None:
                raise NotReady("The actual Simulator service log stream ended before launch.")
            if b"Filtering the log data using" in stream_path.read_bytes():
                break
            time.sleep(0.05)
        else:
            raise NotReady("The actual Simulator service log stream never became ready.")
        launch = ["xcrun", "simctl", "launch", arguments.device, app["bundleID"]]
        state["mutations"].append(dict(kind="normal-public-simulator-system-app-launch", command=launch, startedAtUTC=now()))
        response = command("normal-system-app-launch.txt", launch, 12)
        matches = re.findall(r"^" + re.escape(app["bundleID"]) + r": (\d+)$", response, re.M)
        if len(matches) != 1 or int(matches[0]) <= 1:
            raise NotReady("Normal Simulator app launch did not identify one actual Druid PID.")
        pid = int(matches[0])
        state["launchedSystemAppPID"] = pid
        while time.monotonic() < deadline:
            if stream.poll() is not None:
                raise NotReady("The actual Simulator service log stream ended before readiness.")
            lines = stream_path.read_text(errors="replace").splitlines()
            listener = next((line for line in lines if (match := LISTENER.search(line)) and int(match[1]) == pid), None)
            if listener:
                process = command("ready-process-command.txt", ["ps", "-p", str(pid), "-o", "comm="], 2)
                if contained(Path(process), root) != Path(app["executable"]):
                    raise NotReady("The observed listening PID is not the confirmed runtime Druid executable.")
                state.update(ready=True, status="observed-listening", listenerEvidence=listener, listenerObservedAtUTC=now())
                exit_code = 0
                break
            time.sleep(0.05)
        if not state["ready"]:
            raise NotReady("The actual current Druid PID did not report listening before the deadline.")
    except (NotReady, OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        state.update(status="not-ready", reason=str(error))
    finally:
        # Only terminate this helper's own read-only log stream, never Druid,
        # a Simulator service, launchd, another app or a host service.
        if stream is not None:
            for number in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
                if stream.poll() is not None:
                    break
                try:
                    os.killpg(stream.pid, number)
                    stream.wait(timeout=0.5)
                except ProcessLookupError:
                    break
                except subprocess.TimeoutExpired:
                    pass
            state["logStreamExitCode"] = stream.poll()
        if stream_output is not None:
            stream_output.close()
        log = folder / "drag-service-listener.log"
        if log.exists():
            raw = log.read_bytes()
            state.update(listenerLogBytes=len(raw), listenerLogSHA256=hashlib.sha256(raw).hexdigest())
        state.update(endedAtUTC=now(), elapsedSeconds=time.monotonic() - started, exitCode=exit_code)
        receipt.write_text(json.dumps(state, indent=2, sort_keys=True, default=str) + "\n")
    return exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output-dir", default="GestureDiagnostics/drag-readiness")
    parser.add_argument("--start-confirmed-system-app", action="store_true")
    arguments = parser.parse_args()
    if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", arguments.device):
        parser.error("the actual selected Simulator UUID is required")
    try:
        return prepare(arguments)
    except NotReady as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
