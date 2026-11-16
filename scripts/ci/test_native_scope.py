#!/usr/bin/env python3
"""Scope regressions; fixtures describe parser inputs, not real device passes."""
import copy
from pathlib import Path
import tempfile
import unittest
from native_scope import functional_inventory, observed_outcomes, validate_scope_receipt


class NativeScopeTests(unittest.TestCase):
    def setUp(self):
        self.expected=["StudioTests/testCreate", "VoiceTests/testCapture"]
        self.receipt=dict(schemaVersion=1,repository="owner/repo",sourceSHA="a"*40,runID="91",runAttempt="2",status="completed",exitCode=0,subprocessExitCode=0,timedOut=False,receivedSignal=None,scope="full",scopeStatus="full-functional-pass",functionalInventoryVerified=True,expectedFunctionalTests=self.expected.copy(),requiredTestOutcomes={identifier:"passed" for identifier in self.expected})
    def verify(self):return validate_scope_receipt(self.receipt,"owner/repo","a"*40,91,2,self.expected)
    def test_actual_inventory_excludes_only_captures_and_named_optin_diagnostic(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)
            (path/"Studio.swift").write_text("final class StudioTests:XCTestCase {func testCreate(){} // func testComment(){}\n}")
            (path/"Capture.swift").write_text("final class ScreenshotTests:XCTestCase {func testCaptureStoreScreens(){}}")
            (path/"Audio.swift").write_text("final class AudioRuntimeContinuityTests:XCTestCase {func testRealCapture(){} func testDiagnosticOnlyFreshInputLifecycleControls(){}}")
            self.assertEqual(functional_inventory(path),["AudioRuntimeContinuityTests/testRealCapture","StudioTests/testCreate"])
    def test_no_tests_is_not_an_inventory(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):functional_inventory(folder)
    def test_observed_outcomes_require_actual_case_terminal_lines(self):
        text="Test Case '-[Fixture.StudioTests testCreate]' passed (2.0 seconds).\nTest Case '-[Fixture.VoiceTests testCapture]' skipped (0.0 seconds).\nExecuted 2 tests, with 0 failures"
        self.assertEqual(observed_outcomes(text),{"StudioTests/testCreate":"passed","VoiceTests/testCapture":"skipped"})
        self.assertEqual(observed_outcomes("Executed 0 tests, with 0 failures"),{})
    def test_actual_allowance_marker_stays_failure_despite_late_pass(self):
        # Original a61 run43912715044 stdout, not invented native/device proof.
        text=(Path(__file__).parent/"fixtures/a61-case-timeout-late-pass.txt").read_text()
        identity="AIAvailabilityTests/testActualUnavailableModelLocallyReviewsJazzAppliesAndUndoesOnce"
        self.assertEqual(observed_outcomes(text),{identity:"time-allowance-exceeded"})
        self.assertEqual(observed_outcomes("\n".join(reversed(text.splitlines()))),{identity:"time-allowance-exceeded"})
    def test_allowance_markers_are_case_specific_and_ignore_quoted_prose(self):
        timeout="Test Case '-[Fixture.OtherTests testCreate]' exceeded execution time allowance of 2 minutes."
        passed="Test Case '-[Fixture.StudioTests testCreate]' passed (1.000 seconds)."
        self.assertEqual(observed_outcomes(timeout+"\n"+passed),{"OtherTests/testCreate":"time-allowance-exceeded","StudioTests/testCreate":"passed"})
        for prose in [repr(timeout),'print('+repr(timeout)+')','Example: '+timeout,'{"output": '+repr(timeout)+'}']:
            with self.subTest(prose=prose):
                self.assertEqual(observed_outcomes(prose+"\n"+passed),{"StudioTests/testCreate":"passed"})
    def test_allowance_violation_cannot_validate_a_claimed_full_pass(self):
        text="Test Case '-[Fixture.StudioTests testCreate]' exceeded execution time allowance of 2 minutes.\nTest Case '-[Fixture.StudioTests testCreate]' passed (121.0 seconds).\nTest Case '-[Fixture.VoiceTests testCapture]' passed (1.0 seconds)."
        self.receipt["requiredTestOutcomes"]=observed_outcomes(text)
        with self.assertRaises(ValueError):self.verify()
    def test_complete_matching_inventory_accepts_and_reports_scope(self):
        self.assertEqual(self.verify(),dict(scope="full",scopeStatus="full-functional-pass",functionalTestCount=2))
    def test_partial_zero_skipped_or_missing_inventory_rejected(self):
        baseline=copy.deepcopy(self.receipt)
        for key,value in [("scope","integration-only"),("scopeStatus","focused-pass"),("expectedFunctionalTests",[]),("requiredTestOutcomes",{}),("requiredTestOutcomes",{identifier:"skipped" for identifier in self.expected}),("functionalInventoryVerified",False)]:
            self.receipt=copy.deepcopy(baseline);self.receipt[key]=value
            with self.assertRaises(ValueError):self.verify()
    def test_other_source_run_attempt_or_process_failure_rejected(self):
        baseline=copy.deepcopy(self.receipt)
        for key,value in [("sourceSHA","b"*40),("runID","92"),("runAttempt","1"),("exitCode",124),("exitCode",False),("schemaVersion",True),("subprocessExitCode",65),("timedOut",True),("receivedSignal",15)]:
            self.receipt=copy.deepcopy(baseline);self.receipt[key]=value
            with self.assertRaises(ValueError):self.verify()


if __name__=="__main__":unittest.main()
