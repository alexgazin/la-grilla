# Независимый QA-аудит La Grilla — 16 ноября 2026

Роль: тестировщик, независимо от авторов исправлений и новых тестов. Решение: **функциональная alpha; выпуск в App Store пока не принят**. Музыкальный редактор и сохранение уже имеют существенную программную проверку. Главный незакрытый риск — разница между успешно автоматизированным Simulator и первым реальным пользовательским сеансом с аудио, диктовкой и моделью.

## Границы и метод

- Проверен checkout `fix/authorized-microphone`, committed source `9fb52e01340d060f3424ae5ea3d38a90b0893b83`, build 17, schema 8; незакоммиченные изменения retirement рассматриваются только как подготовленная реализация.
- Проверены реальные stdout CI, статусы GitHub jobs, восстановленные оригинальные payloads неполного `xcresult`, исходники UI/аудио/хранилища/тестов и действующие release-матрицы.
- Визуально осмотрены четыре оригинальных PNG build 17: AI setup и три splash preview; два PNG build 16: локальный review и редактирование при отказе аудио; кадры настоящего working-demo build 15 на 5, 40 и 120 секундах.
- Это просмотр фактически записанных действий приложения и технический аудит. Я не управлял физическим телефоном, не проводил новую нативную сессию и не выдаю чтение исходников за ручное прохождение на iPhone.
- Среда этого аудита — Linux, без Xcode, подключённого iPhone, USB/BLE-контроллера и реальной доступной Foundation Models. Новые workflow не запускались, настройки CI не менялись.
- «Подтверждено» ниже означает указанный source/run; «риск» означает вывод из кода/покрытия; «Pending» означает отсутствие требуемого фактического измерения.

## Фактическая проверка, включая обновлённый main

