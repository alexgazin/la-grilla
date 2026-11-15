# Physical release acceptance record

**Status: not measured.** This environment has no connected physical iPhone, USB/BLE controller, two DAWs or Apple signing account. Simulator and host benchmarks must not be entered as hardware results.

Copy this record per tested release candidate. Keep the source SHA, version/build and installed TestFlight build identifier together.

| Field | Recorded result |
| --- | --- |
| Source SHA / installed build | Pending |
| iPhone / iOS / audio route / interface firmware | Pending |
| MIDI controller / firmware / USB or BLE | Pending |
| DAW 1 / DAW 2 / versions | Pending |
| 30-minute P1/P2/P3 CPU, memory, thermal and dropout observations | Pending |
| Touch-to-sound measurement method, median/p95 and route latency | Pending |
| MIDI timestamp/reference method, median/p95 and stuck-note checks | Pending |
| Screen lock/background/remote Stop; unplug/call/Siri/media reset | Pending |
| Microphone denied/revoked, local speech unavailable, count-in cancel | Pending |
| Save/kill/reopen, backup recovery and full-storage behavior | Pending |
| VoiceOver / Dynamic Type / language / orientation | Pending |
| MIDI/WAV/stem/project imports; source audio retained | Pending |
| Defects / evidence links / tester / date | Pending |

P1: 3 tracks / sparse 64 bars. P2: 8 tracks / 8,192 events. P3: 8 tracks / 16,384 events, live pads, filter/delay and repeated section/transport actions. Use the real instrument/mix presets and export/import the same project between tests. Keep audio recordings or Instruments traces where they substantiate timing or dropout claims. Repeat failed cases after fixes on the new build.
