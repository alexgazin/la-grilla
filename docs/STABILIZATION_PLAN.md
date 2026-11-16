# La Grilla — техническая передача этапов стабилизации и выпуска

Срез: 16 ноября 2026, кандидат **1.0.0 (16), schema 8**. Продуктовое направление и конкуренты — в [ROADMAP](../ROADMAP.md); фактические проверки — в [журнале](IMPLEMENTATION_LOG.md). Этот документ задаёт следующую инженерную работу и условия её приёмки.

## Текущее подтверждение и границы

- Source `27cbf09`: реализованы output-only startup для устройства, безопасная доставка Speech callbacks, независимые от звука проекты и явный LOCAL fallback помощника; **634 EN/RU ключа**.
- [Recovery run 43845748716](https://github.com/alexgazin/la-grilla/actions/runs/43845748716), job `133236522462`: исходные **8 native methods PASS / 0 failures / 0 skips**, 300.179 s. Это Simulator/host-PCM проверка; разрешённое отсутствие Speech-модели не является успешной транскрипцией голоса.
- Source `01fb8b7`: расширены focused scope до **10** методов и full inventory до **51 functional + 1 diagnostic**. Эти новые результаты пока ожидаются и не наследуют PASS восьми методов.
- Первый владелец сообщил об аудиоошибке `2003329396` (`what`), вылете диктовки и проблемах проектов/доступности ИИ. Точные iPhone, iOS, установленный build и crash stack не зафиксированы.
- Физическое устранение симптомов, качество живого голоса/модели и C8 остаются открытыми. Сохранённые неуспешные проверки `main 224e248` не переписываются как успешные.
- Сборка/архив, исполненный UI-тест, модельная fixture, реальный пользовательский голос и измерение телефона имеют отдельные поля происхождения.

## Порядок и общий контракт

Этап 0 → этап 1 → голос/модель этапа 2 → аппаратная beta этапа 4 → выпуск этапа 5. Полировка существующего исполнения из этапа 3 может идти параллельно после стабилизации ядра. Новый MIDI-генератор получает отдельный объём и приёмку.

Для каждой задачи фиксировать: входной source/build → воспроизводимый сбой → изменённый контракт → проверки → оставшиеся ограничения → принятые артефакты. Приёмка относится к точному исходнику и установленному бинарнику, когда этого требует сценарий.

## Этап 0 — устранить P0 первого запуска на телефоне

**Зависимость:** текущий кандидат 16. **Состояние:** программный пакет подготовлен; физический retest открыт.

**Код:** [AudioController](../AudioRuntime/AudioController.swift), [LiveMicrophone](../AudioRuntime/LiveMicrophone.swift), [DictationController](../AudioRuntime/DictationController.swift), [Session](../App/Session.swift), [ProjectsView](../Features/ProjectsView.swift), [DeviceRecoveryTests](../UITests/DeviceRecoveryTests.swift).

**Работа:**

- Подтвердить playback-only порядок подготовки на устройстве, фактические output sample rate/channel format и восстановление того же графа/ядра после смены маршрута.
- Проверить Speech authorization и recognition callbacks вне неявного MainActor, отмену устаревших задач и однократное завершение запроса/PCM drain.
- Подтвердить сохранение/создание/открытие проекта при неработающем аудио, атомарное переключение документа и защиту от двойного Create.
- Оставить поддерживаемые Commands доступными при выключенной/неготовой модели; показывать реальное происхождение предложения и объяснять пустой проект.
- Сохранить диагностический stage/code/format/route без автоматической отправки записей и без подстановки фиктивного PCM.

**Проверки и gate:**

- Завершить текущие 10 focused cases и полный inventory; каждый неожиданный FAIL/SKIP имеет отдельное решение, существующий opt-in diagnostic отмечается явно.
- Повторить на установленном кандидате cold launch → Play → Pads → Dictate с разрешением/отказом → create/edit/save/reopen/export; нет вылетов и потери работы.
- Launch/Play не запрашивают микрофон; аудиосбой даёт восстановимый Retry и не создаёт дублирующую блокирующую модальную ошибку.

**Артефакты:** `xcresult`, оригинальные attachments/PCM receipts, source/build, диагностический отчёт и отдельная запись физического retest в [DEVICE_ACCEPTANCE](release/DEVICE_ACCEPTANCE.md). QA fault injection маркируется как injection, а не как аппаратное измерение.

## Этап 1 — закрепить основной музыкальный маршрут

**Зависимость:** этап 0. **Объём:** существующая студия; новые способы генерации сюда не входят.

**Код:** [GridView](../Features/GridView.swift), [ArrangementClipControl](../Features/ArrangementClipControl.swift), [JamView](../Features/JamView.swift), [PianoRollView](../Features/PianoRollView.swift), [MixerView](../Features/MixerView.swift), [ProjectStore](../Packages/MusicDomain/Sources/MusicDomain/ProjectStore.swift), [ProjectArchive](../Packages/MusicDomain/Sources/MusicDomain/ProjectArchive.swift).

**Работа:**

- Стабилизировать маршрут: проект → четыре такта аккордов → бит → бас/мелодия → куплет/припев → баланс → сохранённое исполнение → reopen → MIDI/WAV в DAW.
- Проверить транзакции Undo/Redo, resize/copy/move клипов и секций, сохранение музыкального положения при pinch, выбор правильного track/clip после удаления.
- Проверить debounce/checkpoint, kill/reopen, backup recovery, import независимой копией, нехватку хранилища и сохранение исходных voice assets.
- Довести loading/empty/error состояния; пустая партия не обещает звук до добавления нот/паттерна. UI показывает такты/доли и музыкальные длительности; PPQ/ticks остаются в domain/диагностике.
- Сверить RU/EN, Light/Dark, 44 pt touch targets, контраст, Dynamic Type, VoiceOver, Reduce Motion, компактный и горизонтальный экран.

**Проверки и gate:**

- Один сохранённый проект имеет совпадающие ноты/темп/структуру до закрытия, после открытия и в независимом чтении MIDI/WAV; Undo отменяет ровно заявленную музыкальную операцию.
- Реальные жесты не заменяются координатной инъекцией результата; отчёт показывает входной жест, геометрию и музыкальную точку после него.
- Основной маршрут повторяем на заявленной матрице; открытых P0/P1 нет. Accessibility/locale вывод относится к просмотренным состояниям, а не только к наличию strings.

**Артефакты:** минимальные воспроизводимые проекты, результаты domain/native tests, импортированные файлы, original PNG и manifest с source/run/SHA. Существующие исторические кадры сохраняют собственные источники.

## Этап 2 — голос и помощник с измеренными границами

**Зависимость:** стабильные audio/store/history из этапов 0–1. Диктовка текста и Voice-to-MIDI принимаются отдельно.

**Код:** [DictationController](../AudioRuntime/DictationController.swift), [VoiceCaptureController](../AudioRuntime/VoiceCaptureController.swift), [VoiceAnalyzer](../Packages/MusicDomain/Sources/MusicDomain/VoiceAnalyzer.swift), [VoiceCapturePlan](../Packages/MusicDomain/Sources/MusicDomain/VoiceCapturePlan.swift), [VoicePlacement](../Packages/MusicDomain/Sources/MusicDomain/VoicePlacement.swift), [AIComposerController](../AudioRuntime/AIComposerController.swift), [AssistantView](../Features/AssistantView.swift).

**Работа:**

- Пройти реальные Speech allowed/denied/revoked, доступность локальной языковой модели, Cancel/timeout/background/interruption и повторный старт без зависшего lease.
- Для живого монофонического напева подготовить эталонные pitch/onset/duration, сохранить оригинальный take и проверить placement под текущие BPM/section/loop границы.
- До измерений зафиксировать критерии pitch/onset/false positives и coverage; считать ошибки октав, шум/тишину и объём ручных коррекций, сохраняя границы beta.
- На eligible iPhone проверить фактическую FoundationModels readiness, поддерживаемый язык, реальные prompts/proposals, ожидание/Cancel и Apply/Undo; Commands остаются самостоятельным рабочим путём.
- Разделять AI/LOCAL происхождение; свободный текст не получает ложный успешный ответ при недоступной модели. Исходник голоса сохраняется после исправления нот и portable export.

**Проверки и gate:**

- Speech denial/unavailable завершается понятным состоянием без crash, а успешное распознавание подтверждено реальным текстом/голосом, а не прохождением отказа.
- Голосовой отчёт содержит метод и измеренные распределения ошибок; [офлайн human baseline](VOICE_HUMAN_BASELINE.md) не подменяет телефонную запись.
- Реальная модель создаёт валидное предложение для текущей revision; отмена не редактирует проект, Apply идёт одной history-транзакцией, stale proposal отклоняется.

**Артефакты:** согласованный голосовой корпус/референс, original CAF/WAV SHA, отчёт качества/placement, фактические model inputs/outputs и latency/cancel receipts, запись устройства/ОС/языка.

## Этап 3 — исполнение, экспорт и отдельный MIDI-скетч-генератор

**Зависимость:** этап 1 для существующих live/export путей; этап 2 для использования реальной модели в новом генераторе.

**Код:** [PerformanceController](../AudioRuntime/PerformanceController.swift), [PerformView](../Features/PerformView.swift), [PerformanceTimeline](../Packages/MusicDomain/Sources/MusicDomain/PerformanceTimeline.swift), [OfflineRenderer](../Packages/MusicDomain/Sources/MusicDomain/OfflineRenderer.swift), [StemExporter](../Packages/MusicDomain/Sources/MusicDomain/StemExporter.swift), [ExportView](../Features/ExportView.swift), [AssistantComposition](../Packages/MusicDomain/Sources/MusicDomain/AssistantComposition.swift).

**Работа существующих возможностей:**

- Довести quantized section launch/jump/repeat, filter/reset/delay, Panic, финализацию и replay без stuck notes и незаметного сброса транспорта.
- Сопоставить live take с его замороженным источником и автоматизацией. Project export и performance export явно различаются; WAV/MIDI take не подменяются обычным проектом.
- Зафиксировать mute/solo/master/range/tail семантику WAV/stems, общий старт stems, cancel/progress и очистку временных файлов; проверить импорт результата независимо.

**Отдельный новый контракт MIDI-скетча:**

- Ввести версионированный план: BPM/key/meter/seed, секции, гармония, drum pattern, bass line, motif и происхождение каждого предложения; это будущая реализация, а не готовая функция.
- Валидировать форму, grid, диапазоны нот, плотность/лимиты событий и совместимость партий с гармонией до изменения проекта; генераторы выдают редактируемые ноты/паттерны.
- Подготовить preview/cancel/apply/одну Undo-транзакцию; для детерминированного генератора воспроизводить сохранённый план по seed и версии алгоритма. Ответ реальной модели сохраняется отдельно, повторяемость по одному prompt не предполагается.
- Сохранять фактические музыкальные события в проекте; план/seed/provenance не требуют повторного вызова модели при reopen. Новые поля проходят валидацию и обратную миграционную проверку.
- Правила помечаются как правила, модель — только при фактическом использовании модели.

**Gate и артефакты:** live/replay/export согласованы по событиям и диапазону; MIDI-скетч проходит согласованный контракт и музыкальный review. Сохранить проекты, performance event logs и независимые MIDI/PCM отчёты. Экспериментальный генератор имеет отдельный статус и объём выпуска.

## Этап 4 — аппаратная beta и TestFlight

**Зависимость:** этапы 0–2 приняты для обязательного объёма; scope этапа 3 зафиксирован. Локальная Personal Team достаточна для собственного устройства, TestFlight требует distribution-доступа.

**Код/процедуры:** [MIDIController](../AudioRuntime/MIDIController.swift), [MIDIOutputWorker](../AudioRuntime/MIDIOutputWorker.swift), [NowPlayingController](../AudioRuntime/NowPlayingController.swift), [нагрузочные fixtures](release/fixtures), [DEVICE_ACCEPTANCE](release/DEVICE_ACCEPTANCE.md), [release procedure](release/RELEASE.md).

**Работа:**

- Установить точно идентифицированный подписанный кандидат на минимальную поддерживаемую iOS и актуальный eligible iPhone; зафиксировать source/build/device/OS/route/firmware.
- Выполнить предусмотренные 30-минутные P1/P2/P3 сессии: CPU/memory/thermal, реальный слышимый output, dropout observations и touch-to-sound median/p95 с описанным методом.
- Пройти speaker/wired/USB/Bluetooth, reconnect, звонок/Siri, lock/background/remote controls и media reset; не смешивать Bluetooth audio latency и BLE MIDI.
- На реальных USB/BLE контроллерах проверить timestamp/channel/sustain/CC Learn/disconnect/Panic; импортировать MIDI, WAV/stems и portable voice assets в две реальные DAW.
- Собрать beta-отзывы по одному и тому же музыкальному маршруту, сохранить reproduction/evidence и перепроверить исправленные P0/P1 на новом установленном build.

**Gate:** заполнена физическая матрица с фактическими результатами и методами; открытых P0/P1 нет. UI/host PCM/санитайзеры и слабое связывание frameworks не заполняют аппаратные измерения.

**Артефакты:** installed/TestFlight build receipt, device logs/Instruments и output recordings, latency distributions, MIDI captures, DAW-import receipts и реестр дефектов с повторной проверкой.

## Этап 5 — выпуск в App Store

**Зависимость:** принятая beta и зафиксированный объём 1.0. **Процедура:** [RELEASE](release/RELEASE.md), [RELEASE_QA](RELEASE_QA.md), [Store metadata](store), [privacy](privacy).

**Работа:**

- Для точного release main выполнить все обязательные CI jobs и сверку source/version/build; текущий SDK/archive policy сохраняется независимо от локальной legacy-совместимости.
- Собрать и проверить distribution-signed archive/IPA, профиль, entitlement/UUID/resource/privacy соответствие; установить именно передаваемый на review build.
- Сверить описание, возрастной рейтинг, support/privacy, data declarations и права на материалы с работающим бинарником; portable voice exports описываются честно.
- Сделать актуальные Store EN/RU кадры и запись работающего приложения, затем App Review и smoke production-установки. Исторические Simulator PNG не переименовываются в новые источники.

**Gate:** release source связан с успешными проверками, принятой физической матрицей и установленным signed build; карточка соответствует фактическим функциям/ограничениям; после одобрения проверена production-версия.

**Артефакты:** archive/IPA и подпись, CI run IDs, metadata/screenshots manifests, TestFlight/App Review/Store receipts и production smoke report. Учётные данные остаются в предназначенном хранилище, а не в отчёте.

## Передача результата следующему этапу

1. Записать точный source/version и область проверки: software, simulated failure, real PCM, human voice, real model или physical device.
2. Приложить исходные артефакты и их hashes; сохранить неуспешные попытки и фактические ограничения.
3. Отдельно указать реализовано / проверено / не проверено / блокирует следующий gate. Ожидаемый inventory тестов не является числом прошедших методов.
4. Обновить ROADMAP/README/release evidence после принятого результата; дополнительные функции ранжировать по пользе первого сохранённого скетча и отзывам музыкантов.
