#!/usr/bin/env python3
"""Bounded Simulator-only DragUI readiness experiment; never app acceptance.

Discover the actual selected runtime's definitions first. Only the explicit
flags permit a normal public simctl launch of a uniquely verified Druid system
app or a selected-Simulator start of its verified runtime LaunchDaemon. The
daemon path requires that runtime's Simulator-platform launchctl executable;
no host/bare launchctl command or guessed service label is used.
No application touch, test retry, host service mutation or TCC change occurs.
"""
import argparse
import base64
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
from simulator_macho import inspect_simulator_executable


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
                raise NotReady("The service-readiness deadline expired during discovery.")
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


def daemon_candidates(definitions, root):
    """Resolve the actual job declaring this endpoint, never a guessed label."""
    candidates = []
    for record in definitions:
        definition = record["definition"]
        services = definition.get("MachServices")
        if not isinstance(services, dict) or services.get(MACH_SERVICE) is not True:
            continue
        path = contained(Path(record["path"]), root)
        if path.parent != root / "System/Library/LaunchDaemons":
            raise NotReady("The Druid endpoint is not defined by a runtime LaunchDaemon.")
        label, arguments = definition.get("Label"), definition.get("ProgramArguments")
        if (not isinstance(label, str) or not BUNDLE_ID.fullmatch(label)
                or not isinstance(arguments, list) or not arguments
                or any(not isinstance(value, str) for value in arguments)):
            raise NotReady("The actual Druid job label/program definition is unsupported.")
        program = Path(arguments[0])
        if not program.is_absolute() or ".." in program.parts or program.name != "druid":
            raise NotReady("The Druid job does not name an absolute runtime druid executable.")
        executable = contained(root / str(program).lstrip("/"), root)
        if not executable.is_file() or executable.name != "druid":
            raise NotReady("The declared Druid executable is not inside the selected runtime.")
        candidates.append(dict(label=label, executable=str(executable), job=record))
    return candidates


def runtime_launchctl(root):
    """Only a real tool in the selected runtime may enter its spawn context."""
    tools = set()
    for relative in ("bin/launchctl", "usr/bin/launchctl"):
        candidate = root / relative
        if candidate.exists():
            resolved = contained(candidate, root)
            if not resolved.is_file() or resolved.name != "launchctl":
                raise NotReady("The runtime launchctl candidate is not a contained executable.")
            tools.add(resolved)
    if len(tools) != 1:
        raise NotReady("No unique runtime-contained launchctl; host-tool fallback is prohibited.")
    return tools.pop()