| Источник | Результат | Что разрешено заключить |
| --- | --- | --- |
| `main 9dfec7e`, build 16, [run 43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785), native job `133269665014` | **51 PASS / 0 FAIL / 1 opt-in diagnostic SKIP** из 52; 1825.769 с. Весь workflow SUCCESS. | Полная программная регрессия именно main 9df; также прошли unsigned iPhone SDK compile и Release archive. |
| `01fb8b7`, build 16, [run 43851740287](https://github.com/alexgazin/la-grilla/actions/runs/43851740287) | Исторические **49 PASS / 2 FAIL / 1 diagnostic SKIP**. | История сохраняется; она уже не является последним результатом main. |
| `9fb52e0`, build 17, [focused run 43864455841](https://github.com/alexgazin/la-grilla/actions/runs/43864455841), job `133289297239` | **6 явных PASS; 1 метод превысил 120 с**. Общий watchdog 600 с, workflow FAILURE, `xcresult` не финализирован. | Результаты шести методов действительны в их пределах; общего PASS семи методов нет. |
| `9fb52e0`, [run 43864455932](https://github.com/alexgazin/la-grilla/actions/runs/43864455932) | iPhone SDK compile и Release archive SUCCESS; job `ios` SKIPPED по `[device-only]`. | Сборка приложения подтверждена; этот зелёный workflow не является полной нативной регрессией build 17. |
| `9fb52e0`, [run 43864463495](https://github.com/alexgazin/la-grilla/actions/runs/43864463495) | Полное приложение собирается Xcode 16.4 и 26.0.1. | Подтверждена совместимость сборки; запуск на iOS 18 остаётся отдельной задачей. |
| `bde2caa`, первый build 17 | Компиляция остановилась на записи в readonly `accessibilityReduceMotion`; native methods не запускались. | Исправление source 9fb действительно устраняет SDK compile error; первая попытка остаётся неуспешной. |

В main 9df ранее упавшие `testIdleProposalEndsOnModeAndLanguageChangesWithoutEditing` и `testAppThemePersistsAndSystemSettingsEntryIsReachable` прошли за 104.028 и 42.448 с. Эти тестовые файлы между source 01 и main 9df не менялись. Поэтому нынешний результат снимает статус «воспроизводится в последнем main», но не доказывает устранение причины прежнего таймаута/нестабильности снимка.

Артефакт focused build 17: `14225288135`, 71,619,291 байт; SHA-256 `5a4d97206de070dac3af5d2bc541fcb278356b3e277b9ab8b733b0d509575ae9`. Просмотрены `microphone-native.log`, `microphone-process-status.json`, `microphone-sdk-input-node.log`, `monitoring-report.json` и `RecoveredNativeData/recovery-manifest.json`. Восстановление Zstd-payloads не переименовывается в успешный `xcresulttool export`: экспорт завершился ошибкой отсутствующего `Info.plist`.

## Что уже хорошо

1. **Сохранение музыкальной идеи защищено лучше, чем позволяет судить первый пользовательский сбой.** `ProjectStore` — отдельный actor, атомарный manifest, проверка схемы/ревизии, backup, проверка размера и целостности исходного аудио. `Session.create` сначала сохраняет новый документ и только затем переключает активный проект.
2. **Аудиоошибка больше не должна блокировать сам редактор.** Реальный UI-тест отдельного source 27 и затем main 9df проверяет Create → chord edit → save → relaunch → MIDI share при явно внедрённом отказе аудио. Это полезная проверка отказоустойчивости, а не доказательство исправности звука.
3. **Изменения помощника предварительно просматриваются и отменяются одной Undo.** Есть проверки локального parser, A/B, отмены, устаревшей ревизии, сохранения и переносимого проекта; изменения не применяются сразу после диктовки.
4. **Происхождение результата различается.** LOCAL fallback явно подписан; реальные model output, fixture, Commands и запись PCM не смешиваются в документации. Синтетический тест не назван успешной живой транскрипцией.
5. **Реальный DSP и файл проверяются содержательно.** Есть строгие finite/nonzero PCM guards, обнаруженные ноты, hash исходного CAF, корректировка review, store/reopen и Undo/Redo. Новая проверка впервые действительно проходит output-only → первый input, а не только Simulator input-first путь.
6. **Основные экраны уже выглядят как единый продукт.** Grid, Jam и Perform в просмотренных native кадрах имеют общую палитру/иерархию, заметный transport, разные роли дорожек, понятный активный фильтр/loop/take. Графический splash согласован с логотипом и сеткой.
7. **Новый splash не задерживает готовую студию искусственным таймером.** Тест проверяет реальный bootstrap и Welcome → Skip → relaunch; preview отдельно помечен. Крупный русский текст на просмотренном кадре переносится и остаётся внутри экрана.

## Дефекты и риски с конкретной проверкой

### QA-01 — P1, release blocker: владелец всё ещё не получил доказанный исправный первый сеанс на телефоне

**Шаги:** чистый/обновлённый установленный кандидат → Play → Assistant → Dictate с Allow → Stop → ввести команду → review/Apply/Undo → создать пустой проект → добавить материал → save/kill/reopen.
**Ожидание:** звук запускается, приложение не завершается, выбранный микрофон даёт реальные кадры, команда редактируется, проект сохраняется независимо от аудиоошибки.
**Факт:** сообщения владельца фиксируют audio error `2003329396`, вылет диктовки и «микрофон недоступен» при разрешениях; exact installed source/model/iOS/crash stack не зафиксированы. Новый Simulator first-input CAF PASS ещё не доказывает исправление конкретного телефона.
**Работа:** установить однозначно идентифицированный кандидат; записать hardware/model/iOS/source/build/route, санитизированный input-stage/format diagnostic, crash report при повторе; повторить весь путь с granted и denied.
**Приёмка:** исходный пользовательский сценарий проходит на установленном бинарнике; нет завершения процесса; реальный CAF/текст/сохранённый проект проверены, а не только исчезновение красного banner. До этого статус Pending.

### QA-02 — P1, измеренный риск: переход к микрофону прерывает I/O ощутимо для Live Loop

**Шаги:** начать output-only воспроизведение → впервые запросить и разрешить capture на том же музыкальном ядре.
**Ожидание:** заявленная работа поверх живого лупа требует согласованного бюджета и проверки слышимого результата; сохранение ядра само по себе недостаточно.
**Факт source 9fb:** input transition **460.073 мс**; max output callback interval **475.235 мс** при baseline **10.667 мс**, max excess **464.568 мс**. Это измерение Simulator/host callback time; physical dropout-free acceptance отсутствует.
**Работа:** отдельно измерять активацию и новый retirement; записывать фактический output PCM до/во время/после; считать gaps относительно baseline, musical phase и длительность пропуска. Не писать «бит не останавливается» по одному advancing clock.
**Приёмка:** заранее согласованный бюджет для нормального маршрута, фактическое прослушивание/PCM на телефоне и честное поведение при системной смене маршрута. Если неизбежен gap, UX и описание должны его учитывать; сейчас seamless Live Loop capture не принят.

### QA-03 — P1, privacy/lifecycle gate: Stop обязан выключать текущий микрофонный граф

**Шаги:** Play без input → Dictate/Voice → Stop/Cancel → продолжать output-only Play; повторить capture, background и interruption.
**Ожидание:** после завершения input lease микрофон больше не активен, музыкальное ядро и документ сохранены, не работают два одновременно рендерящих DSP-графа.
**Факт:** SDK AVAudioEngine прямо предупреждает: ранее включённый inputNode при granted permission сохраняет mic-in-use indicator при работающем engine. Значит снятия tap недостаточно. Source 9fb ещё не содержит подготовленный retirement patch.
**Работа:** завершить текущую передачу на свежий output-only engine с тем же kernel/rate/MIDI/state, остановить старый graph, проверить failure/retry и повторную запись. Текущие незакоммиченные изменения не считать прошедшими.
**Приёмка:** реальные input frames во время capture; отсутствие attached input после Stop; один активный graph; старый остановлен; output clock/PCM после передачи, повторная запись, project/Undo целы; на телефоне отдельно проверен системный индикатор.

### QA-04 — P1, automation blocker: granted Speech метод не завершает обещанный golden path

**Шаги:** запустить focused build 17 на свежем Simulator с настоящими Allow-подтверждениями.
**Ожидание:** capture → Stop → обычная typed command → review → Apply → Undo в пределах собственного 120-секундного контракта; финальный `xcodebuild` и корректный `xcresult`.
**Факт:** Speech и Mic authorized, `everStartedCapture=true`, **1,250,448 реальных кадров**; terminal `kAFAssistantErrorDomain/1110` = No speech detected. Процесс продолжил ввод `tempo 108` и превысил 120 с до review; дальше global watchdog 600 с. Это не доказанный crash и не успешное распознавание речи.
**Работа:** убрать повторные лишние открытия sheet/ожидания AX, при необходимости разделить независимые сценарии с сохранением проверок; не повышать лимит вместо объяснения. Сделать тестовый scope и отчёт machine-readable.
**Приёмка:** новый exact-source run завершает все выбранные методы, `xcodebuild` exit 0, валидный `xcresult`, корректный summary; локальные изменения теста ещё требуют такого запуска.

### QA-05 — P1, feature acceptance gap: настоящая генерация и голосовая транскрипция не подтверждены

**Шаги:** поддерживаемый iPhone/OS/locale с готовой моделью → free-form whole-song/style request → review/A/B/Apply/Undo; отдельно произнести русскую и английскую команду в реальный микрофон.
**Ожидание:** модель создаёт валидное и осмысленное изменение в заявленной области; диктовка создаёт редактируемый текст и безопасно завершает capture.
**Факт:** новый AI-тест PASS проверяет именно недоступную системную модель, независимость двух языков, Recheck и локальное «Поджазуй». Granted Speech receipt фиксирует PCM, но заканчивается No speech detected. Оба полезны; ни один не доказывает живой успех.
**Работа:** отдельная аппаратная матрица eligible/off/not-ready/unsupported locale; реальные prompts и proposal JSON; cancel/stale/error; RU/EN диктовка, шум/тишина/частичный результат и повтор после error.
**Приёмка:** несколько сохранённых реальных успешных результатов, latency/failure samples, явный режим происхождения; full-song генерацию не рекламировать как принятую по parser/fixture.

### QA-06 — P2, видимая UX-проблема: Assistant перегружен диагностикой настройки

**Шаги:** открыть Assistant в On-device AI при фактическом modelNotReady, как на PNG build 17.
**Ожидание:** сразу понятны причина, одно нужное действие, место ввода и итоговый review; детали доступны по запросу.
**Факт:** большой экран содержит два языка RU/EN в разных местах, абзац про независимость языков, два пересекающихся абзаца про Settings/download, Recheck/Use Commands и STOPPED. Review command находится внизу. В native сценарии приходится многократно скроллить; 110.666 с на полный AI fallback тест — длительность автоматизации, не latency модели.
**Работа:** оставить один краткий статус и первичное действие; подробную настройку свернуть; явно подписать оба переключателя языков; сохранить честный LOCAL label; проверить ввод с клавиатурой и small-screen/large type.
**Приёмка:** normal/large text RU/EN не скрывают основные действия за неочевидной прокруткой, VoiceOver читает оба языка по назначению, Recheck сохраняет введённое; UI-путь укладывается в прежний тестовый budget.

### QA-07 — P2, тестовая нестабильность: предыдущее падение не исчезает из истории после зелёного main

**Факт:** source 01 упал на Assistant idle wait и theme appearance; те же файлы тестов в main 9df проходят. В старом theme сообщении написано «did not adopt light», хотя последнее измерение luminance=1.0 соответствует light — возможно несогласованность временных снимков, а не устойчивый тёмный UI.
**Работа:** хранить final frame, screenshot dimensions и последовательность state/luminance/timestamp; синхронизировать именно presented sheet и screenshot readiness. Изолированно повторить при следующем относящемся к теме изменении; не превращать failure в skip.
**Приёмка:** понятна причина прежнего сбоя или есть независимые повторяемые доказательства корректности; root-cause status отделён от статуса последнего run. Немедленный бесконечный rerun прошедших тестов не нужен.

### QA-08 — P2, доверие к документации: несколько «текущих» срезов расходятся

**Факт на момент аудита:** `STABILIZATION_PLAN` открывается build 16 и «full native ещё выполняется»; DEVICE_ACCEPTANCE/README ещё содержат pending по source 9fb, хотя build/archive/compatibility уже завершены. После новых исправлений эти статусы снова потребуют привязки к source.
**Работа:** один release-candidate summary с source/build/schema, отдельно full/focused/compile/hardware; документы ссылаются на него. Обновить текущий итог main 51/0/1, сохранить исторический 49/2/1 и не присвоить их build 17.
**Приёмка:** читатель README за минуту различает «реализовано», «проверено Simulator», «проверено телефоном», «не принято»; ссылки ведут к нужному run, старые кадры явно подписаны своим build.

## Пробелы покрытия, которые нельзя закрыть красивыми кадрами

| Область | Что уже есть | Чего ещё требует приёмка |
| --- | --- | --- |
| Разрешения и жизненный цикл | Реальный denied Speech, первый Mic Allow, реальные PCM, callback bridge; background playback UI. | Granted complete path, revoke в Settings, repeated capture/Stop/Cancel, уход в background при permission dialog, interruption/route recovery на телефоне. |
| Persistence | Domain corruption/schema/stale-save/backup/assets tests; UI save/relaunch при audio failure. | Нехватка места/убийство процесса на границах save/assets; fault injection с неизменным текущим документом; actual portable import на устройстве. |
| Real-time звук | DSP/domain/native strict PCM, clock/kernel checks, измеренные callback gaps. | 30 минут P1/P2/P3, thermal/memory/CPU, настоящий выход во время capture/edit/mix, p95 touch-to-sound на hardware. |
| Voice-to-MIDI | Настоящий CAF→analysis→review/store/Undo и отдельный human corpus baseline. | Живой напев с backing bleed, reference notes/offsets, выбранные заранее пороги; false positives и ручная коррекция, cancel/route-change. |
| Реальная модель | Typed availability, реальные unavailable причины, Recheck и локальный parser. | Eligible model generation, supported/unsupported locale, latency/cancel/stale scope, музыкальная оценка результата. |
| Жесты/доступность | Native drag/pinch/resize и доступные альтернативы; large-type/landscape UI tests. | Маленький реальный экран, два пальца/scroll arbitration, VoiceOver/Switch Control, 44-point targets и contrast в текущем candidate. |
| Экспорт/MIDI | Независимые WAV/ZIP readers, finite export/share, virtual MIDI. | MIDI/WAV/stems импорт в двух реальных DAW, USB/BLE disconnect/reconnect/sustain/Panic, проверка тайминга и stuck notes. |
| Launch/distribution | Adaptive storyboard, production splash preview, normal bootstrap/onboarding, unsigned archive. | Холодный launch trace p50/p95, interrupted launch, iOS 18 installed launch/weak-link runtime, подписанный exact-source binary и Store metadata. |

Особенно важно: recorded-human baseline имеет 95.88% confidence-qualified F0, но только **60.28% / 54.95% note onset+pitch F1** и 14.04% false voiced среди reference-unvoiced frames. Это не продукт «надиктовал идеальную MIDI-мелодию»; до улучшения/аппаратной приёмки нужны beta-маркировка и полноценный review. Синтетические устойчивые тоны не заменяют этот критерий.

## Как принимать следующие этапы

1. **Закрыть текущий software candidate.** Retirement + granted Speech + минимум один repeated-input сценарий, прежние строгие PCM assertions, все focused methods PASS с валидным result bundle. Затем full regression и archive/compatibility точного нового source; убрать устаревшие current-status записи.
2. **Подтвердить пользовательский телефон.** Повторить QA-01 без диагностических shortcuts. Отдельно первый Allow, уже granted, denied/revoked и retry; сохранить crash/route/format/PCM evidence. Этот этап блокирует утверждение «исправлено на телефоне».
3. **Пройти golden journey в обеих локалях.** Empty project → chords → beat → bass/notes → Assistant local → Undo/Redo → save/kill/reopen → MIDI/WAV/stems/portable. Пройти stopped/playing и audio unavailable; дополнить результатами клавиатуры/compact/large type.
4. **Принять интеллектуальные функции.** Живой RU/EN speech и human humming; реальная модель на eligible hardware; объявленные критерии качества и latency, error/cancel/review. Во всех результатах сохранять явное происхождение.
5. **Аппаратная beta.** P1/P2/P3 по 30 минут, маршруты/interruptions/controllers, actual two-DAW imports, память/тепло/dropouts; все P1 закрыты или функция честно исключена из заявленного релиза.
6. **Release candidate.** Подписанный бинарник соответствует прошедшему source, чистый install/update/migration, privacy/permissions/support/listing соответствуют реальному поведению; TestFlight smoke и заполненная DEVICE_ACCEPTANCE. Personal Team подходит для локального retest; наличие платного аккаунта не исправляет runtime-дефекты.

Каждый дефект получает owner, source/build, ожидаемый результат, реальное evidence и retest. Gate закрывается поведением и проверкой, а не количеством строк кода, наличием кнопки или зелёным compile job. Новых подтверждённых P0-крашей на просмотренном source я не обнаружил; исходный отчёт владельца остаётся серьёзным незакрытым сигналом до hardware retest.

## Достоверность демонстрации

- `Media/WorkingDemo`: реальные UI-действия и звук той же Simulator-сессии build 15. Просмотренные Grid/Jam/Perform кадры согласуются с описанными действиями; титры и рамка принадлежат видео, не UI.
- Полная музыкальная/голосовая/model/hardware приёмка этим видео не доказывается. В Voice показана подготовка; живого распознавания нет. Исходный capture workflow FAILURE с сохранёнными тремя успешными UI-методами честно раскрыт.
- `Media/Promo` — отдельная презентация кадров с офлайн app-synth soundtrack; не использовать её как evidence непрерывной записи экрана/звука приложения.
- `Screenshots/DeviceRepair`: принятые PNG сохраняют source/hash/test; dimmed Grid вместо share sheet обоснованно исключён. Это хороший образец визуальной приёмки.
- Четыре PNG build 17 восстановлены без изменения пикселей из неполного bundle; пока не переносить их как «полный зелёный run». Splash preview показывает дизайн, а не длительность холодного запуска или качество анимации; для движения нужна реальная запись.
