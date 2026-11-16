#!/usr/bin/env python3
"""Validate source-correlated physical evidence before a release-ready claim.

An accepted receipt is a traceable declaration with locally hash-checked files,
not independent proof that its author performed the physical measurements.
Internal beta distribution does not require or fabricate this receipt.
"""
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
import math
from pathlib import Path
import re
import sys

GATES = (
    "phone-startup-and-privacy", "audio-live-loads-and-routes",
    "voice-human-and-dictation", "actual-foundation-models",
    "editing-accessibility-and-persistence", "external-midi",
    "two-daw-export-import", "minimum-ios18-runtime", "signed-candidate-and-upgrade",
)
ROOT = Path(__file__).resolve().parents[2]
PLACEHOLDER = re.compile(r"^(pending|todo|tbd|unknown|unmeasured|not tested|not recorded|replace|example)(?:\b|:)", re.I)


class DeviceAcceptanceError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise DeviceAcceptanceError(message)


def text(value, field, minimum=1):
    require(isinstance(value, str) and len(value.strip()) >= minimum and not PLACEHOLDER.match(value.strip()), field + " is absent or still a placeholder.")
    return value


def digest(value, field):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None, field + " needs an actual SHA-256.")


def timestamp(value, field):
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        valid = parsed.utcoffset() == timedelta(0) and parsed <= datetime.now(timezone.utc) + timedelta(minutes=5)
    except (ValueError, TypeError, AttributeError):
        valid = False
    require(valid, field + " needs a recorded UTC timestamp, not a future or pending value.")
    return parsed


def number(value, field, minimum=0, maximum=None):
    require(type(value) in (int, float) and math.isfinite(value) and value >= minimum and (maximum is None or value <= maximum), field + " needs a finite measured value in range.")