def prepare(arguments):
    folder = Path(arguments.output_dir)
    folder.mkdir(parents=True, exist_ok=True)
    receipt = folder / "drag-service-readiness.json"
    if receipt.exists():
        raise NotReady("Refusing to overwrite an existing readiness receipt.")
    started = time.monotonic()
    overall_deadline = started + 90
    # Reserve the existing <=1.5-second owned-stream cleanup inside the total.
    deadline = overall_deadline - 1.5
    state = dict(schemaVersion=1, diagnosticOnly=True, ready=False, status="starting", startedAtUTC=now(),
                 repository=os.environ.get("GITHUB_REPOSITORY"), sourceSHA=os.environ.get("GITHUB_SHA"),
                 runID=os.environ.get("GITHUB_RUN_ID"), runAttempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                 deviceID=arguments.device, deadlineSeconds=90, overallDeadlineSeconds=90,
                 metadataQueryLimitSeconds=30, serviceDeadlineSeconds=30, phase="runtime-inventory",
                 normalSystemAppLaunchAuthorized=arguments.start_confirmed_system_app,
                 normalDaemonStartAuthorized=bool(getattr(arguments, "start_confirmed_daemon", False)),
                 commands={}, mutations=[], acceptance="No native, physical-device or release acceptance claimed")
    stream = stream_output = None
    exit_code = 1

    def command(name, argv, limit=6):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NotReady("The readiness phase or overall initialization deadline expired.")
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
        # CoreSimulator/xcrun startup is shared. Concurrent inventory requests
        # stalled on c29, while this same VM's sequential requests succeeded.
        devices = json.loads(command("devices.json", ["xcrun", "simctl", "list", "devices", "available", "--json"], 30))
        runtimes = json.loads(command("runtimes.json", ["xcrun", "simctl", "list", "runtimes", "--json"], 30))
        # Inventory initializes CoreSimulator; only then budget service startup.
        # Each phase remains subordinate to the hard overall initialization cap.
        service_started = time.monotonic()
        deadline = min(service_started + 30, overall_deadline - 1.5)
        state.update(phase="service-readiness", serviceStartedAtUTC=now(),
                     effectiveServiceBudgetSeconds=max(0, deadline - service_started))
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
        daemons = daemon_candidates(definitions, root)
        state["daemonCandidates"] = daemons
        if len(apps) > 1 or len(daemons) > 1:
            raise NotReady("Druid definitions are ambiguous; no process may be started.")
        expected_pid = None
        if len(apps) == 1:
            app = apps[0]
            if not arguments.start_confirmed_system_app:
                raise NotReady("A Druid system app was found, but its normal launch was not authorized.")
            launch = ["xcrun", "simctl", "launch", arguments.device, app["bundleID"]]
            expected_executable = Path(app["executable"])
            mutation_kind = "normal-public-simulator-system-app-launch"
        elif len(daemons) == 1:
            daemon = daemons[0]
            if not state["normalDaemonStartAuthorized"]:
                raise NotReady("A Druid LaunchDaemon was found, but its selected-Simulator start was not authorized.")
            tool = runtime_launchctl(root)
            architecture = command("host-architecture.txt", ["uname", "-m"], 2)
            if architecture not in ("arm64", "x86_64"):
                raise NotReady("The native Simulator host architecture is unsupported.")
            command("runtime-launchctl-architecture.txt", ["xcrun", "lipo", str(tool), "-verify_arch", architecture])
            if tool.stat().st_size > 128 * 1024 * 1024:
                raise NotReady("The contained runtime tool exceeds the bounded inspection size.")
            raw = tool.read_bytes()
            # Cold xcrun/vtool repeatedly stalled before doing any service work.
            # Read the actual contained Mach-O header/load commands instead;
            # retain their original bytes and require platform7 in every slice.
            try:
                inspection = inspect_simulator_executable(raw, architecture)
            except ValueError as error:
                state["rejectedRuntimeLaunchctl"] = dict(path=str(tool), byteCount=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest(), reason=str(error))
                if len(raw) <= 128 * 1024 * 1024:
                    rejected_path = folder / "runtime-launchctl-rejected.macho"
                    rejected_path.write_bytes(raw)
                    state["rejectedRuntimeLaunchctl"]["file"] = rejected_path.name
                raise
            build_path = folder / "runtime-launchctl-build.json"
            build_path.write_text(json.dumps(inspection, indent=2, sort_keys=True) + "\n")
            evidence = build_path.read_bytes()
            state["readOnlyBinaryInspections"] = {"runtime-launchctl-build.json": dict(
                byteCount=len(evidence), sha256=hashlib.sha256(evidence).hexdigest())}
            state["verifiedRuntimeLaunchctl"] = dict(path=str(tool), byteCount=len(raw),
                                                      sha256=hashlib.sha256(raw).hexdigest(),
                                                      architecture=architecture, platforms=["IOSSIMULATOR"],
                                                      platformIdentifiers=inspection["platforms"],
                                                      inspectionEvidence=build_path.name)
            service = "system/" + daemon["label"]
            job = command("runtime-druid-job.txt", scoped(str(tool), "print", service), 6)
            declared_program = daemon["job"]["definition"]["ProgramArguments"][0]
            if (daemon["label"] not in job or MACH_SERVICE not in job
                    or not any(path in job for path in (declared_program, daemon["executable"]))):
                raise NotReady("The selected Simulator's loaded job does not match its actual runtime Druid definition.")
            # simctl spawn enters the exact selected device's execution context.
            # No -k: this requests startup without killing/restarting a daemon.
            launch = scoped(str(tool), "kickstart", service)
            expected_executable = Path(daemon["executable"])
            mutation_kind = "normal-selected-simulator-runtime-daemon-start"
        else:
            raise NotReady("No unique confirmed Druid system app or runtime LaunchDaemon.")
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
        state["mutations"].append(dict(kind=mutation_kind, command=launch, startedAtUTC=now()))
        response = command("normal-system-app-launch.txt", launch, 12)
        if mutation_kind == "normal-public-simulator-system-app-launch":
            matches = re.findall(r"^" + re.escape(app["bundleID"]) + r": (\d+)$", response, re.M)
            if len(matches) != 1 or int(matches[0]) <= 1:
                raise NotReady("Normal Simulator app launch did not identify one actual Druid PID.")
            expected_pid = int(matches[0])
            state["launchedSystemAppPID"] = expected_pid
        while time.monotonic() < deadline:
            if stream.poll() is not None:
                raise NotReady("The actual Simulator service log stream ended before readiness.")
            lines = stream_path.read_text(errors="replace").splitlines()
            listener = next((line for line in lines if (match := LISTENER.search(line))
                             and int(match[1]) > 1 and (expected_pid is None or int(match[1]) == expected_pid)), None)
            if listener:
                pid = int(LISTENER.search(listener)[1])
                process = command("ready-process-command.txt", ["ps", "-p", str(pid), "-o", "comm="], 2)
                if contained(Path(process), root) != expected_executable:
                    raise NotReady("The observed listening PID is not the confirmed runtime Druid executable.")
                state.update(ready=True, status="observed-listening", listeningProcessPID=pid,
                             listeningExecutable=str(expected_executable), listenerEvidence=listener, listenerObservedAtUTC=now())
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
    parser.add_argument("--start-confirmed-daemon", action="store_true")
    arguments = parser.parse_args()
    if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", arguments.device):
        parser.error("the actual selected Simulator UUID is required")
    try:
        return prepare(arguments)
    except NotReady as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
