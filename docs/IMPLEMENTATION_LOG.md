# Журнал завершения исходного видения

План: [ORIGINAL_VISION_COMPLETION](ORIGINAL_VISION_COMPLETION.md). База: `main` `1ddf660` / 1.0.0 (12), schema 7. Проверены 64 Swift tests, 11 C++ suites, 19 Studio flows и обе SDK-сборки/архив; 54 кадра относятся к прежнему объёму функциональности и не доказывают ещё не реализованные расширения.

## C0 — сверка и начало реализации

- **Статус:** техническая сверка выполнена; план и контракты записаны, реализация начата.
- **Обнаруженные пробелы:** ограниченный Assistant вместо free-form AI; нет clip/section drag; Stop при изменении структуры/микрофоне; restart в A/B; неполный практический каталог/нет формул пользователя; фильтр Slider вместо круговой ручки; открытая физическая приёмка.
- **Разделение работы:** гармоническая модель/редактор; clip/section domain+жесты; atomic DSP snapshot; shared microphone; typed AI/provider+review; circular live filter. Интеграция Session/schema/CI/localization/screenshots централизована.
- **Согласованные контракты:** schema 8; optional customIntervals; clip-specific note selection; project snapshot с notes+mix+presets+layout token+revision; один duplex input tap; validated whole-song Assistant proposal.
- **Проверки пока:** исходные acceptance-результаты базы; новые этапы не отмечены выполненными до фактических проверок.

## C1 — гармония, формулы, schema 8

- **Разработка:** 65 пресетов вместо 23, семейства аккордов, разбор джазовых обозначений и формулы из 2–8 интервалов. Редактор показывает ноты, валидирует формулу до применения и даёт выбрать полное/компактное расположение.
- **Техническая часть:** `Model.swift`, `HarmonyLab.swift`, `Editors.swift`, `HarmonyLabView.swift`; `customIntervals` optional, прежние raw values сохранены. Миграция 7→8 затрагивает и frozen source исполнения. Проверка версии выполняется до декодирования новых enum, чтобы старая версия корректно сохраняла неподдерживаемый документ.
- **Музыкальные ограничения:** опускать можно только явно необязательные ступени стандартного аккорда; формула пользователя сохраняет каждую ступень. Сложность компиляции считается по реальному числу голосов, а не по прежней константе.
- **Проверено на host:** 11 новых тестов каталога, включая 65 × 12 корней × slash/no-slash × оба расположения; aliases, ошибки, migration/frozen future schema. Полный пакет после интеграции первых доменных изменений: 101 тест, 0 ошибок.
- **Открыто до приёмки:** native Editor/Apply/Undo и кадры `HarmonyCatalogTests`; финальная SDK-проверка общей сборки.

## C3 — клипы, форма и конкретные редакторы

- **Разработка:** `ClipEditing.swift` — move/copy/resize/create/delete/offset, совместимые дорожки, snap, bounds/overlap и проверка project/revision payload до изменения. Copy клонирует pattern; ссылка на исходный голос сохраняется. Один жест проходит через одну History-транзакцию.
- **Секции:** пересекающие границы клипы разрезаются с сохранением source offset. Duplicate/delete/reorder не теряют материал, начинающийся в предыдущей секции. Публичные методы `Project` также перенаправлены в новые безопасные операции, чтобы меню/fixtures и другие callers не сохраняли старую ошибочную семантику.
- **UI:** явный режим Clips, native drag/drop, resize, инспектор/список; source-aware chord slices; Piano Roll/Jam получают конкретный clip ID, а не первый клип на начале секции.
- **Проверено на host:** 11 новых тестов операций, включая компилируемые MIDI-события, независимую копию, crossing clips, source asset retention, Undo/Redo и атомарный отказ. Новая запись барабанов материализует только выбранный экземпляр и объединяет весь take в одну Undo-операцию; его отдельные проверки выполняются при интеграции Session.
- **Открыто:** завершить связь Session и native жесты в `ArrangementUITests`, проверить scroll/pinch на компактном iPhone; получить реальные кадры.

## C4 — согласованные live-транзакции и MIDI

- **DSP:** `lg_submit_project` переносит ноты, BPM/range, mixer, presets, master FX и стабильные ключи дорожек одной транзакцией. Принятие на границе такта/цикла; stopped/seek принимает последний снимок. Sample clock и Play сохраняются.
- **Исправленные дефекты:** однотактовый loop раньше не видел новую границу; будущий mixer мог вытесняться burst старого поколения; старый beat-repeat history мог прозвучать на новой дорожке после перестановки. Добавлены отдельные regression checks. Смена структуры отменяет repeat и старые held MIDI/sustain; stereo delay/filter сохраняются, переход сглаживается 3 ms.
- **MIDI:** стабильный UUID key следует за дорожкой при reorder, удалённая цель отклоняется. Карта output channels принимает новый layout в том же callback; asynchronous worker не может вернуть старые каналы. Destination epoch отделён от channel map. Структурная правка frozen Performance source во время записи/replay остаётся заблокирована: его формат индексный, поэтому произвольная замена source в таком take была бы неверной.
- **Swift integration:** AudioController кэширует музыкальные поколения вместе с метаданными layout, использует revision-aware mixer и показывает настоящий pending. MIDI Session настраивается по принятому поколению. Live A/B отправляет новое предложение без seek/restart; idle audition запускается явно.
- **Проверено на host:** 14 C++ suites и P1/P2/P3 stress, реальные stereo PCM, 44.1–192 kHz, add/reorder/delete, конкурентные публикации и отсутствие render allocations. Отдельный MIDI layout regression прошёл ASan/UBSan; LeakSanitizer недоступен в текущем ptrace-окружении. Эти результаты не заменяют задержку/нагрев реального iPhone.
- **Открыто:** окончательный аудит callback/preview handover, native непрерывный сценарий и финальные интеграционные проверки.

