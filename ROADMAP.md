# La Grilla — roadmap до App Store

Обновлено: 15 ноября 2026. Источник требований: [README](README.md), [дизайн](DESIGN_PROMPT.txt). Это рабочий план реализации, а не обещание готовности неизмеренных функций.

**Правило работы:** реализовать законченный сценарий → поведенческие тесты → native build/UI QA → реальные скриншоты в `Screenshots/<этап>/` → PR и merge в `main` → обновить этот файл и журнал проверок. По запросу владельца проверенные этапы интегрируются в `main`; проверки физического устройства остаются обязательным условием выпуска. Изменения дизайна и графику при необходимости делать через OpenArt. Скриншоты продукта — только из работающего приложения.

## Завершение исходного видения — C0–C8

Сверка с первоначальными идеями выявила функциональные пробелы поверх выполненного MVP: свободный AI/многосекционные предложения, полноценные clip/section жесты, непрерывные структурные правки и duplex voice, практическое расширение гармонии/формулы и круговой DJ-фильтр. Прежнее завершение R0–R10 **не закрывает эти расширения**.

Подробная техчасть, зависимости, тесты и приёмка каждого этапа: [план C0–C8](docs/ORIGINAL_VISION_COMPLETION.md). Фактические результаты: [журнал реализации](docs/IMPLEMENTATION_LOG.md).

| Этап | Что сделать | Статус |
| --- | --- | --- |
| C0 | Полная сверка, технические контракты и журнал | План записан; реализация начата |
| C1 | Джазовый каталог, пользовательские формулы, voicings, schema 8 | Реализовано: 65 качеств и формулы; host и отдельные native сценарии прошли; общая C7 приёмка впереди |
| C2 | Настоящий круговой live-фильтр и доступность | Native приёмка пройдена; [55 кадров и receipt](Screenshots/C2) |
| C3 | Move/copy/resize клипов, совместимые drop, section drag, clip-specific piano roll | Реализовано; все 5 native arrangement сценариев прошли в 43733352465; финальная регрессия впереди |
| C4 | Атомарный music/mix/preset snapshot; live add/remove/reorder и фазовое A/B без Stop | Реализовано; kernel/MIDI, native live edits и настоящий drum overdub прошли; расширенная проверка audition ожидает C7 |
| C5 | Общий duplex input, напев/диктовка поверх бита, bounded capture и cleanup | Focused native cold/warm CAF→analysis→review→Apply/store/reopen/UndoRedo прошли (43748050176); render timestamp gaps измерены, physical output/indicator/живой голос остаются C8 |
| C6 | Реальный AI provider, естественные команды/«поджазовать», whole-song review/Apply/Undo | FoundationModels adapter и Commands реализованы; native review/Apply/Undo прошли; реальная модель/язык проверяются в C8 |
| C7 | Интеграционная QA, совместимость, новый RC и реальные кадры | Кандидат 1.0.0 (14), schema 8; 115 Swift/18 suites,15 C++ и603 EN/RU keys проходят; полный native43/captures73, визуальная приёмка и merge впереди |
| C8 | Устройства/реальные модели/голоса, signing, TestFlight и App Review | Внешняя приёмка открыта |

