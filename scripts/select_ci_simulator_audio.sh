#!/bin/bash
# Exercise Simulator's supported audio menu, not a guessed guest/app API.
# Apple documents Simulator audio input/output selection in its hardware menu:
# https://developer.apple.com/videos/play/wwdc2019/418/
# This is an ephemeral CI fixture. A checked menu item is routing evidence;
# the following native test must still receive real PCM and retain playback.
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo "Simulator audio menu selection requires macOS." >&2
  exit 1
fi
python3 - <<'PY'
import subprocess,sys

script=r'''
on showAudioMenu(topTitle, audioTitle, nestedSound)
    tell application "System Events"
        tell process "Simulator"
            click menu bar item topTitle of menu bar 1
            set parentMenu to menu 1 of menu bar item topTitle of menu bar 1
            if nestedSound then
                click menu item "Sound" of parentMenu
                set parentMenu to menu 1 of menu item "Sound" of parentMenu
            end if
            if not (exists menu item audioTitle of parentMenu) then error "Audio submenu missing: " & audioTitle
            click menu item audioTitle of parentMenu
            return menu 1 of menu item audioTitle of parentMenu
        end tell
    end tell
end showAudioMenu

on selectAndVerify(topTitle, audioTitle, nestedSound, deviceTitle)
    set deviceMenu to my showAudioMenu(topTitle, audioTitle, nestedSound)
    tell application "System Events"
        tell process "Simulator"
            log audioTitle & " entries:"
            repeat with entry in menu items of deviceMenu
                set entryTitle to name of entry
                if entryTitle is missing value then set entryTitle to "(separator)"
                set entryMark to ""
                try
                    set entryMark to value of attribute "AXMenuItemMarkChar" of entry
                end try
                if entryMark is missing value then set entryMark to ""
                log "Before: " & (entryTitle as text) & "; mark=" & (entryMark as text)
            end repeat
            if not (exists menu item deviceTitle of deviceMenu) then error "Configured host device is absent from Simulator " & audioTitle
            if not (enabled of menu item deviceTitle of deviceMenu) then error "Simulator audio device is disabled: " & deviceTitle
            click menu item deviceTitle of deviceMenu
        end tell
    end tell
    delay 0.3
    set verifiedMenu to my showAudioMenu(topTitle, audioTitle, nestedSound)
    tell application "System Events"
        tell process "Simulator"
            set selectedDeviceItem to menu item deviceTitle of verifiedMenu
            set checkedMark to value of attribute "AXMenuItemMarkChar" of selectedDeviceItem
            if checkedMark is missing value then error "Simulator did not mark the selected " & audioTitle
            if (checkedMark as text) is "" then error "Simulator did not check the selected " & audioTitle
            log "Verified " & audioTitle & ": " & deviceTitle & "; AXMenuItemMarkChar=" & (checkedMark as text)
            key code 53
            key code 53
        end tell
    end tell
end selectAndVerify

on run argv
    set deviceTitle to item 1 of argv
    tell application "System Events"
        if not (exists process "Simulator") then error "Simulator must be running before audio menu selection"
        tell process "Simulator"
            set frontmost to true
            log "Simulator windows:"
            log (name of every window)
            set menuTitles to name of every menu bar item of menu bar 1
            log "Simulator menu bar:"
            log menuTitles
        end tell
    end tell
    if menuTitles contains "I/O" then
        my selectAndVerify("I/O", "Audio Input", false, deviceTitle)
        my selectAndVerify("I/O", "Audio Output", false, deviceTitle)
    else if menuTitles contains "Hardware" then
        my selectAndVerify("Hardware", "Audio Input", false, deviceTitle)
        my selectAndVerify("Hardware", "Audio Output", false, deviceTitle)
    else if menuTitles contains "Device" then
        my selectAndVerify("Device", "Sound Input", true, deviceTitle)
        my selectAndVerify("Device", "Sound Output", true, deviceTitle)
    else
        error "Simulator has no supported audio menu layout"
    end if
    return "Actual Simulator menu input and output both checked BlackHole 2ch; native PCM still required."
end run
'''

try:
    result=subprocess.run(['/usr/bin/osascript','-','BlackHole 2ch'],input=script,text=True,
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=45)
except subprocess.TimeoutExpired as error:
    output=error.stdout or ''
    print(output.decode(errors='replace') if isinstance(output,bytes) else output,end='')
    print('Simulator audio menu selection exceeded its 45-second limit.',file=sys.stderr)
    sys.exit(124)
print(result.stdout,end='')
sys.exit(result.returncode)
PY
