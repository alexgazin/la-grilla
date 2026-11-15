#!/usr/bin/env python3
"""Apple has required Xcode 26 / iOS 26 SDK since April 28, 2026."""
import subprocess
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-version'],text=True).strip()
assert int(sdk.split('.')[0])>=26,f'App Store submission requires iOS 26 SDK or newer; selected SDK is {sdk}. Select Xcode 26 or newer.'
print(subprocess.check_output(['xcodebuild','-version'],text=True).strip())
print('App Store SDK requirement passed: iPhoneOS '+sdk)
