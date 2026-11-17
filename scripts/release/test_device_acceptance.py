#!/usr/bin/env python3
"""Synthetic schema fixtures only: no hardware acceptance is asserted here."""
import copy
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from device_acceptance import DeviceAcceptanceError, GATES, validate_device_acceptance

REPO, SHA, VERSION, BUILD = "owner/repo", "a" * 40, "1.0.0", "17"


def synthetic_document(root):
    """A deliberately invented unit fixture, never exported as device evidence."""
    payload = b"UNIT TEST FIXTURE ONLY. No physical measurement or release acceptance.\n"
    (root / "fixture.txt").write_bytes(payload)
    measured_at = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    candidates = []
    for identifier, role, ios, available in (("oldest", "minimum-ios18", "18.7.1", False), ("current", "current-model-eligible", "26.2.0", True)):
        candidates.append(dict(id=identifier, role=role, physicalDevice=True, model="Synthetic fixture iPhone", iOSVersion=ios,
                               modelAvailable=available, sourceSHA=SHA, version=VERSION, build=BUILD,
                               installationMethod="testflight", installedBuildID="unit-fixture-only", binarySHA256="b" * 64,
                               testedAtUTC=measured_at, evidenceIDs=["fixture"]))
    return dict(schemaVersion=1, classification="release-ready", physicalAcceptance=True, repository=REPO, sourceSHA=SHA,
                version=VERSION, build=BUILD, testedAtUTC=measured_at, tester="Synthetic unit fixture", unresolvedP0P1=[],
                installedCandidates=candidates,
                evidence=[dict(id="fixture", path="fixture.txt", sha256=hashlib.sha256(payload).hexdigest(), kind="measurement-report")],
                gates=[dict(id=identifier, status="pass", testedBy="Synthetic unit fixture", testedAtUTC=measured_at,
                            observedResult="Synthetic validation fixture; no actual device result is asserted.",
                            deviceIDs=["oldest", "current"], evidenceIDs=["fixture"]) for identifier in GATES],
                audioLoadSessions=[dict(fixture=fixture, durationMinutes=30, unexplainedDropouts=0, peakMemoryMB=100,
                                        touchToSoundP95Milliseconds=10, route="unit fixture route", evidenceIDs=["fixture"]) for fixture in ("P1", "P2", "P3")],
                midiControllers=[dict(transport=transport, model="Synthetic controller", firmware="unit fixture 1", evidenceIDs=["fixture"]) for transport in ("usb", "ble")],
                dawImports=[dict(name=name, version="unit fixture 1", formats=["midi", "wav", "stems", "project-source-audio"], evidenceIDs=["fixture"]) for name in ("Synthetic DAW A", "Synthetic DAW B")],
                actualModel=dict(availability="available", requestLocale="en-US", proposalSHA256="c" * 64, evidenceIDs=["fixture"]),
                humanVoice=dict(sourceSHA256="d" * 64, successfulDictationLocales=["ru-RU", "en-US"], noteOnsetPitchF1=0.8,
                                declaredMinimumF1=0.75, protocolDeclaredBeforeSession=True, evidenceIDs=["fixture"]))


class DeviceAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.document = synthetic_document(self.root)

    def validate(self):
        return validate_device_acceptance(self.document, REPO, SHA, VERSION, BUILD, self.root)

    def test_complete_synthetic_receipt_validates_and_hashes_actual_file(self):
        result = self.validate()
        self.assertEqual(result["sourceSHA"], SHA)
        self.assertTrue(result["physicalAccepted"])
        self.assertEqual(result["gateCount"], 9)
        self.assertEqual(result["evidenceFileCount"], 1)
        self.assertEqual(len(result["canonicalReceiptSHA256"]), 64)
        self.assertEqual(result["verifiedEvidence"][0]["sha256"], self.document["evidence"][0]["sha256"])

    def test_missing_and_mismatched_source_build_version_repository_rejected(self):
        baseline = copy.deepcopy(self.document)
        for key in ("repository", "sourceSHA", "version", "build"):
            for replacement in (None, "different-candidate"):
                with self.subTest(key=key, replacement=replacement):
                    self.document = copy.deepcopy(baseline)
                    self.document[key] = replacement
                    with self.assertRaises(DeviceAcceptanceError):
                        self.validate()

    def test_pending_or_failed_gate_and_missing_required_gate_rejected(self):
        baseline = copy.deepcopy(self.document)
        for status in ("pending", "fail", "skipped", None):
            with self.subTest(status=status):
                self.document = copy.deepcopy(baseline)
                self.document["gates"][0]["status"] = status
                with self.assertRaises(DeviceAcceptanceError):
                    self.validate()
        self.document = baseline
        self.document["gates"].pop()
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()

    def test_duplicate_unknown_gate_rejected(self):
        for identifier in ("unrecognized-new-gate", GATES[1]):
            self.document["gates"][0]["id"] = identifier
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_placeholder_measurement_and_future_timestamp_rejected(self):
        baseline = copy.deepcopy(self.document)
        for key, value in (("observedResult", "Pending: owner needs to test this on a device"), ("testedBy", "TBD"), ("testedAtUTC", "Pending"), ("testedAtUTC", "2999-01-01T00:00:00Z")):
            self.document = copy.deepcopy(baseline)
            self.document["gates"][0][key] = value
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_simulator_missing_os_role_or_different_installed_binary_rejected(self):
        baseline = copy.deepcopy(self.document)
        for key, value in (("physicalDevice", False), ("model", "iPhone 16 Simulator"), ("iOSVersion", "26.2.0"), ("sourceSHA", "e" * 40), ("build", "16"), ("binarySHA256", "Pending"), ("installedBuildID", "Pending")):
            self.document = copy.deepcopy(baseline)
            self.document["installedCandidates"][0][key] = value
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_current_device_without_real_model_availability_rejected(self):
        self.document["installedCandidates"][1]["modelAvailable"] = False
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()

    def test_missing_changed_outside_or_symlinked_evidence_rejected(self):
        baseline = copy.deepcopy(self.document)
        for path in ("missing.txt", "../elsewhere.txt", str(self.root / "fixture.txt")):
            self.document = copy.deepcopy(baseline)
            self.document["evidence"][0]["path"] = path
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()
        self.document = baseline
        (self.root / "fixture.txt").write_text("changed")
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "private.txt"
            target.write_text("not an allowed evidence file")
            (self.root / "escape").symlink_to(target)
            self.document["evidence"][0]["path"] = "escape"
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_nonexistent_and_duplicate_evidence_reference_rejected(self):
        for references in ([], ["missing"], ["fixture", "fixture"], [None]):
            self.document["gates"][0]["evidenceIDs"] = references
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_unmeasured_short_loads_dropouts_and_nonfinite_latency_rejected(self):
        baseline = copy.deepcopy(self.document)
        for key, value in (("durationMinutes", 29.99), ("unexplainedDropouts", 1), ("unexplainedDropouts", False), ("peakMemoryMB", None), ("touchToSoundP95Milliseconds", float("nan")), ("route", "Unknown")):
            self.document = copy.deepcopy(baseline)
            self.document["audioLoadSessions"][0][key] = value
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_missing_ble_and_duplicate_daw_do_not_satisfy_hardware_gate(self):
        baseline = copy.deepcopy(self.document)
        self.document["midiControllers"].pop()
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()
        self.document = baseline
        self.document["dawImports"][1]["name"] = self.document["dawImports"][0]["name"]
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()

    def test_parser_fallback_and_no_speech_detected_are_not_live_model_voice_success(self):
        baseline = copy.deepcopy(self.document)
        self.document["actualModel"]["availability"] = "commands-fallback"
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()
        self.document = baseline
        self.document["humanVoice"]["successfulDictationLocales"] = []
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()

    def test_failed_human_criterion_or_posthoc_criterion_rejected(self):
        baseline = copy.deepcopy(self.document)
        for key, value in (("noteOnsetPitchF1", 0.6), ("protocolDeclaredBeforeSession", False)):
            self.document = copy.deepcopy(baseline)
            self.document["humanVoice"][key] = value
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_open_p0_p1_and_unperformed_acceptance_rejected(self):
        baseline = copy.deepcopy(self.document)
        for key, value in (("unresolvedP0P1", ["known microphone failure"]), ("physicalAcceptance", False)):
            self.document = copy.deepcopy(baseline)
            self.document[key] = value
            with self.assertRaises(DeviceAcceptanceError):
                self.validate()

    def test_template_intentionally_cannot_authorize_release(self):
        self.document = json.loads((Path(__file__).resolve().parents[2] / "docs/release/newdevice-receipt-template.json").read_text())
        with self.assertRaises(DeviceAcceptanceError):
            self.validate()

    def test_cli_rejects_pending_without_printing_document_or_credentials(self):
        receipt = self.root / "receipt.json"
        self.document["tester"] = "PRIVATE-CREDENTIAL-SENTINEL"
        self.document["sourceSHA"] = "Pending"
        receipt.write_text(json.dumps(self.document))
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("device_acceptance.py")), "--receipt", str(receipt), "--repo", REPO, "--sha", SHA, "--version", VERSION, "--build", BUILD, "--evidence-root", str(self.root)], capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PRIVATE-CREDENTIAL-SENTINEL", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
