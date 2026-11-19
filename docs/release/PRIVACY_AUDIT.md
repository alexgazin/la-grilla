# Privacy and content audit

The app contains no network client, account flow, advertising or telemetry SDK. SwiftPM dependencies are the two local MusicDomain/AudioDSP products. Store privacy answers: **Data Not Collected**, no tracking. This describes the app, not GitHub or a provider the user selects in the system share sheet.

`Resources/PrivacyInfo.xcprivacy` is copied into the app and archive:

| Required-reason API | Use | Declared reason |
| --- | --- | --- |
| UserDefaults / SwiftUI AppStorage | User-selected appearance in this app | CA92.1 |
| System boot time / mach_absolute_time | Audio/MIDI timestamp alignment and elapsed intervals within the app | 35F9.1 |

File size checks read sizes, not creation/modification timestamps or disk capacity. Project dates are app-authored model fields. No file timestamp, available disk space, active keyboard or fingerprinting API is used. Re-audit this table whenever dependencies or APIs change; Apple maintains the authoritative required-reason list.

Microphone, Speech and Bluetooth purpose strings are present in English and Russian. Speech requests set `requiresOnDeviceRecognition = true` and reject unsupported models; server fallback is absent. Source voice assets stay local and are deliberately included in portable project exports. There are no push, contacts, photos, location or advertising permissions. Background audio is limited to explicit playback; the idle graph stops when backgrounded.

On iOS 26, the optional generative Assistant uses Apple's Foundation Models framework and `SystemLanguageModel.default` on the device. Device eligibility, model readiness and the selected language are checked before generation. No prompt, project, voice recording or generated response is uploaded by the app; no cloud provider, API credential or analytics client is included. Unsupported devices retain the explicitly labelled Commands mode. A single shared input tap captures voice/dictation over explicit playback; monitoring is off and the tap is removed on stop, cancellation, interruption or backgrounding.

**Build 46 re-audit.** Edits described in words (`SongEditParser`/`SongEditor`) run entirely in local Swift code on the device; no text leaves the app and no model is required. Palettes use the app's own on-device drum generator and built-in synthesized timbres; loudness matching renders offline into a temporary file that is deleted afterwards. MIDI file import reads only the file the user picks in the system document picker; no new entitlement, permission or purpose string was added. Required-reason APIs are unchanged (`systemUptime` for tap tempo falls under the existing 35F9.1 elapsed-interval reason). Store privacy answers remain **Data Not Collected**.

`ITSAppUsesNonExemptEncryption = false`: the app implements no non-exempt encryption. SHA-256 asset integrity is a hash, not encryption. System-provided security is used by iOS.

All drum/instrument audio is synthesized by project code; no sample pack or third-party music is bundled. The OpenArt icon's source, generation record and transformation are in `Design/OpenArt`, `Design/2026` and `Design/README.md`. No OpenArt SDK is embedded. Apple's frameworks and SF Symbols retain Apple's terms. This repository has no granted third-party code dependency requiring an additional license notice. No repository-wide open-source license is inferred or added.

App Store content questionnaire: no user-generated public content, messaging, browsing, gambling, contests, purchases, ads, medical claims, violence or mature content. Answer the current questionnaire against the actual binary; Apple determines the resulting age rating. The app allows users to record their own audio locally, not publish a social feed.
