# Reproducible host-only baseline measurements

Run `bash /tmp/grilla-architecture-profile/run.sh /workspace/la-grilla-audit-actions`.

The script freezes MusicDomain and both load fixtures from commit `29adf6c398173faf830de8f6249702628b8a3f76` through `git archive`. It does not edit the repository. The executable is built with `swift run -c release` and uses existing production `Project.validate`, `Compiler.notes`, `History.apply` and actor `ProjectStore` APIs.

Default compiler: Swift 6.1.2, x86_64 Linux. Override `GRILLA_SWIFT_BIN` to choose an installed toolchain; the checked receipt runtime string identifies the measured baseline compiler. There are 15 measured repetitions after one warmup for each direct operation and 5 list repetitions after one separate, timed warmup. Each library's save/setup time is separate from list timing. Libraries are removed after the executable finishes.

`receipt.json` preserves raw durations and nearest-rank percentile summaries. Setup creates 10 or 50 independent project IDs and valid on-disk manifests. Each list result must load every project without an error. Fixtures must compile to exactly 768 (P1) and 16,384 (P3) notes. A History measurement begins from a fresh project value and History for each sample, then performs a real mix or drum-note velocity change including production validation.

This measures warm filesystem cache and the domain/storage code in a Linux process. It excludes SwiftUI, Session.sync, AVAudioEngine, rendering deadlines, iPhone memory/temperature, touch latency and physical dropouts. Times cannot establish iPhone readiness or its regression budgets. Concurrent work elsewhere on the host can add scheduling variation.

`provenance.json` records exact harness/fixture/source hashes, toolchain output and host metadata for the captured result. The initial attempt against the shared worktree failed with SwiftPM's "input file ProjectStore.swift was modified during the build"; no metrics from that attempt are accepted. The successful result uses the immutable baseline above.
