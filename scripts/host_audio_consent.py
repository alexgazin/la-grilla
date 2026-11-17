#!/usr/bin/env python3
"""Observe and accept only the normal virtual-recorder consent prompt."""
import json
from pathlib import Path
import subprocess
import time

TARGET_PROCESSES = ['UserNotificationCenter', 'CoreServicesUIAgent', 'SecurityAgent', 'LaGrillaDemoAudioRecorder']

CONSENT_SCRIPT = r'''on run argv
set targetName to item 1 of argv
set report to "PROCESS " & targetName & linefeed
tell application "System Events"
 if not (exists application process targetName) then return report & "ABSENT"
 tell application process targetName
  set report to report & "WINDOWS " & (count of windows) & linefeed
  repeat with aWindow in windows
   set joinedText to ""
   try
    set joinedText to name of aWindow as text
   end try
   set controls to entire contents of aWindow
   repeat with aControl in controls
    try
     if role of aControl is "AXStaticText" then
      set joinedText to joinedText & " " & (value of aControl as text)
     end if
    end try
   end repeat
   set report to report & "TEXT " & joinedText & linefeed
   set expectedName to joinedText contains "La Grilla Demo Audio Recorder" or joinedText contains "LaGrillaDemoAudioRecorder"
   if expectedName and joinedText contains "microphone" then
    repeat with aControl in controls
     try
      if role of aControl is "AXButton" then
       set buttonName to name of aControl as text
       set report to report & "BUTTON " & buttonName & linefeed
       if buttonName is "Allow" or buttonName is "OK" then
        perform action "AXPress" of aControl
        return report & "ACCEPTED_EXPECTED_NORMAL_MICROPHONE_PROMPT"
       end if
      end if
     end try
    end repeat
   end if
  end repeat
 end tell
end tell
return report
end run'''


def _probe_process(name):
    started = time.monotonic()
    try:
        result = subprocess.run(['osascript', '-e', CONSENT_SCRIPT, name], capture_output=True, text=True, timeout=5)
        return dict(process=name, request_elapsed_seconds=time.monotonic()-started, exit_code=result.returncode,
                    stdout=result.stdout, stderr=result.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(process=name, request_elapsed_seconds=time.monotonic()-started, error='timeout',
                    stdout=str(error.stdout or ''), stderr=str(error.stderr or ''))


def _screenshot(output, phase):
    path = output / f'host-consent-{phase}.png'
    try:
        result = subprocess.run(['/usr/sbin/screencapture', '-x', str(path)], capture_output=True, text=True, timeout=5)
        return dict(action='desktop-screenshot', phase=phase, exit_code=result.returncode,
                    path=path.name, exists=path.exists(), stdout=result.stdout, stderr=result.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(action='desktop-screenshot', phase=phase, error='timeout', stderr=str(error.stderr or ''))


def wait_for_audio_ready(output: Path, process: subprocess.Popen, timeout: float = 75):
    """No privacy resets/DB writes, no alternate app identity or offline audio."""
    output.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    captures = set()
    accepted_prompt = False
    transcript = output / 'host-consent-observations.jsonl'
    def log(value):
        value.update(elapsed=time.monotonic()-start, uptime=time.monotonic())
        with transcript.open('a') as handle:
            handle.write(json.dumps(value, sort_keys=True)+'\n')
        if 'ACCEPTED_EXPECTED_NORMAL_MICROPHONE_PROMPT' in value.get('stdout', ''):
            print('Accepted the expected recorder’s ordinary macOS microphone prompt.', flush=True)
    # A fresh, already authorized recorder can supply actual PCM while AX is
    # busy. Its ready file takes priority over this optional desktop diagnostic.
    if not (output / 'ready.json').exists():
        try:
            names = subprocess.run(['osascript', '-e', 'tell application "System Events" to get name of every application process'], capture_output=True, text=True, timeout=5)
            log(dict(action='process-list', exit_code=names.returncode, stdout=names.stdout, stderr=names.stderr))
        except subprocess.TimeoutExpired as error:
            def decoded(value):
                return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
            log(dict(action='process-list', error='timeout', timeout_seconds=5,
                     stdout=decoded(error.stdout), stderr=decoded(error.stderr)))
    while not (output / 'ready.json').exists():
        elapsed = time.monotonic()-start
        for threshold in [10, 25]:
            if elapsed >= threshold and threshold not in captures:
                captures.add(threshold);log(_screenshot(output, f'{threshold}s'))
        if process.poll() is not None or elapsed >= timeout:
            log(_screenshot(output, 'failure'))
            raise RuntimeError('Normal host capture did not become ready; inspect helper.log, failure.json, AX observations and desktop screenshots.')
        # These Apple events share one System Events/AX server. Query known
        # hosts in priority order; after Allow, wait only for actual PCM ready.
        if not accepted_prompt:
            for name in TARGET_PROCESSES:
                if (output / 'ready.json').exists() or process.poll() is not None or time.monotonic()-start >= timeout:
                    break
                observation = _probe_process(name)
                log(observation)
                if 'ACCEPTED_EXPECTED_NORMAL_MICROPHONE_PROMPT' in observation.get('stdout', ''):
                    accepted_prompt = True
                    break
        time.sleep(0.25)
    if process.poll() is not None:
        raise RuntimeError('The actual recorder ended before ongoing PCM readiness could be accepted.')
    log(dict(action='actual-timestamped-pcm-ready', ready=json.loads((output/'ready.json').read_text())))