def validate_device_acceptance(document, repo, sha, version, build, evidence_root=ROOT):
    require(isinstance(document, dict), "Physical receipt must be an object.")
    require(type(document.get("schemaVersion")) is int and document["schemaVersion"] == 1, "Unsupported physical receipt schema.")
    require(document.get("classification") == "release-ready", "Physical receipt is not a release-ready acceptance.")
    require(document.get("physicalAcceptance") is True, "Physical acceptance has not been performed.")
    for key, expected in (("repository", repo), ("sourceSHA", sha), ("version", version), ("build", str(build))):
        require(document.get(key) == expected, "Physical receipt " + key + " does not match this exact candidate.")
    require(re.fullmatch(r"[0-9a-f]{40}", sha) is not None, "Invalid exact source identity.")
    accepted_at = timestamp(document.get("testedAtUTC"), "Receipt testedAtUTC")
    text(document.get("tester"), "Receipt tester", 2)
    require(document.get("unresolvedP0P1") == [], "Unresolved P0/P1 defects prevent release-ready classification.")

    evidence = document.get("evidence")
    require(isinstance(evidence, list) and evidence, "Physical receipt has no evidence files.")
    evidence_ids = set()
    root = Path(evidence_root).resolve()
    for entry in evidence:
        require(isinstance(entry, dict), "Malformed physical evidence entry.")
        identifier = text(entry.get("id"), "Evidence id")
        require(identifier not in evidence_ids, "Duplicate physical evidence id.")
        evidence_ids.add(identifier)
        relative = text(entry.get("path"), "Evidence path")
        path = Path(relative)
        require(not path.is_absolute() and ".." not in path.parts, "Physical evidence must use a contained relative file path.")
        resolved = (root / path).resolve()
        require(resolved.is_relative_to(root) and resolved.is_file(), "Physical evidence file is missing or outside its evidence root.")
        digest(entry.get("sha256"), "Evidence hash")
        require(resolved.stat().st_size <= 128 * 1024 * 1024, "Physical evidence file exceeds the validator limit.")
        with resolved.open("rb") as source:
            hashed = hashlib.file_digest(source, "sha256").hexdigest()
        require(hashed == entry["sha256"], "Physical evidence hash does not match its recorded file.")
        require(entry.get("kind") in ("device-log", "screen-recording", "audio-capture", "measurement-report", "daw-import-report", "model-proposal", "signed-build-receipt"), "Record the actual physical evidence kind.")

    def references(value, field):
        require(isinstance(value, list) and value and all(isinstance(item, str) for item in value) and len(value) == len(set(value)) and all(item in evidence_ids for item in value), field + " needs existing, unique evidence references.")

    devices = document.get("installedCandidates")
    require(isinstance(devices, list) and len(devices) >= 2, "Record minimum-iOS and current-model physical candidates.")
    device_ids, roles = set(), {}
    for device in devices:
        require(isinstance(device, dict), "Malformed installed candidate.")
        identifier = text(device.get("id"), "Installed candidate id")
        require(identifier not in device_ids, "Duplicate installed candidate id.")
        device_ids.add(identifier)
        require(device.get("physicalDevice") is True, "Simulator evidence cannot satisfy physical acceptance.")
        for key, expected in (("sourceSHA", sha), ("version", version), ("build", str(build))):
            require(device.get(key) == expected, "Installed candidate " + key + " does not match the receipt.")
        model_name = text(device.get("model"), "Physical iPhone model", 3)
        require("simulator" not in model_name.casefold() and "virtual" not in model_name.casefold(), "Simulator/virtual model cannot satisfy physical acceptance.")
        ios = text(device.get("iOSVersion"), "Physical iOS version")
        require(re.fullmatch(r"\d+(?:\.\d+){1,2}(?: \([A-Za-z0-9]+\))?", ios) is not None, "Record the physical iOS version/build.")
        role = device.get("role")
        require(role in ("minimum-ios18", "current-model-eligible") and role not in roles, "Installed candidate roles must be explicit and unique.")
        major = int(ios.split(".")[0])
        require(major == 18 if role == "minimum-ios18" else major >= 26 and device.get("modelAvailable") is True, "Physical candidate does not satisfy its claimed OS/model role.")
        roles[role] = identifier
        require(device.get("installationMethod") in ("xcode-personal-team", "xcode-development", "ad-hoc", "testflight", "app-store"), "Record the actual installation method.")
        text(device.get("installedBuildID"), "Installed signed build identifier", 3)
        digest(device.get("binarySHA256"), "Installed binary hash")
        require(timestamp(device.get("testedAtUTC"), "Installed candidate testedAtUTC") <= accepted_at, "Receipt predates an installed-candidate session.")
        references(device.get("evidenceIDs"), "Installed candidate")
    require(set(roles) == {"minimum-ios18", "current-model-eligible"}, "Minimum-iOS/current-model physical acceptance is incomplete.")

    gates = document.get("gates")
    require(isinstance(gates, list) and len(gates) == len(GATES), "Physical receipt must cover every required acceptance gate.")
    seen = set()
    for gate in gates:
        require(isinstance(gate, dict) and gate.get("id") in GATES and gate.get("id") not in seen, "Unknown, duplicate or malformed physical acceptance gate.")
        seen.add(gate["id"])
        require(gate.get("status") == "pass", "A physical acceptance gate is missing, pending or failed.")
        text(gate.get("testedBy"), "Gate tester", 2)
        require(timestamp(gate.get("testedAtUTC"), "Gate testedAtUTC") <= accepted_at, "Receipt predates a gate session.")
        text(gate.get("observedResult"), "Gate observed result", 20)
        references(gate.get("evidenceIDs"), "Gate")
        identifiers = gate.get("deviceIDs")
        require(isinstance(identifiers, list) and identifiers and all(isinstance(item, str) and item in device_ids for item in identifiers), "Gate needs actual recorded candidate references.")
        if gate["id"] == "minimum-ios18-runtime":
            require(roles["minimum-ios18"] in identifiers, "Minimum-iOS gate must reference the iOS 18 candidate.")
        if gate["id"] == "actual-foundation-models":
            require(roles["current-model-eligible"] in identifiers, "Model gate must reference the eligible physical candidate.")

    loads = document.get("audioLoadSessions")
    require(isinstance(loads, list) and len(loads) == 3 and {item.get("fixture") for item in loads if isinstance(item, dict)} == {"P1", "P2", "P3"}, "Record all three physical audio load sessions.")
    for session in loads:
        number(session.get("durationMinutes"), "Load duration", 30)
        require(type(session.get("unexplainedDropouts")) is int and session["unexplainedDropouts"] == 0, "Unexplained audio dropouts remain open or unmeasured.")
        number(session.get("peakMemoryMB"), "Measured peak memory", 0.001)
        number(session.get("touchToSoundP95Milliseconds"), "Measured touch-to-sound p95", 0.001)
        text(session.get("route"), "Measured audio route")
        references(session.get("evidenceIDs"), "Audio load session")
    controllers = document.get("midiControllers")
    require(isinstance(controllers, list) and {item.get("transport") for item in controllers if isinstance(item, dict)} >= {"usb", "ble"}, "Physical USB and BLE MIDI coverage is incomplete.")
    for controller in controllers:
        require(isinstance(controller, dict), "Malformed MIDI controller entry.")
        text(controller.get("model"), "MIDI controller model")
        text(controller.get("firmware"), "MIDI controller firmware")
        references(controller.get("evidenceIDs"), "MIDI controller")
    daws = document.get("dawImports")
    require(isinstance(daws, list) and len(daws) >= 2, "Record imports in two actual DAWs.")
    names = set()
    for daw in daws:
        require(isinstance(daw, dict), "Malformed DAW import entry.")
        names.add(text(daw.get("name"), "DAW name").casefold())
        text(daw.get("version"), "DAW version")
        require(set(daw.get("formats", [])) >= {"midi", "wav", "stems", "project-source-audio"}, "DAW import formats/source-audio verification is incomplete.")
        references(daw.get("evidenceIDs"), "DAW import")
    require(len(names) >= 2, "Two entries for one DAW do not satisfy independent imports.")
    model = document.get("actualModel")
    require(isinstance(model, dict) and model.get("availability") == "available", "Actual Foundation Models generation has not been recorded.")
    text(model.get("requestLocale"), "Actual model request locale")
    digest(model.get("proposalSHA256"), "Actual model proposal hash")
    references(model.get("evidenceIDs"), "Actual model")
    voice = document.get("humanVoice")
    require(isinstance(voice, dict), "Recorded human voice results are missing.")
    digest(voice.get("sourceSHA256"), "Recorded human source hash")
    require(set(voice.get("successfulDictationLocales", [])) >= {"ru-RU", "en-US"}, "Successful live RU/EN dictation has not been recorded.")
    number(voice.get("noteOnsetPitchF1"), "Human note onset/pitch F1", 0, 1)
    number(voice.get("declaredMinimumF1"), "Predeclared human F1 criterion", 0.001, 1)
    require(voice["noteOnsetPitchF1"] >= voice["declaredMinimumF1"] and voice.get("protocolDeclaredBeforeSession") is True, "Human voice result did not meet its predeclared criterion.")
    references(voice.get("evidenceIDs"), "Human voice")
    canonical = json.dumps(document, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return {"sourceSHA": sha, "version": version, "build": str(build), "physicalAccepted": True,
            "testedAtUTC": document["testedAtUTC"], "gateCount": len(seen), "evidenceFileCount": len(evidence_ids),
            "canonicalReceiptSHA256": hashlib.sha256(canonical).hexdigest(),
            "verifiedEvidence": [{"id": item["id"], "sha256": item["sha256"]} for item in evidence]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("receipt", "repo", "sha", "version", "build"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--evidence-root", type=Path, default=ROOT)
    arguments = parser.parse_args()
    try:
        document = json.loads(Path(arguments.receipt).read_text())
        result = validate_device_acceptance(document, arguments.repo, arguments.sha, arguments.version, arguments.build, arguments.evidence_root)
    except DeviceAcceptanceError as error:
        raise SystemExit(str(error)) from None
    except (OSError, ValueError, TypeError, KeyError) as error:
        raise SystemExit("Could not validate physical receipt (" + type(error).__name__ + ").") from None
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