## C5 — общий input graph, голос и диктовка

- **Разработка:** `LiveMicrophone.swift`, `LiveInputBuffer.cpp`, обновлённые VoiceCapture/DictationController. Один input tap существующего AVAudioEngine; микрофонная lease ограничивает input, оставляя output/MIDI и текущую музыкальную позицию.
- **Realtime:** ограниченный двухсекундный SPSC ring; только downmix/copy/atomics в tap. Дренирование, конверсия, запись CAF и Speech append выполняются на worker. Ошибки overflow/route/invalid PCM показываются явно; максимальный take — 30 s, разрешение запрашивается по действию.
- **Привязка:** точка начала рассчитывается после подготовки audio route. Работающий loop ждёт его фактического начала; линейный playback — следующего такта. Запись ограничивается остатком целевой секции/loop, чтобы ноты не исчезали за её границей. Пользователь видит ожидание и фактическую длительность. Изменённый проект требует явного повторного review с сохранением CAF и ручной правки.
- **Диктовка:** Stop завершает уже переданные слова вместо немедленного удаления recognition task. Язык/доступность on-device Speech проверяются, сетевого fallback нет.
- **Проверено на host:** ring downmix/order/overflow/finite samples/arm-once и 240000 конкурентных кадров, ноль callback allocations. Синтетический draft остаётся явно помеченным fixture и проходит тот же off-tap converter/CAF sink.
- **Открыто:** Swift/Session/UI интеграция, SDK typecheck и native fixture; человеческий голос, реальные входы и Bluetooth-маршруты относятся к C8.

## C6 — настоящий локальный ИИ и предложение всей песни

- **Разработка:** `AIComposerController.swift` использует Foundation Models на iOS 26, `SystemLanguageModel` availability/language checks и typed guided generation. Неподдерживаемое устройство не получает фиктивный ответ модели: остаётся обозначенный Commands режим.
- **Domain:** `AssistantComposition.swift` валидирует 1–8 секций/64 такта, тональность, темп, длительности, источник ритма/мелодии и плотность. Новые schema-2 operations совместимы со schema-1 proposals. Whole-song arrangement сохраняет идентичность дорожек, mixer/MIDI/voice assets и frozen take; materialize учитывает repeat/trim/offset.
- **Review:** видны полный before/after список секций, аккорды/длительности, предположения и источники материала. A/B и Apply используют ту же живую транзакцию; ошибка, отмена, повторный или устаревший proposal не меняют проект. Генерация ограничена по времени и отменяется.
- **Локальный режим:** русская/английская команда «поджазовать» выполняет настоящее гармоническое преобразование; структурированный `Song: ...`/русский эквивалент строит многосекционный proposal без модели. Free-form AI требует поддерживаемую локальную модель и язык, это отдельно объясняется в UI.
- **Проверено на host:** 10 новых composition tests и прежние 7 Assistant tests; strict JSON/limits/stale/source preservation/Undo/повторный Apply. Native screenshot fixture `assistant-song-proposal` использует Commands и явно не считается результатом реальной LLM.
- **Открыто:** Apple SDK typecheck, native review/Apply/Undo; реальная Foundation Models generation и её музыкальное качество на поддерживаемом iPhone — C8.

## C7/C8 — граница текущей проверки

Рабочий интеграционный кандидат — **1.0.0 (14), schema 8**; последний принятый baseline — **main `912dc483` / 1.0.0 (13)**, exact-main run `43719321757`. Новая версия принимается отдельно. Новые источники не объявляются проверенными только потому, что синтаксический parser Linux их принимает.