Последний принятый `main` — `912dc483`, **1.0.0 (13)**, exact-main run `43719321757`. Расширения кандидата 14 находятся в [PR #13](https://github.com/alexgazin/la-grilla/pull/13). Focused C5 cold playback→consent→complete capture в одном процессе прошёл; источник/фаза не выданы за gapless physical audio. Частичные прогоны и шесть [промежуточных оригинальных кадров](Screenshots/OriginalVision-progress) не являются финальной приёмкой; RU Duration bug в одном кадре сохранён и исправляется с общей dynamic-localization регрессией. Следующая цепочка: полный native run и свежая коллекция кадров → merge → проверки точного `main` → C8.

## История выполненных базовых этапов

| Этап | Объём | Приёмка / артефакт | Статус |
| --- | --- | --- | --- |
| R0. База v0.1 | Grid, Harmony/Drums/Bass, Jam, takes, Mixer, projects, Undo, autosave/recovery, MIDI | 14 domain/storage tests + C++ + 4 native UI tests, обе SDK-сборки, 4 скриншота. [QA](docs/QA.md), [PR #1](https://github.com/alexgazin/la-grilla/pull/1) | **Слито в main** |
| R1. Переносимый результат | WAV mixdown, stems, 44.1/48 kHz, 16/24 bit, tail, диапазон; export progress/cancel; переносимый `.grillapack`, импорт копией | Файлы открываются независимым WAV/ZIP reader; mix/stem alignment, deterministic render, finite duration, cancel cleanup, project round-trip. Live transport не переключается в offline mode | **Слито в main** |
| R2. Полный нотный редактор | Melody/piano roll, до 8 дорожек, add/move/resize/delete notes, velocity, selection, copy/paste, clip/section operations, zoom/drag arbitration | Создать мелодию, изменить ноты, Undo, сохранить/открыть и услышать/экспортировать ровно те же ноты. Нет потери v1-проектов | **Слито в main** |
| R3. Гармоническая лаборатория | 9/11/13, alterations/slash bass, voicing/range/voice leading; мягкая/выразительная стилизация и reharm | Объяснимое предложение с исходными/новыми аккордами, A/B, Apply/Cancel, одна Undo-транзакция. Хроматика и ограничения видны | **Слито в main** |
| R4. Assistant | RU/EN локальные команды tempo/key/sections/progressions; dictation отдельно от напева; typed proposals, scope, assumptions, stale/double-apply guards | Команда → preview → Apply или Cancel. Нет скрытого редактирования, неподтверждённых сетевых обещаний или ключей в клиенте. Cloud provider только через защищённый backend, если понадобится | **Слито в main** |
| R5. Voice-to-MIDI | Microphone permission, headphones guidance, count-in, запись исходного mono audio, monophonic pitch/onset/confidence, quantize/scale snap, piano-roll correction/A-B | Синус/напев/пауза/шум/octave-jump набор; сомнительные ноты видны, тишина остаётся тишиной, Apply/Cancel сохраняют исходник до решения | **Слито в main** |
| R6. Perform | Quantized section launch/cancel, repeat/jump, filter/repeat FX, bounded smoothing, finite performance-take с replay/export | Отрепетировать секции → записать исполнение → воспроизвести и экспортировать тот же порядок/автоматизацию без stuck notes | **Слито в main** |
| R7. MIDI devices | Core MIDI USB/BLE, endpoint selection, MIDI in/out, learn/map, channel filtering, disconnect/panic | Реальный input/output и проверка unplug/sustain на USB и BLE. Bluetooth audio latency не смешивается с BLE MIDI | **Слито в main; аппаратная проверка открыта** |
| R8. Продуктовая полировка | Профессиональная иконка/графика через OpenArt, тёмная/светлая темы, RU/EN, Dynamic Type/VoiceOver, touch ≥44 pt, 375 pt/landscape, empty/error/recovery states | Реальные screenshots всех сценариев и размеров; audit доступности и состояния ошибок; ни одной декоративной неработающей кнопки | **Слито в main** |
| R8.1. Дизайн 2026 | Самостоятельное направление через OpenArt; узнаваемая музыкальная сетка, типографика и цвет; упрощённые Harmony/Perform, компактные основные действия и единые компоненты во всех режимах | Реализованный SwiftUI-интерфейс; реальные EN/RU, light/dark, 375 pt и landscape кадры; 44 pt targets, AA, Dynamic Type/VoiceOver, рабочие сценарии и обновлённый Store-набор | **Программная реализация и QA готовы; [PR #12](https://github.com/alexgazin/la-grilla/pull/12). Физическая доступность остаётся открытой** |
| R9. Стабилизация | Schema migrations/import safety, bounded queues/voices, gain/pan/voice-steal fades, clipping/meter reset, interruptions/routes/background/media reset, P1/P2/P3 load fixtures | Автотесты и 30 min физический load/latency/CPU/memory отчёт, audio route/device matrix, MIDI round-trip в 2 DAW, восстановление после kill/save failure | **Слито в main; software QA пройдена, физическая часть открыта** |
| R10. Release candidate | Версии/build numbers, Release/archive CI, privacy manifest и RU/EN policy/support, licenses/provenance, store metadata, screenshots, export compliance, signing/TestFlight scripts | Воспроизводимый архив, checklist без выдуманных выполненных пунктов, установленный TestFlight build, закрытые blocker/critical defects | **Кандидат 1.0.0 (12) и software QA готовы; signing/TestFlight и device QA открыты** |
| R11. App Store | Проверка установленного RC, App Store Connect listing/age rating/privacy, upload, review, production smoke | Доступная пользователю production-сборка и проверка установленного build | Ожидает установленный проверенный RC и Apple Developer/App Store Connect |

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

- **15.11.2026 — R6:** quantized launch/cancel, beat jump/repeat, filter/delay, runtime mixer, finite frozen-source take, replay и WAV/MIDI export реализованы. 60 Swift tests, 3 C++ suites, независимый PCM/SMF reader, обе SDK-сборки и все 14 native UI flows проходят. 18 реальных экранов — `Screenshots/R6`. MIDI-устройства и продуктовая полировка разрабатываются отдельно.

- **15.11.2026 — R7:** Core MIDI input/output, endpoint/channel selection, sustain, CC Learn, finite input capture и emergency Panic реализованы. 62 Swift tests, 6 C++ suites, обе SDK-сборки, 15 native UI flows и захват 20 экранов проходят: run `43680458783`, app source `223615f`. Физические USB/BLE и DAW остаются релизными воротами.

- **15.11.2026 — R8:** светлая/тёмная темы, OpenArt icon/provenance, RU/EN и доступные/компактные/landscape layouts реализованы. Source `595d4a3`, run `43682961615`: 62 Swift, 6 C++ suites, обе SDK-сборки и 18 native UI flows проходят. Три новых QA-кадра — `Screenshots/R8`.

- **15.11.2026 — R9:** schema 7/versioned instruments, atomic mixer, incremental repeat, voice tails, microphone ownership, background/system transport и recovery hardening реализованы. Source `cd2ae56`, run `43681942977`: 64 Swift, 11 C++ suites, обе SDK-сборки, 19 Studio flows и два capture tests проходят. 36 original PNGs — `Screenshots/R9`; импортируемые P1/P2/P3 — `docs/release/fixtures`.

- **15.11.2026 — R10:** технический кандидат 1.0.0 (11), текущая цепочка Xcode 26.3 / iOS 26.2, privacy/store/support и signing/TestFlight automation подготовлены. Source `ecfc9b9`, run `43689852307`: 64 Swift, 11 C++ suites, обе SDK-сборки, 19 Studio flows, RU Pro Max/SE captures и Release-архив проходят. Исправлены MIDI boundary routing/Off-before-On, 13 пропущенных переводов и Master/quantize labels. Сохранены 51 native PNG с source/hash и 12 Store-копий. Подпись, физические измерения и публикация не выполнены.

- **15.11.2026 — R8.1:** новый дизайн реализован во всех режимах: сетка и курсор как фирменный мотив, графит/лайм и цветовые роли партий, единые поверхности/типографика, компактный транспорт, Harmony A/B/Apply, живой Perform, Jam и адаптивный Mixer. OpenArt-направление и иконка сохранены с provenance. Исправлены пустая область нажатия строки подсказки и настоящие 44 pt кнопки Pads/Steps. Source `d63be9e`, [run 43699657512](https://github.com/alexgazin/la-grilla/actions/runs/43699657512): 64 Swift, 11 C++ suites, обе SDK-сборки, архив и все 19 Studio flows проходят. [Run 43700109621](https://github.com/alexgazin/la-grilla/actions/runs/43700109621) повторно подтверждает 19 сценариев и шесть EN/RU compact-кадров. Полная визуальная приёмка и источники кадров — [Design QA](docs/DESIGN_QA.md); интеграция — [PR #12](https://github.com/alexgazin/la-grilla/pull/12). Подпись, физические измерения, TestFlight и App Review остаются открытыми воротами.

  **Финальная визуальная приёмка R8.1:** source `72d81cb`, [run 43700372709](https://github.com/alexgazin/la-grilla/actions/runs/43700372709) полностью проходит: 64 Swift, 11 C++ suites, обе SDK-сборки/архив и 22 native tests (19 сценариев + три захвата). Сохранены [54 оригинальных кадра](Screenshots/Design2026) и [12 неизменённых Store-копий](Screenshots/AppStore) с source/run/размерами/SHA-256. Корневые превью обновлены; прежние четыре кадра сохранены в R0.
