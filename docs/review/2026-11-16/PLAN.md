# План исполнения независимого аудита La Grilla

Дата: 16 ноября 2026. Основание: [аналитик](analyst.md), [продакт-менеджер](product-manager.md), [QA](qa.md), [архитектор](architecture.md).
Эти четыре отчёта сохраняются как независимые исходные срезы. Здесь объединены повторяющиеся находки и записано, что сделано после аудита, что требует проверки и что ещё предстоит реализовать.

**Направление продукта:** карманная студия для собственного редактируемого музыкального скетча: гармония → бит/бас/мелодия → живое исполнение → сохранение и перенос в DAW. Помощник ускоряет музыкальные действия, а автор сохраняет контроль через review, A/B и Undo.
**Текущее положение:** в main интегрирован кандидат 17 с семью пройденными recovery-сценариями и [IPA для подписи тестировщиком](../../../Builds/Testing/README.md). Следующий пакет — **1.0.0 (19), schema 10**, app/test source `0ed624a`, [PR #21](https://github.com/alexgazin/la-grilla/pull/21). Он реализует также новые скетчи и сохранение написания аккордов. Полная нативная приёмка 19 и App Store release-ready пока не объявлены. [Детальный результат исполнения](IMPLEMENTATION.md).

## Как читать статусы

- **Реализовано:** код существует; это ещё не пройденный пользовательский сценарий.
- **Проверено локально:** указанные domain/C++/host проверки действительно выполнены; их граница не включает iPhone.
- **Native Pending:** требуется завершённый exact-source Xcode/Simulator run и его корректный результат; подготовленный XCTest не считается PASS.
- **Device/model/DAW Pending:** нужны фактические результаты установленного бинарника, доступной системной модели, контроллера или внешнего приложения.
- **Запланировано:** задача остаётся в работе roadmap; экран, подпись или документация не заменяют её реализацию.

Исторические результаты сохраняют собственные источники. `5adbadb` / build 17: [focused 7](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2) — **7 PASS**, 379.622 s; Debug/archive/compatibility PASS. Это не физический повтор.
`fefa036` / build 18: [focused 11](https://github.com/alexgazin/la-grilla/actions/runs/43879719411) — **7 PASS / 2 spelling FAIL / 2 Settings-навигационных timeout**. Три FirstResult, AI fallback и три strict PCM метода прошли. Написание нот и маршрут двух новых тестов исправлены в 19; пределы и музыкальные проверки сохранены. Старый полный [run](https://github.com/alexgazin/la-grilla/actions/runs/43879719282) не наследуется новым кодом.
Для кода 19 локально прошли **186 Swift tests**, **61 CI/release host test**, presentation/release audits; DSP не менялся после 16 пройденных harnesses build 18. Новый обязательный scope — **14 focused / 63 functional native**, ещё Pending; эти числа не означают завершённые PASS.

## Реестр всех 34 находок

W1–W10 ниже — единые рабочие потоки. Один дефект не превращается в несколько независимых обещаний из-за того, что его заметили разные роли.

| Исходный ID | Поток | Состояние после аудита и следующий обязательный результат |
| --- | --- | --- |
| A-01 | W1 | Lifecycle исправлен программно; установленный полный первый сеанс остаётся Device Pending. |
| A-02 | W1 | Activation/retirement gaps сохраняются в receipts; zero-gap не принят, нужны реальные PCM/прослушивание и бюджет. |
| A-03 | W2 | Empty/starter, подсказки первого действия и постоянный пример реализованы; три native FirstResult предыдущего 18 прошли; текущий 19 и пользовательские сессии Pending. |
| A-04 | W3 | Контракт формы/гармонии уточнён; генератор новых editable MIDI-партий реализован в 19/W10, его native-приёмка Pending. |
| A-05 | W3 | Четыре языковых контракта разделены, setup/Recheck компактнее; eligible model/RU/EN Speech Pending. |
| A-06 | W4 | Mono beta/review/source сохранены; улучшение сегментации и реальная голосовая приёмка не завершены. |
| A-07 | W6 | Форматы и независимые readers есть; одинаковый скетч в двух реальных DAW Pending. |
| A-08 | W5 | Transpose, degree/chord-tone notation и сохранение написания root/slash реализованы в schema 10; native 19 Pending. |
| A-09 | W7 | Bar/beat review и компактная структура подготовлены; текущая compact/large-type/VoiceOver матрица Pending. |
| PM-01 | W1 | Audio failure не должен блокировать документы; общий путь Retry и реальный первый сеанс требуется принять. |
| PM-02 | W2 | Empty Grid показывает следующие музыкальные действия; native пустой проект → собственный звук Pending. |
| PM-03 | W2 | Пример доступен из непустой библиотеки как отдельная копия; сохранение/возврат покрываются новым native case. |
| PM-04 | W3 | Scope и происхождение повторяемых партий раскрыты; полная новая композиция не объявляется готовой по форме. |
| PM-05 | W3 | Ввод, краткий статус, раскрываемая AI setup и отдельная диктовка реализованы; compact/keyboard native Pending. |
| PM-06 | W1 | Общее ядро сохранено; seamless capture обещание ограничено до аппаратной проверки gap/indicator. |
| PM-07 | W7 | Текущий бренд сохраняется, плотность рабочих редакторов уменьшается; новые реальные кадры и доступность Pending. |
| PM-08 | W6 | Объяснения MIDI/stems/portable сохранены; перенос собственного результата и отмена проверяются до релиза. |
| QA-01 | W1 | Жалобы владельца остаются основанием для Device Pending, а не закрываются зелёным чужим source. |
| QA-02 | W1 | Реальные host gaps измерены; следующее доказательство — физический output PCM и заранее заданный бюджет. |
| QA-03 | W1 | Retirement software proof есть в `29adf6c`; повторный capture/failure/retry и системный индикатор требуют дальнейшей приёмки. |
| QA-04 | W8 | Granted Speech даёт настоящий PCM; complete typed recovery превышал 120 с, новый компактный путь Native Pending. |
| QA-05 | W3/W4 | Недоступная модель и No speech detected не выданы за успешную AI/диктовку; нужны настоящие результаты. |
| QA-06 | W3/W7 | Setup свернута и освобождает ввод; UI/VoiceOver/large type и сохранение запроса требуют нового прогона. |
| QA-07 | W8 | История failures сохранена; нынешний зелёный main и root-cause старой нестабильности — разные факты. |
| QA-08 | W9 | Введены frozen reports, этот PLAN и отдельные receipts; финальные README/release summary обновляются по exact-source. |
| ARC-01 | W1 | Kernel/MIDI/lease/observer/pending-retirement ownership сохранены; software и device gates разделены. |
| ARC-02 | W8 | `lg_create` содержит constructor exceptions; outer + 34 nested allocation failures и recovery реально проверены. |
| ARC-03 | W1 | Stop timing instrumentation реализована; wall-clock stages/Dictation totals ещё собираются, phone budget не заявлен. |
| ARC-04 | W8 | Узкий `History.applyMix` fast path и проверки подготовлены; host evidence отдельно, настоящий UI/device frame budget Pending. |
| ARC-05 | W8 | Lightweight metadata/одиночный autosave refresh реализованы; P3/50 host list ускорен в 57.37×, device RSS/launch Pending. |
| ARC-06 | W8 | Actor rename с canonical read/revision CAS/modified/backup реализован и проверен шестью domain tests. |
| ARC-07 | W9 | Software/beta/release-ready gates разделены и формализуются receipts; physical matrix/signing/review ещё не приняты. |
| ARC-08 | W8 | Native shards/watchdog/evidence collection подготовлены; новый полный coherent run всех обязательных частей Pending. |
| ARC-09 | W10 | Domain commands/metadata/mix boundaries усиливаются без переписывания стека; дальнейшее расширение требует отдельных контрактов. |

## W1 — Первый звук, захват и непрерывность музыкальной работы

Реализовано: output-only старт без inputNode, разрешённый input с реальными форматами, lease ownership, безопасные callback actor boundaries и retirement старого input-enabled I/O graph после Stop. Новый playback graph использует прежние kernel, rate, MIDI hub, queues, generations и проект; failed retirement повторяется без оживления старого input graph.
Добавлена узкая диагностика Stop: monotonic wall-clock tap removal / worker drain / output restore / total, отдельно Dictation endAudio/task.finish. Это измерение текущего синхронного пути, а не незаметная переделка его concurrency и не обещание задержки.

Дальше: завершить complete granted Speech/typed recovery; повторить Voice→Stop→Dictation→Stop→Voice, Cancel/count-in, background/interruption, route change, denied/revoked и failure→Retry. Проверить одно понятное сообщение для одной аудиоошибки.
На устройстве записать сигнал до/во время/после activation и retirement, фактические gaps относительно buffer baseline, musical phase, потерянное/сохранённое начало фразы и mic indicator. Сначала зафиксировать приемлемый бюджет и метод измерения, затем принимать результат.
Если worker drain/Speech append занимает неприемлемое время, следующий отдельный fix — asynchronous completion с явным stopping state и сохранением lease ownership; произвольный перенос AVAudioEngine на другую очередь запрещён самим контрактом владения.

**Выход:** exact-source native receipt + установленный device receipt, без crash/потери проекта/двух render owners, рабочий повторный capture и честно измеренный переход. Зависимость для всех публичных live/voice обещаний.

## W2 — Первый собственный музыкальный результат

Реализовано: выбор Empty/Starter, starter с реальными редактируемыми партиями в выбранных BPM/key/mode/length; empty остаётся пустым. Grid показывает добавить первый аккорд / перейти к биту. Постоянный Open example создаёт отдельную копию и не включает воспроизведение неожиданно.
`ProjectTemplatesTests` проверяют форму, уникальные IDs, границы, nonzero/silent rendering, Undo и сохранение. `FirstResultTests` подготовлены для empty→свой аккорд→реальный output→reopen и starter/example→возврат к своей работе.
Переходы документов сериализованы token-ом; принятый MIDI/edit на awaited границе отменяет переключение и сохраняет свежую работу. Уже записанный, но не открытый новый документ виден в Projects. Active Retry валидирует диск до checkpoint; SaveCopy выводит known-bad workspace в проверенную здоровую копию, не перезаписывая повреждённый source.
Новый continuation probe вызывает настоящий `Session.applyMIDI` на checkpoint/read/candidate boundaries; в нём нет fabricated PASS, физический MIDI он не подтверждает.

**Выход:** завершённые новые native cases, затем 5–8 наблюдаемых пользовательских сессий «первый собственный скетч» с временем/ошибками и целью 5–10 минут. Скорость XCTest не считается временем музыканта. Race/active-recovery cases обязательны до интеграционной приёмки.

## W3 — Помощник с понятным и проверяемым контрактом

Реализовано: локальные Commands отдельно от FoundationModels, typed availability/reason/action, Recheck, отдельные AI request language и dictation language, сохранение введённого текста. Setup раскрывается отдельно от основного ввода. LOCAL и ON-DEVICE AI не смешиваются.
Текущая генерация предлагает форму/гармонию и повторяет либо обрезает существующие rhythm/melody источники. В review нужно показывать источники и пустые партии; на пустой гармонии jazzify даёт понятный следующий шаг, а не обещание нового трека.
Дальше: завершить native compact path без изменения 120-секундного allowance, проверить клавиатуру, RU/EN, unavailable/off/not-ready/unsupported locale, Cancel/stale/Apply/Undo и отсутствие скрытого переключения языка.
На eligible iPhone сохранить настоящие free-form prompts, model availability, выбранный locale, proposal/music, A/B и повторяемые latency/failure samples. Отдельно произнести реальные RU/EN команды; No speech detected остаётся отказом распознавания при успешном PCM capture.

**Выход:** доступный ввод и корректный fallback на любом поддерживаемом устройстве; несколько настоящих удачных model/Speech результатов на совместимом устройстве. Новый материал из пустого проекта относится к W10, а не подменяет этот acceptance.

## W4 — Напев → полезная исправляемая MIDI-фраза

Исправлены отрицательные/off-grid onset при коротком take и неполной клетке квантования; placement/CAF/store/Undo проверены. [Исследование и raw evidence](voice/README.md): все 18 329 F0 frames и 587 unquantized notes до/после совпали, качество не объявлено улучшенным; две гипотезы сегментации отклонены.
Сохранить: mono beta, исходный CAF, confidence/manual corrections, timing offset, placement в выбранную секцию и неизменный original после review/Undo/save/portable.
Development baseline: confidence-qualified F0 95.88%, onset/pitch F1 60.28% / 54.95%, с offsets 42.76% / 38.36%. Это восемь записанных development-фрагментов, не доказательство точной телефонной транскрипции.
Дальше: заранее объявить note/onset/offset/false-positive/coverage критерии и время ручного исправления. Проверить повторы, паузы, октавы, тихие ноты, наушники и speaker bleed поверх backing loop.
Изменять сегментацию по development данным с сохранением контрольного алгоритма и raw reports. Замороженный обоснованный вариант один раз проверить на зарезервированном holdout; не подбирать параметры по нему.

**Выход:** реальные размеченные фразы и сохранённые исходники; полезность относительно ручного ввода; отсутствие регрессии placement/storage. W1 предшествует hardware-приёмке этой функции.

## W5 — Музыкальная математика, нотация и перенос тональности

Реализовано в schema 10: настоящее транспонирование chords/custom voicings/slash/melody/bass, без Drums, с проверкой MIDI-диапазона/stale proposal и одной Undo. Миграции 1…8 и frozen sources сохраняют звучание/voice assets. Degree labels и Auto/Sharps/Flats — режимы отображения.
Реализовано сохранённое каноническое написание root/slash: `C♯` и `D♭` различаются в документе, Undo и portable. Auto сохраняет написанное, явные Sharps/Flats меняют только отображение. Старое утраченное написание проектов 1…9 не выдумывается. Chromatic transpose убирает несовместимое имя, octave transpose сохраняет; Undo возвращает исходное. MIDI остаётся звуковысотным форматом, обещания DAW-орфографии нет.
Аккордовые ноты учитывают интервалы: ♭3/♭9/♯9/♭5/♯11 и регистр; ступени различают C♯→♯I и D♭→♭II в C. Локально пройдены 44 целевые проверки, включая 65 качеств × 12 корней; общий пакет — 186. Новые native transposition/writing cases Pending.

## W6 — Перенос результата в реальную студию

Сохранить действующие MIDI, stereo WAV, aligned stems, portable project и независимые readers. Экспорт использует snapshot и отдельный offline kernel; MIDI не переносит встроенные тембры, stems имеют общий старт, portable включает original recordings.
Дальше: один собственный reopen-скетч экспортировать из установленного RC во все форматы. Открыть в двух записанных DAW/version; сверить BPM, markers, drum map, voicings, start/range/tail, длину/stem alignment и исходные assets.
Проверить отмену/ошибку места без partial file, Unicode названия, mute/solo/gain/pan/master semantics и независимый imported project. USB/BLE: reconnect, sustain, Panic, timestamps и stuck notes.
Произвольный MIDI/WAV import сейчас не реализован: справка должна описывать поддерживаемый portable import. Spotify — дальнейшее сведение/мастеринг/дистрибуция, не выполняемое приложением действие.

**Выход:** сохранённые эталонные файлы + реальные DAW/controller receipts. Внутренний parser или виртуальный CoreMIDI не заменяют этот результат.

## W7 — Рабочий интерфейс и профессиональная оболочка

Сохранить современный grid/transport/цветовые роли, согласованные icon/storyboard/реальную loading-анимацию, Settings и onboarding. Splash не добавляет фиктивную задержку или процент и уважает Reduce Motion; preview не считается cold-launch trace.
Подготовлены более компактный Assistant и bar/beat review; музыке отдаётся приоритет перед повторными вводными текстами. Проверить вертикальный доступ ко всем дорожкам/Bass и safe areas; расширенные options раскрывать по требованию.
Матрица: 375 pt/основной iPhone, portrait/landscape, RU/EN, Light/Dark, normal/accessibility text, клавиатура, VoiceOver/Switch Control, цели 44 pt, запись/pending/playing/stopped и отмена.
После каждого принятого UI этапа сохранять оригинальные screenshots в соответствующий каталог `Screenshots/` с source/run/attachment/hash. Не перекрашивать старые кадры и не подписывать их новым build.

**Выход:** доступные реальные действия и новые native originals; краткие пользовательские наблюдения о понятности до/после. OpenArt уместен для нужных brand/media assets, но не заменяет настоящие экраны и поведение.

## W8 — Быстрое безопасное редактирование, документы и воспроизводимая QA

Закрыто локально: `lg_create` содержит все constructor allocations; 16 C++ harnesses PASS, включая outer + 34 nested failures, unwind и recovery render. Rename использует canonical load/expected revision/строго возрастающий modified/backup; 6 meaningful tests PASS.
Metadata library реализована через bounded `ProjectSummary`, `SummaryEntry`, `listSummaries()` и `summary(id)`: никаких полных Project в каталоге. При открытии обязательны fresh canonical load/full validation; известная ошибка музыкальных данных не стирается успешным metadata refresh. Autosave обновляет один реальный summary, каталог — при открытии Projects.
Удалены повторные full validation и повторный JSON parse; future outer/frozen-source schema не перезаписывается. 17 targeted metadata/rename/revision tests PASS, включая malformed music→full-open failure, schema 1…9, backup, mismatched ID и 8 MB limit.
Host evidence сохранён в [performance](performance/README.md): P3/50 same-snapshot legacy list 8159.464 → metadata 142.218 мс (**57.37×**); один summary 2.903 мс. Linux release/warm cache, не device RSS или iPhone latency. Исходный before list 10177.557 мс хранится отдельным source.
`History.applyMix` использует проверенный value/copy-on-write certificate и нормализованное сравнение mix-only полей; музыкальные velocity edits остаются полноценными music edits. Проверки/измерения нового пути — в [MIX_HISTORY](performance/MIX_HISTORY.md); холодная validation не скрывается средним тёплым временем.
Native pipeline разбивается на обязательные functional части с bounded subprocess watchdog, свежими Simulator/TCC и always-preserved status/stdout/partial xcresult/crash evidence. Полный gate агрегирует coherent exact-source результат; focused/capture-only запуск его не заменяет.

Дальше: выполнить новый полный domain/DSP/SDK/archive/compatibility/native набор после замораживания всех правок. На устройстве снять edit/fader p50/p95, peak RSS/history/import/launch/save и 30 минут P1/P2/P3. Byte-aware history/cache/streaming import делать при подтверждённом bottleneck, не объявлять уже готовыми по новым metadata DTO.

## W9 — Достоверный кандидат и путь в App Store

Один текущий release summary связывает source/build/schema, exact software run, signed binary и hardware/model/DAW receipts. README/ROADMAP/release документы ссылаются на него, historical runs и старые media остаются отдельными источниками.
Подготовлены machine-readable device receipt/template и разделение software acceptance, internal beta и release-ready. Pending device matrix не должна выдавать production-ready и не должна мешать beta-установке, необходимой для теста.
До production submission нужны: подписанный кандидат, минимальный iOS 18 installed launch/weak-link runtime, текущий eligible iOS/model, заполненные W1/W3/W4/W6/device performance/accessibility results; затем Store screenshots/listing/privacy/support/age-rating/export metadata и App Review receipt.
Personal Team достаточно для локальной установки на свой iPhone. Paid team/signing/TestFlight/App Store Connect — последующий внешний этап; отсутствие платной команды не оправдывает остановку разрешённой разработки и программной проверки.

**Выход:** exact-source verification → merge/main verification → signed beta/device sessions → release-ready receipt → App Review/approved installation. Это разные события, каждое фиксируется фактическим результатом.

## W10 — Завершение первоначального видения и устойчивое развитие

1. **Реализовано в 19:** новый editable MIDI sketch из пустого проекта — House/Hip-hop/Jazz, 4/8/16 тактов, BPM/key/seed, реальные новые chords/drums/bass/motif, A/B, Apply/Undo, save/export. LOCAL composer создаёт ноты; настоящая модель при доступности только интерпретирует параметры. Существующая музыка не перезаписывается. Полный 8/16-тактовый луп сохраняется при повторном открытии. Native Pending.
2. **Реализовано в 19:** сохранение enharmonic writing из W5, отдельно от временной display preference; native Pending.
3. Улучшение human Voice-to-MIDI по W4 с сохранением исходника и объявленных метрик. Низкий note F1 нельзя закрывать красивой визуализацией F0.
4. Точечное разделение Session на document/export/capture coordinators по мере этих изменений; один owner каждого async job, явные cancel/stale contracts. Domain/SwiftUI/C++ стек сохраняется.

Новые meter/audio-track/AUv3/cloud-sync расширения из архитектурного обзора требуют отдельных моделей и acceptance, если входят в последующий продуктовый объём. Они не приписываются нынешнему приложению и не подменяют обязательные исходные шесть блоков.

## Этапы выполнения и условия перехода

| Этап | Действия и зависимости | Артефакт завершения |
| --- | --- | --- |
| 0. Закончить текущий интеграционный пакет | W1 lifecycle; W2 first-result/transition recovery; W3 compact Assistant; W5 transpose; W8 allocation/rename/metadata/mix/CI. | Код заморожен, локальные meaningful проверки завершены; новые known defects исправлены, текущий source однозначен. |
| 1. Принять программный кандидат | Полный domain/DSP, independent exports, generated project/localization/release audits, Debug/archive/compatibility, все обязательные native cases, новый полный результат после merge. | Coherent exact-source run и сохранённые originals/receipts. Не переносить PASS другого source. |
| 2. Принять первый физический сеанс | Установить точный бинарник; W1 полный сценарий, current iOS и minimum iOS 18, model/Speech, save/reopen и реальные route/permission cases. | Device/model receipt; crash/диагностика при отказе и повтор на исправленном source. |
| 3. Принять студийный результат | W4 human notes, W6 две DAW/USB/BLE, W7 доступность/compact, W8 30 минут CPU/memory/thermal/timing. | Измерения с методом/порогами и эталонными файлами; выявленные проблемы исправлены и повторно проверены. |
| 4. Подготовить выпуск | W9 signed beta, privacy/listing/support/screenshots/review metadata и exact-build acceptance. | Release-ready receipt, processing/submission/review/installation results отдельно. |
| 5. Довести расширенную первоначальную идею | W10 новые партии из пустого проекта, полное writing, улучшение voice; каждый шаг проходит domain/native/device приемку своей функции. | Реально работающие, редактируемые музыкальные результаты; документация перестаёт называть незавершённое готовым. |

Пока внешний device/model/DAW/signing gate недоступен, команда продолжает независимую реализацию и проверку следующих разрешённых задач. Статус этого gate остаётся Pending; ожидание не превращается в успешный результат.