- **Host checkpoint `031f977`:** 107 Swift tests, 0 ошибок; 14 C++ suites и P1/P2/P3 stress проходят, callback allocations = 0. Presentation audit — 584 EN/RU ключа, placeholder parity, contrast/font/icon; Release audit проходит.
- **Сквозная приёмка:** один короткий проект проходит custom/jazz whole-song proposal decode/review/apply, clip move/resize/offset/copy, section duplicate/reorder/delete, save/load и portable install. Независимый SMF reader проверяет 21 конкретную пару NoteOn/Off с channel/tick/duration/velocity, tempo и markers. Повторный PCM render побайтово совпадает, пять stems выровнены, mute даёт нули, их сумма совпадает с mix в пределах 16-bit quantization. Отдельный Python reader проверил RIFF/ZIP и реальную басовую последовательность D1→E1.
- **Первая Apple проверка `08fc23d` / run `43713282157`:** обнаружен type-check timeout сложного `GridView.clipList`; body разделён на небольшие builder helpers. Предупреждения захвата AVAudioPCMBuffer/изменяемой локальной переменной converter callback устранены явной confined ownership box, без подавления Sendable diagnostics.
- **Native acceptance checkpoint:** `031f977`, run `43713870989`, [PR #13](https://github.com/alexgazin/la-grilla/pull/13). Результат ещё не принят. Новые suites проверяют настоящий native drag, whole-song review/Apply/Undo, custom editor, live track/section/A-B, voice rebase и actual engine/kernel clock/PCM; synthetic fixtures обозначены явно. Проверка настоящего mic tap не подменяется синтетическим источником.

Дальше: обе Apple SDK, optimized archive, все native сценарии, оригинальные кадры `Screenshots/OriginalVision`, App Store copies и повторная проверка итогового `main`. Source SHA/run/merge/manifest фиксируются по факту.

Для C8 нужны реальные Apple signing ресурсы и оборудование: установленная сборка, человеческие напевы, USB/BLE MIDI, route/latency/thermal/background сессии, настоящая локальная модель, TestFlight и App Review. Независимая программная работа продолжается; недоступность этих ресурсов не превращается в выдуманную отметку «готово».

### C7 — первый нативный прогон и исправления по фактам

Источник `12dc161`, run `43714307514`: обе SDK-сборки и optimized archive проходят. Прошли все 19 прежних Studio-сценариев, два Harmony Catalog, два Assistant Composition, три Perform Control и проверка настоящего AudioController snapshot. Последняя проверила слышимый preview по meter, согласованный pending mix/FX, preset-only invalidation, 80 публикаций, ограниченный routing cache, kernel identity и фазу.

Общий native результат **не принят**. Исправления по hierarchy/video/log:

- Родительский `grid.lane` identifier подменял UUID и frame каждого clip; удалён. Clip/section drag используют один String Transferable с обеих сторон; native gesture tests сохраняют реальный перенос и Undo/Redo с полноценным lift/dwell.
- Родительский `section.row` identifier подменял menu identifier; удалён, menu получил название секции. У Bass Switch iOS 26 AX frame включает всю строку: тест касался середины label; теперь касается настоящего thumb и по-прежнему проверяет смену значения и Play.
- Длинная строка команды в native Examples popup не имела рабочего activation point; после повторных таймаутов меню заменено обычным sheet/List с полным текстом и стабильными ID.
- Mic fixture запрашивал permission во время `app.launch`, до присоединения XCTest; видео показывает WAITING и живой системный alert, CrashReports отсутствуют. Fixture теперь ждёт READY и явного Start после launch, с зарегистрированной обработкой permission. Проверки реального PCM/route/phase не ослаблены; оснований менять production audio graph по этому сбою нет.
- SwiftUI Stepper экспортирует составной child identifier (`voice.pitch-Increment`), а не голую кнопку Increment; запрос исправлен по фактической hierarchy.
- Реальные кадры показали непонятный выбор `None` без подписи Slash bass; подписи двух menu pickers добавлены явно. В accessibility-размере DJ section pads переходят в одну колонку, чтобы Chorus не обрезался.

Дополнительно закрыты два обнаруженных дефекта данных/управления:

- Текущее отключение MIDI input/output больше не ждёт музыкального поколения. Output worker активирует только свой ещё актуальный disabled epoch; старая queued selection не включает уже отключённый endpoint. Host regressions проверяют held/sustain release, pending layout, stale input/output, no reconnect после adoption и правильный новый bus. Добавлен actual Session/virtual CoreMIDI native regression.
- Импортированный `revision = Int.max` раньше принимался и приводил к overflow на следующей правке. Диапазон ограничен `0...Project.maximumRevision`; History проверяет следующий номер до изменения данных/стеков. Пять новых тестов проверили обычные Undo/Redo, границы, JSON/portable/store, сохранность исходника и атомарный отказ. **112 Swift tests проходят**, 14 C++ suites и targeted ASan/UBSan проходят; presentation audit — 588 EN/RU ключей.

Release archive `12dc161` проверен отдельно: iOS 18 minimum, SDK 26.2, version 1.0.0 (14), matching binary/dSYM UUID, privacy/localizations/resources. FoundationModels — weak load, все 77 imports и chained-loader bindings weak; нет startup initializer или unguarded startup call. Reusable `audit_binary.py` включён в archive CI; четыре negative corruption probes корректно отклонены. Это статическая проверка совместимости, а не выдуманный запуск на физическом iOS 18.

В capture collector исправлено ложное распознавание суффикса UUID как stage name (`...A5C2-D263...`). Регрессионный fixture проверяет настоящее suggested screenshot name и побайтовое сохранение PNG. Это исправление метаданных, а не изменение изображения.

### C7 — повтор bba и текущая стабилизация

`bba5aac`, run `43719235900`: обе SDK и archive/binary audit проходят. Native подтвердил реальный section drag+Undo, доступное Add clip+Undo, whole-song Assistant A/B с непрерывным Play, voice review/rebase с сохранённой ручной C♯4 и исходником, immediate MIDI Off до pending boundary, живой snapshot/clock. Все Harmony/Perform и прежние 19 Studio-сценариев снова прошли. Общая приёмка остаётся открытой.

Оставшиеся сбои: clip уже рисовался шириной 90 pt, но его AX frame оставался 768 pt; Bass/section popup продолжали получать неверный native activation point; после корректно выданного permission hosted input не имел пригодного формата. Тесты сохраняют строгие frame/value/Play/gesture/PCM проверки. Clip получает публичный UIKit accessibility carrier с реальными экранными bounds; Bass — отдельный ограниченный native switch; section и melody-track actions — обычные sheet/List с отложенным rename/source/delete presentation. Попытка использовать несуществующий SwiftUI frame modifier была отклонена Apple SDK и заменена публичным UIKit API.

Микрофон фиксирует структурированную route/format диагностику **до** восстановления playback category. Если session объявляет вход, но node format некорректен, выполняется одна перестройка того же графа без замены kernel/Stop/Seek. Только исходное подтверждённое отсутствие input/ports может считаться недоступным оборудованием, после проверки сохранности output. CI дополнительно настраивает официальный виртуальный duplex HAL BlackHole и требует настоящий PCM; `UNAVAILABLE` в таком CI — failure. Установка/выбор host devices логируются отдельно; это проверка настоящего AVAudioEngine input path, а не человеческого голоса.

Повтор `dc3a0a9` / run `43724350400`: обе SDK, archive и установка HAL проходят; 7/10 integration-сценариев прошли, общий результат не принят. Clipboard frame уже соответствует 90 pt вместо 768 pt, но видео доказало конфликт long-press context menu с drag; меню удалено (те же действия есть в инспекторе), passive touch observer сохраняет grab offset, не распознавая и не отменяя жест. Добавлена проверка off-center drag широкого клипа. У native Switch собственная AX thumb-высота около 27 pt: теперь настоящий UISwitch имеет согласованную публичную 64×44 touch/AX область, а тест касается верхнего/нижнего края и проверяет каждое изменение значения.

Host HAL был действительно выбран и работал на 48 kHz, но Simulator по-прежнему объявил 2 канала с частотой 0 Hz и не дал PCM. Диагностика подтвердила сохранение engine/kernel/clock/category и фазы; это не выдано за успешную запись. Следующий CI дополнительно задаёт собственные remembered input/output preferences Simulator: точные `RecentAudioInputDeviceUIDs`/`RecentAudioOutputDeviceUIDs` проверяются по установленному SDK, сохраняются и логируются после boot. Производственный граф не заменяется на догадке о причине. Финальные полный native run, 375-point capture и полная коллекция OriginalVision остаются обязательными.

### C7 — проверка 8a909 и расширение сквозной приёмки

Source `8a90920684e2e66fb9a159adec975e4af1cfa303`, [run 43726756796](https://github.com/alexgazin/la-grilla/actions/runs/43726756796): обе SDK и optimized archive проходят; **7/11 native integration tests passed, 4 failed**, общий результат не принят. Впервые прошёл настоящий перенос широкого четырёхтактового клипа с off-center grab offset и Undo. Также проходят Add clip, section drag, live snapshot, immediate MIDI Off, Assistant A/B и live section operations.

По реальным log/video исправляются четыре причины, без ослабления проверок:

- Уменьшенный однобарный клип действительно поднимался при drag и возвращался без ошибки доменной операции; широкий клип переносится. Resize-gesture вынесен из draggable Button в отдельный нижний угловой target; native source обновляется после revision, сохраняя стабильный clip AX UUID. Добавлена проверка фактического corner resize и Undo; исходные one-bar/wide движения и start `2:1` сохранены.
- Native Bass Switch имел 44 локальных пункта, но системная презентация уменьшила экранную высоту до 42.4. Настоящие layout, touch и AX bounds увеличены согласованно до 64×48; строгие физические ±20-point edge taps, обе смены value, 44-point минимум и непрерывный Play остаются обязательными.
- VoiceReview прошёл source hash, ручную C♯4 и rebase, затем не включил Instrument: SwiftUI объявил частично скрытую кнопку hittable. Reveal теперь проверяет положение всего контрола внутри видимого viewport, а реальное касание должно сначала включить `PREVIEW`; explicit Stop возвращает `ORIGINAL`, сохраняя Play/hash/pitch. Предположение об окончании короткого preview отвергнуто после чтения Session и видео: этот preview работает в loop.
- Input всё ещё объявлял 2 канала с 0 Hz и не дал кадров. Host HAL и post-boot RecentAudio UID arrays действительно выбраны, но recents не доказывают выбранный Simulator input. Следующая проверка использует поддерживаемое меню Simulator Audio Input/Output через bounded GUI automation и требует checked marker существующего BlackHole item. Только последующий настоящий PCM может закрыть входную цепь. Output engine/kernel/clock/playing/category уже сохранялись; phase difference — `3.41e-13` tick.

Обнаружен отдельный release bug: прежний signing gate принимал три green check names даже от сокращённого integration/capture run. Gate теперь проверяет exact SHA, GitHub Actions origin, фактический verification event/scope, job/check linkage и один coherent завершённый run. Focused/capture-only push не разрешает signing; manual exception относится только к настоящему `ios.yml workflow_dispatch`. Host regressions покрывают ложные допуски и безопасные ошибки; read-only проверка на реальных API-данных main `912dc483` корректно приняла run `43719321757`. Signing при этом не выполнялся.

Приёмка дополнена реальными RU/EN/375-point кадрами custom chord editor и крупным верхним блоком Perform. В разработке — actual VoiceCapture → CAF → analysis → apply/source persistence/Undo и фактический Session lifecycle записи offset/repeating drum clip. Эти проверки не подменяют человеческий голос или измерения физического MIDI. [Промежуточный кадр Assistant](../Screenshots/OriginalVision-progress/assistant-live-form.png) сохраняет собственный прежний source/run/manifest и явно отделён от будущей полной коллекции.

Дополнительные native проверки реализованы, Apple SDK/execution ещё не приняты:

- `VoiceCaptureRuntimeQA` использует настоящие Session/VoiceCaptureController, input tap и host HAL loopback: ядро играет монофоническую референсную мелодию с тихими барабанами, а тест не подставляет PCM или результат анализа. Проверяются finite Float32/mono/48 kHz CAF, frame/duration/provenance/hash, неизменный оригинал после ручной коррекции, непустые реальные detected notes, точная связь sourceAsset и reviewed notes, настоящий store/reopen и одна Undo/Redo. Монитор наблюдает engine/kernel/clock/phase на всём async capture/analysis/save пути. Это программная приёмка тракта, не оценка человеческого напева.
- `DrumClipRuntimeQA` ведёт настоящую Session-запись в offset/repeating clip с общим исходным pattern: два прохода по audio clock, отдельная правка gain/pan, самостоятельный audible draft и одна финальная history-транзакция. Проверяются независимость нового источника, сохранность sibling/старых слышимых событий, quantized pads, mixer, Undo/Redo и фаза. Второй сценарий проверяет natural finite end: частичный take сохраняется и снимает recording lock, нажатие за пределами клипа слышно, но не заворачивается в его pattern.

Generated project включает 31 app source file; всего 43 native test methods: 40 функциональных и три capture methods. Focused run теперь выбирает 14 integration tests, не заменяя полный набор. Синтаксический parser, presentation/release и 12 release-gate regressions проходят; это не объявляется Apple typecheck или native выполнением нового кода.

### C7 — 4d1f69: подтверждённый маршрут и устранение реальных touch/I/O причин

[Run 43729615286](https://github.com/alexgazin/la-grilla/actions/runs/43729615286), source `4d1f69ac0abe4ba727a6a12573d2c155e454374c`: обе SDK и optimized archive проходят. GUI automation действительно открыла Simulator I/O и подтвердила `✓` у BlackHole input/output до и после выбора. Несмотря на это, mic вернул 0 frames и 2-channel/0 Hz formats. Гипотеза неверно выбранного input этим результатом отвергнута; это не доказательство отсутствия оборудования.

Строгий native прогон снова не принят. Add clip, section drag, wide off-center drag, snapshot/MIDI, Assistant A/B и section operations прошли. Однобарный drag и новый corner resize не завершили изменение, без domain validation error: физический SwiftUI hit/gesture host не совпал с правильным AX carrier. Вместо дальнейшей правки AX frames вводится настоящий ограниченный UIKit touch surface: UIDragInteraction, tap и отдельный corner UIPan; актуальный payload создаётся в момент drag. Внешний SwiftUI face остаётся рисунком, native lift preview берёт реальную видимую область клипа. Старые проверки реального переноса/resize/Undo не ослаблены.

Bass прошёл минимальную высоту, но касание в расширенном border не включило внутренний UISwitch gesture. Новый UIView host разделяет реальные touch regions: native switch принимает только свою область, padding — только внешние точки и посылает ровно один valueChanged. Его AX frame теперь соответствует фактически работающему целому target. Оригинальные ±20-point касания/обе смены состояния/Play сохранены.

VoiceReview подтвердил `PREVIEW` → настоящий Stop → `ORIGINAL`, исходный hash, ручную C♯4 и Play. Последующее раскрытие Apply превысило timeout: helper измерял ScrollView Grid под представленным Voice sheet. Теперь он адресует именно Voice ScrollView и имеет ограниченные retries с диагностикой target/viewport.

Для C5 Apple [pause](https://developer.apple.com/documentation/avfaudio/avaudioengine/pause()) сохраняет prepared resources, а [stop](https://developer.apple.com/documentation/avfaudio/avaudioengine/stop()) освобождает их. При фактически невалидном input новый guarded fallback освобождает I/O и подготавливает **тот же** engine/source/kernel; он не вызывает музыкальный Stop/Seek/reset и не задаёт выдуманный format. Read-only EnableIO status/size/optional value снимаются до первого input getter и после reprepare; неподдерживаемый query даёт null. Добавляется измерение output host-timestamp gaps, поскольку сохранённые clock/identity сами по себе не доказывают отсутствие аппаратной паузы. Успех этого изменения и реальный PCM ещё требуют Apple SDK/native receipt; непрерывность на физическом iPhone остаётся C8.

Следующий программный checkpoint включает 32 app source files, настоящую нативную поверхность клипов, разделённые touch regions Bass и адресный Voice scroll helper. Для короткой дорожки corner не закрывает центр; очень узкий clip использует всё тело для drag и существующий inspector для resize. NSItemProvider loader создаётся вне MainActor и передаёт только immutable UTF-8 data.

Новый OutputTimingMeter хранит предыдущий host anchor через measurement epoch и engine restart, использует bounded atomic publication/read без callback locks/allocations и не меняет PCM. Проверены непрерывный/переменный buffer spacing, 80/100 ms паузы, первая пауза после epoch, обратные timestamps/rate changes, offline exclusion, 44.1/48/96 kHz, 5000 конкурентных epochs/snapshots и точное сохранение звука. **15 C++ suites + stress прошли**, render allocations = 0. После изменения ядра заново прошли **112 Swift tests**. Generic mic и production VoiceCapture receipts ждут baseline callbacks до записи и сохраняют baseline/final host-timing; `physicalDropoutAbsenceVerified=false` не даёт спутать их с физическим измерением динамика. Apple SDK/UI этого checkpoint ещё не приняты.

### C7 — 1bfdb22: все touch/live сценарии приняты, input остаётся единственным блокером

Source `1bfdb22bd7fa60efca90c7a702befbf240c6e986`, [run 43733352465](https://github.com/alexgazin/la-grilla/actions/runs/43733352465): обе SDK/Release archive, 112 Swift и 15 C++ suites проходят. **12/14 native integration tests passed**: все пять Arrangement (включая настоящий one-bar drag, corner resize и Undo), snapshot/MIDI, production Session drum lifecycle, все три LiveEditing и VoiceReview. Новые реальные [arrangement/track actions PNG](../Screenshots/OriginalVision-progress) сохранены с per-file source/run/hash; старый Assistant не переименован в новый источник.

Не прошли только generic mic и actual VoiceCapture. EnableIO query успешен (`status=0`, 4 bytes): input остаётся `0`, output `1` до input getter и после reprepare; оба input formats — 2ch/0Hz, frames=0. Host timing раскрыл **132.052167 ms excess / 142.718833 ms max callback interval** против 10.666667 ms baseline/512 frames. Сохранённая phase/engine identity не выдана за бесшовный звук. Дополнительные случайные изменения Simulator preferences прекращены.

Следующий запуск `[input-diagnostic]` сохраняет оба строгих failing production tests и отдельно собирает четыре локальных fresh-engine controls: duplex input-first, playback с заранее созданным disabled input, playback output-first/late input и duplex output-first/late input. Категория задаётся **до создания** соответствующего engine; разрешение запрашивается после READY/Start, до reset/controls. Входной format берётся только из реального node; tap не устанавливается на нулевой hardware/output format. Отдельный terminal `DIAGNOSTIC`/JSON `productionAcceptance=false` не закрывает C5. Такой scope отклоняется signing gate. Read-only TCC rows и фактические SimulatorTrampoline identifiers дополняют receipt без изменения разрешений.

При независимой сверке найден реальный state bug: MIDI mixer edit вызывал baseline sync, но оставлял `harmonyPreview=true`; preview из idle продолжал играть baseline. Нормальный sync теперь централизованно сбрасывает audition и восстанавливает исходное idle/run состояние; Performance mix path сохранён. `endHarmonyPreview` использует ту же процедуру, а open очищает старый audition до смены проекта/seek0. Native snapshot QA дополнен running-preview/MIDI gain, rejected edit, accepted idle edit и project-open cases; их новая приёмка ещё предстоит.

### C5 — 94c6a6a: установлен различающий порядок создания I/O

[Run 43736580392](https://github.com/alexgazin/la-grilla/actions/runs/43736580392), source `94c6a6a4822cbe88bad1506728a1d1ae70016239`: обе SDK/archive проходят. Оба production mic tests по-прежнему не приняты. Отдельная сборка диагностических данных прошла и вернула `DIAGNOSTIC`, не `PASS` C5: permission `undetermined → granted`, explicit request=true, 5.169 s для четырёх контролей. Actual host TCC row — grant2/type0; настоящий SimulatorTrampoline code identifier совпадает.

| Локальный контроль | Реальные input formats / EnableIO | Реальные конечные PCM |
| --- | --- | --- |
| Duplex, input getter до output | 48 kHz/2ch, input1 | 12000 finite frames, complete |
| Playback, input getter до output; затем duplex | 48 kHz/2ch, input1 уже на первом этапе | 12000 finite frames, complete |
| Playback, output-first/late input + reprepare | 0 Hz/2ch, input0 | 0, tap не установлен |
| Duplex до engine creation, output-first/late input | 0 Hz/2ch, input0 | 0, tap не установлен |

Категория первого локального контроля сменилась на Playback во время наблюдения; поэтому данные не объявляют весь эксперимент идеальной изоляцией глобальной сессии. При этом оба input-first графа дали настоящий ограниченный callback transport, оба output-first — нет. Название старого второго ID «disabled» было гипотезой: фактический EnableIO там1, это явно сохранено в receipt. Generic production failure снова показал сохранённую phase, но 158.662625 ms excess output gap; сам reprepare не исправил disabled singleton.

Минимальная следующая production-правка создаёт `e.inputNode` до output/mainMixer/source preparation существующего AudioController. Категория на старте остаётся Playback, ручного изменения AU/формата или нового capture engine нет. До принятия обязательна новая cold-output проверка: XCTest сбрасывает разрешение в undetermined, запускает настоящий output и отвергает неожиданный microphone alert; helper не вызывает permission API/tap. Реальная запись, CAF/analysis/apply/source/Undo должны пройти прежние строгие тесты. Физический microphone indicator остаётся отдельным C8 наблюдением.

### C5/C7 — холодный первый захват и готовность Simulator

Source `d9250ae`, [run 43738952980](https://github.com/alexgazin/la-grilla/actions/runs/43738952980): simulator build, iPhone SDK и optimized archive прошли. Оба запуска iOS job остановились **до native tests** на настройке Simulator: attempt 1 — timeout System Events 45 s; attempt 2 — доступное меню I/O с ещё пустым Audio Input, без BlackHole item. Ни privacy, ни PCM, ни CAF результата этот run не установил. Ни один из этих setup failures не переименован в успешную или недоступную запись.

Настройка GUI теперь делает до трёх ограниченных попыток (каждая ≤45 s), ожидает реальные окна/наполнение меню и повторно читает фактические checkmarks. Для успеха по-прежнему необходимы **оба** выбранных и включённых BlackHole input/output. Нет fallback route, отключения native-проверок, перезапуска Simulator или изменения TCC. Host shell/Python parse и mock проверки retry→success, missing→failure, timeout→124 прошли; настоящее GUI поведение ожидает следующего macOS run.

Cold privacy acceptance усилена: один процесс и первоначальные engine/kernel сначала играют монофонический reference с permission `undetermined`, без запроса микрофона. XCTest сохраняет и проверяет отдельный phase-one JSON; любой ранний alert отвергается и проваливает сценарий. Только после явного Start разрешается ожидаемый prompt и запускается **тот же production VoiceCaptureController**: реальные HAL/input callbacks → CAF → analysis → ручная правка → apply/store/reopen → одна Undo/Redo. Между фазами не вызываются prepare/edit/seek/play и не пересоздаётся reference. Проверяются PID, engine/kernel, исходный проект, clock/phase и permission до/после; warm microphone и VoiceCapture cases сохранены отдельно. Это исключает ложный успех, при котором запись начинает работать лишь после перезапуска уже разрешённого приложения. Результат новой проверки пока не получен; человеческий голос и физический microphone indicator остаются C8.

## Формат отчёта каждого этапа

Для C1–C8 добавлять отдельную запись:

1. Статус и конкретное изменение поведения.
2. Данные/API/алгоритм и затронутые файлы.
3. Совместимость старых проектов, export и Undo/save/reopen.
4. Реальные выполненные тесты и результаты; отдельно host, simulator, device/model.
5. Source SHA, CI run, PR/merge, version/schema.
6. Реальные кадры и manifest; какие сцены и языки покрыты.
7. Найденные дефекты, исправления, оставшиеся ограничения/следующий зависимый этап.

Нельзя записывать «проверено» для недоступного устройства, модели, signing или внешнего сервиса; тестовый provider и синтетический голос должны оставаться явно помеченными fixtures.

## C2 — круговой live-фильтр

- **Статус:** software/native приёмка пройдена, кандидат **1.0.0 (13)**, [PR #14](https://github.com/alexgazin/la-grilla/pull/14) слит в `main` `912dc483`. Проверенные кадры и исходники сохранены. Публикация в App Store не выполнялась.
- **Поведение:** вместо линейного filter Slider установлен `FilterKnob`: относительное вращение low-pass ↔ bypass ↔ high-pass, заметная нулевая точка, числовое значение, double-tap и отдельный Reset. Drag из центра работает вертикально; касание обода работает по углу. Первый контакт сохраняет исходное значение, переход через ±π нормализуется, пределы ограничены −1…1. Нейтральный detent — ±0.02.
- **Связь с музыкой:** Binding читает `PerformanceController.fx.filter` и вызывает существующий `setEffects`. DSP ramp, MIDI Learn, запись автоматизации, replay и экспорт используют прежний параметр. Визуальное состояние ручки не заменяет источник истины. Во время replay ручка и Reset отключены.
- **iOS и доступность:** hit target ручки 112 pt, Reset минимум 44 pt, нативное adjustable Slider representation с текущим значением и направлением LP/HP. Reduce Motion отключает дополнительную анимацию; крупный текст перестраивает FX-карточки в вертикальный стек.
- **Файлы:** `Features/FilterKnob.swift`, `Features/PerformView.swift`, `UITests/PerformControlTests.swift`; `ScreenshotTests`/`StudioTests` сохраняют C2 attachments. CI больше не ограничивает `[ui-only]` одной тестовой группой Studio: новые native test classes тоже исполняются.
- **Совместимость:** schema остаётся 7, формат проектов/автоматизации/MIDI/WAV не меняется. Кандидат — **1.0.0 (13)**, минимальная ОС — iOS 18. Старые проекты и frozen takes используют прежний аудиоконтракт.
- **Подтверждённые проверки первого запуска:** 64 Swift tests / 10 suites; независимые WAV/ZIP/voice/performance readers; 11 C++ suites; 480 EN/RU keys и contrast/font/icon audit; simulator build; unsigned iPhone SDK build и оптимизированный Release archive. В скачанном архиве проверены `1.0.0 (13)`, Xcode 26.3 / iphoneos26.2 и совпадающие UUID бинарника/dSYM.
- **Найденная проблема CI:** [43711639450](https://github.com/alexgazin/la-grilla/actions/runs/43711639450), source `4d6d656b06bac39d030541400504bfc94b0f0129`, не принят: пять запусков XCTest завершились `Failed to get background assertion` в `app.launch()` до взаимодействия с приложением. Остальные 18 Studio flows и compact capture прошли, но девять полученных C2 PNG не составляют полную коллекцию. Этот run не доказывает работу жеста.
- **Вторая проверка:** source `4fcf4c3a3594af67871d05f3d8ccefcc5dc0b70e`, [полный повтор 43713084377](https://github.com/alexgazin/la-grilla/actions/runs/43713084377). Все три Perform tests прошли: rotary/reset — 65.296 s; replay readonly — 34.622 s; крупный текст/transport — 26.514 s. Два основных capture methods прошли за 467.903 s, compact capture — за 60.003 s. В основном suite 23/24 passed; единственная ошибка — прежний MIDI UI test, который после фиксированного `app.swipeUp()` не нашёл виртуализированную Form-кнопку `midi.panic`. Итог run — failure; он не объявляется полностью зелёным.
- **Исправление и финальная регрессия:** scoped collection/table/scroll и ограниченный `reveal` до `isHittable` заменили фиксированные swipes для Learn/send/activity/output/Panic. Production source не менялся после capture. Source `bcc9f60c0dc639fe5ac6bf9f36fae6df644900b8`, [43716116613](https://github.com/alexgazin/la-grilla/actions/runs/43716116613) — **все три jobs success**: 64 Swift tests / 10 suites (25.838 s); независимые export readers; 11 C++ suites; presentation/release/project audits; simulator/iPhone SDK builds; unsigned Release archive. **22/22 native user flows, 0 failures**, 540.259 s: три Perform tests и все 19 Studio tests. Исправленный virtual MIDI flow прошёл за 34.705 s. Это `[ui-only]` run; три capture methods приняты отдельно из полного source `4fcf4c3` выше, а не выданы за повторно выполненные здесь.
- **Реальные кадры:** [55 оригинальных PNG](../Screenshots/C2) из прошедших capture methods; [manifest](../Screenshots/C2/manifest.json) содержит source/run/artifact, размеры и SHA-256 каждого файла. Крупный Perform показывает фактическое значение +67% после жеста. Все PNG проверены как RGB8, 49 Pro Max и 6 SE; двенадцать [Store копий](../Screenshots/AppStore) побайтово совпадают с оригиналами. [Ранний video preview](../Screenshots/C2-progress) помечен отдельно и не используется как Store evidence.
- **Исправление сборщика кадров:** link audit обнаружил `notes.png`, ошибочно названный `D263B9BAE7C4.png`: regex принял `C2-` внутри UUID экспортированного attachment за имя сцены. Prefix ограничен началом строки/пути. Регрессия с фактическими UUID/attachment names проверяет точное имя `notes.png`, исходные bytes, отсутствие ложного кадра у голого UUID и прямой named export; старый collector тест не проходит, исправленный проходит. Проверка включена в CI. Notes PNG побайтово сверен с исходным `NativeAttachments/main/6858E196-25BB-45B0-A5C2-D263B9BAE7C4.png`; исправлено только имя и manifest. Production app не менялся, дополнительный native run для host-only исправления не запускался.
- **Открытые внешние ворота:** физический iPhone/audio/MIDI, Apple signing, TestFlight и App Review. Проверка симулятора и unsigned archive их не закрывает.
- **Проверка точного main:** [43719321757](https://github.com/alexgazin/la-grilla/actions/runs/43719321757), source `912dc483415ad2e59c78a89c08eaa6fda38342f5` — все три jobs success: 64 Swift tests/10 suites, 11 C++ suites, collector regression, export/release/presentation audits, обе SDK и archive. 22/22 native flows, 0 ошибок (610.914 s), MIDI Form flow — 30.140 s. Четыре новых main QA attachments отделены от 55 сохранённых capture originals source `4fcf4c3`; весь каталог не переименован в новый источник.
