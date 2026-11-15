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
import subprocess,sys,time

script=r'''
on waitForDeviceItem(deviceMenu, audioTitle, deviceTitle)
    set readyDeadline to (current date) + 8
    tell application "System Events"
        tell process "Simulator"
            repeat
                if exists menu item deviceTitle of deviceMenu then return
                if (current date) is greater than or equal to readyDeadline then exit repeat
                delay 0.2
            end repeat
        end tell
    end tell
    log "Timed out waiting for populated " & audioTitle & " menu containing " & deviceTitle
end waitForDeviceItem

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
    my waitForDeviceItem(deviceMenu, audioTitle, deviceTitle)
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
    my waitForDeviceItem(verifiedMenu, audioTitle, deviceTitle)
    tell application "System Events"
        tell process "Simulator"
            set selectedDeviceItem to menu item deviceTitle of verifiedMenu
            set checkedMark to ""
            set markDeadline to (current date) + 5
            repeat
                try
                    set checkedMark to value of attribute "AXMenuItemMarkChar" of selectedDeviceItem
                end try
                if checkedMark is missing value then set checkedMark to ""
                if (checkedMark as text) is not "" then exit repeat
                if (current date) is greater than or equal to markDeadline then error "Simulator did not check the selected " & audioTitle
                delay 0.2
            end repeat
            log "Verified " & audioTitle & ": " & deviceTitle & "; AXMenuItemMarkChar=" & (checkedMark as text)
            key code 53
            key code 53
        end tell
    end tell
end selectAndVerify

on run argv
    set deviceTitle to item 1 of argv
    set expectedWindowTitle to item 2 of argv
    tell application "System Events"
        if not (exists process "Simulator") then error "Simulator must be running before audio menu selection"
        tell process "Simulator"
            set frontmost to true
            -- A booted guest can precede its accessible device window. Retry
            -- this whole script if System Events still cannot expose that UI.
            set windowDeadline to (current date) + 12
            set targetWindow to missing value
            repeat
                repeat with candidateWindow in windows
                    set candidateTitle to get name of candidateWindow
                    if candidateTitle is not missing value then
                        if (candidateTitle as text) contains expectedWindowTitle then set targetWindow to candidateWindow
                    end if
                end repeat
                if targetWindow is not missing value then exit repeat
                if (current date) is greater than or equal to windowDeadline then error "Simulator has no named window for the booted target: " & expectedWindowTitle
                delay 0.2
            end repeat
            try
                perform action "AXRaise" of targetWindow
            end try
            key code 53
            key code 53
            set windowNames to get name of every window
            log "Simulator windows:"
            log windowNames
            set menuTitles to get name of every menu bar item of menu bar 1
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

# Freshly booted hosted VMs can expose empty AX submenus before their contents
# arrive. Every attempt still selects the real device and requires both marks;
# retries never convert missing menu evidence into a successful route receipt.
last_status=1
began=time.monotonic()
for attempt in range(1,4):
    print(f'Simulator audio menu attempt {attempt}/3 (elapsed {time.monotonic()-began:.1f}s).',flush=True)
    try:
        result=subprocess.run(['/usr/bin/osascript','-','BlackHole 2ch','iPhone 16 Pro Max'],input=script,text=True,
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=45)
        print(result.stdout,end='',flush=True)
        last_status=result.returncode
        if last_status==0:
            print(f'Simulator audio menu routing verified after {time.monotonic()-began:.1f}s.',flush=True)
            sys.exit(0)
    except subprocess.TimeoutExpired as error:
        output=error.stdout or ''
        print(output.decode(errors='replace') if isinstance(output,bytes) else output,end='',flush=True)
        print(f'Simulator audio menu attempt {attempt} exceeded its 45-second limit.',file=sys.stderr,flush=True)
        last_status=124
    if attempt<3:
        print('Retrying actual Simulator menu population and checked-device verification.',flush=True)
        time.sleep(1)
print('Simulator did not verify both BlackHole input/output checkmarks within three bounded attempts.',file=sys.stderr,flush=True)
sys.exit(last_status)
PY
