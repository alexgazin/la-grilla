#!/usr/bin/env python3
"""Actual XCTest inventory and source/run-correlated native scope receipts."""
from pathlib import Path
import re

OPT_IN_DIAGNOSTICS = {"AudioRuntimeContinuityTests/testDiagnosticOnlyFreshInputLifecycleControls"}


def functional_inventory(directory):
    tests = set()
    for path in sorted(Path(directory).glob("*.swift")):
        # UI test declarations are standard XCTestCase classes. Strip comments
        # so examples in documentation cannot create an expected test case.
        source = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(), flags=re.S)
        classes = list(re.finditer(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source))
        for index, declaration in enumerate(classes):
            name = declaration[1]
            if name == "ScreenshotTests":
                continue  # Capture-only methods are separate from functional acceptance.
            body = source[declaration.end():classes[index + 1].start() if index + 1 < len(classes) else len(source)]
            tests.update(name + "/" + method for method in re.findall(r"\bfunc\s+(test\w+)\s*\(", body))
    tests -= OPT_IN_DIAGNOSTICS
    if not tests:
        raise ValueError("No functional XCTest inventory found in the selected source.")
    return sorted(tests)


def observed_outcomes(output):
    outcomes = {}
    for match in re.finditer(r"Test Case '-\[([^\s\]]+) ([^\]\s]+)\]' (passed|failed|skipped)", output):
        outcomes[match[1].rsplit(".", 1)[-1] + "/" + match[2]] = match[3]
    return outcomes


def validate_scope_receipt(document, repo, sha, run_id, run_attempt, expected_tests):
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    require(isinstance(document, dict) and type(document.get("schemaVersion")) is int and document["schemaVersion"] == 1, "Native scope receipt is missing or unsupported.")
    for key, expected in (("repository", repo), ("sourceSHA", sha), ("runID", str(run_id)), ("runAttempt", str(run_attempt))):
        require(document.get(key) == expected, "Native scope receipt does not match its source/run/attempt.")
    require(document.get("status") == "completed" and type(document.get("exitCode")) is int and document["exitCode"] == 0 and type(document.get("subprocessExitCode")) is int and document["subprocessExitCode"] == 0 and document.get("timedOut") is False and document.get("receivedSignal") is None, "Native process did not complete successfully.")
    require(document.get("scope") in ("full", "ui-only") and document.get("scopeStatus") == "full-functional-pass" and document.get("functionalInventoryVerified") is True, "Native artifact does not declare verified full functional scope.")
    expected = set(expected_tests)
    recorded = document.get("expectedFunctionalTests")
    require(expected and isinstance(recorded, list) and all(isinstance(item, str) for item in recorded) and len(recorded) == len(set(recorded)) and set(recorded) == expected, "Native functional inventory does not match this exact source.")
    outcomes = document.get("requiredTestOutcomes")
    require(isinstance(outcomes, dict) and all(outcomes.get(identifier) == "passed" for identifier in expected), "A required functional test did not actually pass; zero-test and skipped success are not acceptance.")
    return {"scope": document["scope"], "scopeStatus": document["scopeStatus"], "functionalTestCount": len(expected)}
