# La Grilla — roadmap до App Store

Обновлено: 15 ноября 2026. Источник требований: [README](README.md), [дизайн](DESIGN_PROMPT.txt). Это рабочий план реализации, а не обещание готовности неизмеренных функций.

**Правило работы:** реализовать законченный сценарий → поведенческие тесты → native build/UI QA → реальные скриншоты в `Screenshots/<этап>/` → PR и merge в `main` → обновить этот файл и журнал проверок. По запросу владельца проверенные этапы интегрируются в `main`; проверки физического устройства остаются обязательным условием выпуска. Изменения дизайна и графику при необходимости делать через OpenArt. Скриншоты продукта — только из работающего приложения.

| Этап | Объём | Приёмка / артефакт | Статус |
| --- | --- | --- | --- |
| R0. База v0.1 | Grid, Harmony/Drums/Bass, Jam, takes, Mixer, projects, Undo, autosave/recovery, MIDI | 14 domain/storage tests + C++ + 4 native UI tests, обе SDK-сборки, 4 скриншота. [QA](docs/QA.md), [PR #1](https://github.com/alexgazin/la-grilla/pull/1) | **Слито в main** |
| R1. Переносимый результат | WAV mixdown, stems, 44.1/48 kHz, 16/24 bit, tail, диапазон; export progress/cancel; переносимый `.grillapack`, импорт копией | Файлы открываются независимым WAV/ZIP reader; mix/stem alignment, deterministic render, finite duration, cancel cleanup, project round-trip. Live transport не переключается в offline mode | **Слито в main** |
| R2. Полный нотный редактор | Melody/piano roll, до 8 дорожек, add/move/resize/delete notes, velocity, selection, copy/paste, clip/section operations, zoom/drag arbitration | Создать мелодию, изменить ноты, Undo, сохранить/открыть и услышать/экспортировать ровно те же ноты. Нет потери v1-проектов | **Слито в main** |
| R3. Гармоническая лаборатория | 9/11/13, alterations/slash bass, voicing/range/voice leading; мягкая/выразительная стилизация и reharm | Объяснимое предложение с исходными/новыми аккордами, A/B, Apply/Cancel, одна Undo-транзакция. Хроматика и ограничения видны | **Слито в main** |
| R4. Assistant | RU/EN локальные команды tempo/key/sections/progressions; dictation отдельно от напева; typed proposals, scope, assumptions, stale/double-apply guards | Команда → preview → Apply или Cancel. Нет скрытого редактирования, неподтверждённых сетевых обещаний или ключей в клиенте. Cloud provider только через защищённый backend, если понадобится | **Слито в main** |
| R5. Voice-to-MIDI | Microphone permission, headphones guidance, count-in, запись исходного mono audio, monophonic pitch/onset/confidence, quantize/scale snap, piano-roll correction/A-B | Синус/напев/пауза/шум/octave-jump набор; сомнительные ноты видны, тишина остаётся тишиной, Apply/Cancel сохраняют исходник до решения | **Слито в main** |
| R6. Perform | Quantized section launch/cancel, repeat/jump, filter/repeat FX, bounded smoothing, finite performance-take с replay/export | Отрепетировать секции → записать исполнение → воспроизвести и экспортировать тот же порядок/автоматизацию без stuck notes | **В работе** |
| R7. MIDI devices | Core MIDI USB/BLE, endpoint selection, MIDI in/out, learn/map, channel filtering, disconnect/panic | Реальный input/output и проверка unplug/sustain на USB и BLE. Bluetooth audio latency не смешивается с BLE MIDI | Запланировано |
| R8. Продуктовая полировка | Профессиональная иконка/графика через OpenArt, тёмная/светлая темы, RU/EN, Dynamic Type/VoiceOver, touch ≥44 pt, 375 pt/landscape, empty/error/recovery states | Реальные screenshots всех сценариев и размеров; audit доступности и состояния ошибок; ни одной декоративной неработающей кнопки | Запланировано |
| R9. Стабилизация | Schema migrations/import safety, bounded queues/voices, gain/pan/voice-steal fades, clipping/meter reset, interruptions/routes/background/media reset, P1/P2/P3 load fixtures | Автотесты и 30 min физический load/latency/CPU/memory отчёт, audio route/device matrix, MIDI round-trip в 2 DAW, восстановление после kill/save failure | Запланировано; физическая часть требует устройства |
| R10. Release candidate | Версии/build numbers, Release/archive CI, privacy manifest и RU/EN policy/support, licenses/provenance, store metadata, screenshots, export compliance, signing/TestFlight scripts | Воспроизводимый архив, checklist без выдуманных выполненных пунктов, установленный TestFlight build, закрытые blocker/critical defects | Запланировано; signing/account нужны для распространения |
| R11. App Store | Проверка установленного RC, App Store Connect listing/age rating/privacy, upload, review, production smoke | Доступная пользователю production-сборка и проверка установленного build | Ожидает R0–R10 и доступ Apple Developer/App Store Connect |

## Состояние и зависимости

R1 → R2 → R3 → R4; R2 и аудиосессия → R5; transport/compiler → R6 → R7. R8 и R9 сопровождают каждый этап, R10/R11 завершают выпуск. Аппаратные и внешние проверки не блокируют независимую разработку, но не могут быть отмечены выполненными по результату симулятора.

### Завершено: R1–R5

- [x] Offline renderer использует тот же compiler и DSP kernel, отдельный экземпляр, без изменения live engine.
- [x] WAV PCM stereo 44.1/48 kHz, 16/24 bit, range, release tail, progress/cancel.
- [x] Stems с общей стартовой точкой, контролируемой семантикой mute/solo/master и manifest.
- [x] Переносимый project pack, проверки schema/size/path, импорт независимой копией.
- [x] Native export/import flow, работающие кнопки, локализация, UI regression и новые screenshots.
- [x] Документированные проверки и merge R1 в `main`.

## Журнал

- **14.11.2026 — R0:** PR #1 слит в `main` (`947a177`). Подтверждены 14 Swift tests, kernel regressions/sanitizers, 4 native UI flows и SDK builds. Физический iPhone, DAW и подпись не объявляются проверенными.
- **14.11.2026 — R1:** WAV/stems/project pack реализованы; 21 Swift test, независимые WAV/ZIP readers, C++ regressions, обе SDK-сборки и 6 native UI tests проходят. Реальные изображения — `Screenshots/R1`. Следующий этап R2 уже разрабатывается отдельно.

## Условия, которые нельзя заменить кодом или макетом

Физический iPhone/наушники/USB и BLE MIDI нужны для аппаратных измерений; DAW — для фактического импорта; Apple Developer signing/App Store Connect — для TestFlight и публикации. В среде пока нет этих устройств/учётных данных. Все независимые программные этапы продолжаются; доступ запрашивается только когда соответствующий конкретный результат готов к этой внешней проверке/публикации.

- **15.11.2026 — R2:** piano roll, melody, 8 каналов и schema migration реализованы; 28 Swift tests, C++ routing, обе SDK-сборки и 8 native UI tests проходят. Реальные экраны — `Screenshots/R2`.

- **15.11.2026 — R3:** 9/11/13, altered/slash chords, bounded voicings, voice leading, scoped reharm и A/B реализованы. 35 Swift tests, C++ restart regression, обе SDK-сборки и 9 native UI tests проходят. Экраны — `Screenshots/R3`.

- **15.11.2026 — R4:** RU/EN local Assistant, проверяемые предложения, выбор длительностей, A/B и одна Undo-транзакция реализованы. 42 Swift tests, обе SDK-сборки и 11 native UI tests проходят; `Screenshots/R4`. On-device Speech adapter собран, реальная диктовка требует физического устройства/доступной модели.

- **15.11.2026 — R5:** mono recording/count-in, original/instrument review, YIN/autocorrelation comparison, confidence/correction, quantize/scale, source-preserving packages и schema v4 реализованы. 54 Swift tests, независимый CAF/SHA-256/ZIP reader, обе SDK-сборки и 12 native UI tests проходят. 15 экранов — `Screenshots/R5`; реальный напев остаётся beta/device gate.
