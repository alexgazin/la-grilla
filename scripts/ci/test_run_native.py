#!/usr/bin/env python3
"""Exercise actual processes, signals, streamed bytes and deadline cleanup."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SUPERVISOR = Path(__file__).with_name("run_native.py")


class NativeSupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log, self.status = self.root / "native.log", self.root / "status.json"

    def command(self, script, timeout=5, extra=()):
        return [sys.executable, str(SUPERVISOR), "--timeout-seconds", str(timeout),
                "--interrupt-grace-seconds", "0.15", "--terminate-grace-seconds", "0.15",
                "--log", str(self.log), "--status", str(self.status), *extra,
                "--", sys.executable, "-u", "-c", script]

    def invoke(self, script, **kwargs):
        result = subprocess.run(self.command(script, **kwargs), capture_output=True, timeout=8)
        return result, json.loads(self.status.read_text())

    def test_zero_exit_preserves_stdout_stderr_and_original_bytes(self):
        result, state = self.invoke("import os,time;os.write(1,b'first\\n');time.sleep(.03);os.write(2,b'last\\xff\\n')")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.log.read_bytes(), b"first\nlast\xff\n")
        self.assertEqual(result.stdout, self.log.read_bytes())
        self.assertEqual(state["subprocessExitCode"], 0)
        self.assertFalse(state["timedOut"])
        self.assertEqual(state["status"], "completed")

    def test_nonzero_exit_is_not_relabelled_success(self):
        result, state = self.invoke("import sys;print('assertion failed');sys.exit(23)")
        self.assertEqual(result.returncode, 23)
        self.assertEqual(state["subprocessExitCode"], 23)
        self.assertIn("assertion failed", self.log.read_text())

    def invoke_without_draining_console(self, script, **kwargs):
        # Deliberately leave the outer pipe unread until the supervisor exits.
        # A synchronous console tee would deadlock before checking its timeout.
        supervisor = subprocess.Popen(self.command(script, **kwargs), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            supervisor.wait(timeout=5)
        finally:
            # Keep even a regressing supervisor test bounded and orphan-free.
            if supervisor.poll() is None:
                state = json.loads(self.status.read_text()) if self.status.exists() else {}
                if state.get("processGroupID"):
                    try:
                        os.killpg(state["processGroupID"], signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                supervisor.kill()
            output, error = supervisor.communicate(timeout=3)
        return supervisor.returncode, output, error, json.loads(self.status.read_text())

    def test_unread_console_pipe_does_not_block_timeout_or_original_output(self):
        size = 1024 * 1024
        script = ("import os,signal,time;signal.signal(signal.SIGINT,signal.SIG_IGN);"
                  "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                  f"os.write(1,b'N'*{size});time.sleep(50)")
        code, output, _, state = self.invoke_without_draining_console(script, timeout=0.5)
        self.assertEqual(code, 124)
        self.assertTrue(state["timedOut"])
        self.assertEqual(state["subprocessExitCode"], -signal.SIGKILL)
        self.assertLess(state["elapsedSeconds"], 4)
        self.assertTrue(self.log.read_bytes().startswith(b'N' * size))
        self.assertGreater(state["consoleBytesDropped"], 0)
        self.assertEqual(state["consoleBytesWritten"], len(output))
        self.assertEqual(state["consoleBytesWritten"] + state["consoleBytesDropped"], self.log.stat().st_size)
        self.assert_process_not_running(state["subprocessPID"])

    def test_unread_console_keeps_zero_exit_and_required_outcome_from_complete_log(self):
        line = "Test Case '-[FixtureModule.ActualCase testRequested]' passed (1.000 seconds)."
        script = f"import os;os.write(1,b'N'*1048576+b'\\n'+{line.encode()!r}+b'\\n')"
        code, output, _, state = self.invoke_without_draining_console(script, extra=("--require-test", "ActualCase/testRequested"))
        self.assertEqual(code, 0)
        self.assertEqual(state["subprocessExitCode"], 0)
        self.assertFalse(state["timedOut"])
        self.assertEqual(self.log.read_bytes(), b'N' * 1048576 + b'\n' + line.encode() + b'\n')
        self.assertEqual(state["requiredTestOutcomes"], {"ActualCase/testRequested": "passed"})
        self.assertGreater(state["consoleBytesDropped"], 0)
        self.assertEqual(state["consoleBytesWritten"], len(output))
        self.assertEqual(state["consoleBytesWritten"] + state["consoleBytesDropped"], self.log.stat().st_size)

    def test_signal_exit_uses_shell_convention(self):
        result, state = self.invoke("import os,signal;print('before signal');os.kill(os.getpid(),signal.SIGTERM)")
        self.assertEqual(result.returncode, 143)
        self.assertEqual(state["subprocessExitCode"], -signal.SIGTERM)
        self.assertFalse(state["timedOut"])

    def test_timeout_kills_resistant_process_group_and_retains_partial_log(self):
        child = "import signal,time;signal.signal(signal.SIGINT,signal.SIG_IGN);signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(50)"
        script = ("import signal,subprocess,sys,time;signal.signal(signal.SIGINT,signal.SIG_IGN);"
                  "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                  f"p=subprocess.Popen([sys.executable,'-c',{child!r}]);print('descendant='+str(p.pid));time.sleep(50)")
        result, state = self.invoke(script, timeout=0.25)
        self.assertEqual(result.returncode, 124)
        self.assertTrue(state["timedOut"])
        self.assertEqual(state["terminationPhase"], "kill")
        self.assertEqual(state["subprocessExitCode"], -signal.SIGKILL)
        self.assertLess(state["elapsedSeconds"], 4)
        pid = int(self.log.read_text().split("descendant=")[1].splitlines()[0])
        self.assert_process_not_running(pid)

    def test_external_sigterm_stops_child_and_records_cancellation_separately(self):
        ready = self.root / "ready"
        script = f"from pathlib import Path;import time;Path({str(ready)!r}).write_text('ready');print('ready');time.sleep(50)"
        with subprocess.Popen(self.command(script), stdout=subprocess.PIPE, stderr=subprocess.PIPE) as supervisor:
            deadline = time.monotonic() + 3
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(ready.exists())
            supervisor.send_signal(signal.SIGTERM)
            supervisor.communicate(timeout=5)
            self.assertEqual(supervisor.returncode, 143)
        state = json.loads(self.status.read_text())
        self.assertEqual(state["receivedSignal"], signal.SIGTERM)
        self.assertFalse(state["timedOut"])
        self.assertEqual(state["status"], "completed")

    def test_expired_job_deadline_does_not_start_another_capture(self):
        marker = self.root / "should-not-exist"
        environment = dict(os.environ, GRILLA_TEST_DEADLINE=str(time.time() - 1))
        result = subprocess.run(self.command(f"from pathlib import Path;Path({str(marker)!r}).touch()", extra=("--deadline-env", "GRILLA_TEST_DEADLINE")), env=environment, capture_output=True, timeout=5)
        state = json.loads(self.status.read_text())
        self.assertEqual(result.returncode, 124)
        self.assertFalse(marker.exists())
        self.assertIsNone(state["subprocessExitCode"])
        self.assertEqual(state["terminationPhase"], "deadline-before-start")

    def test_missing_executable_fails_with_preserved_receipt(self):
        command = self.command("pass")
        command[command.index("--") + 1:] = [str(self.root / "missing")]
        result = subprocess.run(command, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 127)
        self.assertEqual(json.loads(self.status.read_text())["errorType"], "FileNotFoundError")

    def test_parent_exit_does_not_leave_inherited_pipe_hanging(self):
        script = "import subprocess,sys;child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(50)']);print('descendant='+str(child.pid))"
        result, state = self.invoke(script)
        self.assertEqual(result.returncode, 0)
        self.assertTrue(state["descendantCleanupRequired"])
        self.assertLess(state["elapsedSeconds"], 3)
        self.assert_process_not_running(int(self.log.read_text().split("descendant=")[1].splitlines()[0]))

    def test_zero_exit_with_missing_focused_test_cannot_claim_acceptance(self):
        result, state = self.invoke("print('Executed 0 tests, with 0 failures')", extra=("--require-test", "ActualCase/testRequested"))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(state["subprocessExitCode"], 0)
        self.assertEqual(state["requiredTestOutcomes"], {"ActualCase/testRequested": "not-observed"})

    def test_required_test_outcomes_are_observed_without_rewriting_failure(self):
        for outcome in ("passed", "failed", "skipped"):
            with self.subTest(outcome=outcome):
                line = f"Test Case '-[FixtureModule.ActualCase testRequested]' {outcome} (1.000 seconds)."
                result, state = self.invoke(f"print({line!r})", extra=("--require-test", "ActualCase/testRequested"))
                self.assertEqual(result.returncode, 0 if outcome == "passed" else 1)
                self.assertEqual(state["requiredTestOutcomes"]["ActualCase/testRequested"], outcome)

    def test_full_scope_is_only_verified_after_declared_source_inventory_passes(self):
        (self.root/"ActualCase.swift").write_text("final class ActualCase:XCTestCase {func testRequested(){}}")
        line="Test Case '-[Fixture.ActualCase testRequested]' passed (1.000 seconds)."
        result,state=self.invoke(f"print({line!r})",extra=("--scope","full","--functional-inventory",str(self.root)))
        self.assertEqual(result.returncode,0)
        self.assertTrue(state["functionalInventoryVerified"])
        self.assertEqual(state["scopeStatus"],"full-functional-pass")
        self.assertEqual(state["expectedFunctionalTests"],["ActualCase/testRequested"])

    def test_full_scope_claim_with_empty_actual_execution_fails_process_acceptance(self):
        (self.root/"ActualCase.swift").write_text("final class ActualCase:XCTestCase {func testRequested(){}}")
        result,state=self.invoke("print('Executed 0 tests, with 0 failures')",extra=("--scope","full","--functional-inventory",str(self.root)))
        self.assertEqual(result.returncode,1)
        self.assertEqual(state["subprocessExitCode"],0)
        self.assertFalse(state["functionalInventoryVerified"])
        self.assertEqual(state["scopeStatus"],"not-accepted")

    def assert_process_not_running(self, pid):
        # Linux container PID1 can leave a dead descendant briefly as a zombie;
        # it cannot execute or retain the pipe. macOS reaps it immediately.
        path = Path(f"/proc/{pid}/stat")
        if path.exists() and path.read_text().split()[2] == "Z":
            return
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        self.fail(f"Owned descendant {pid} is still running")


if __name__ == "__main__":
    unittest.main()
