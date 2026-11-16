# Независимый архитектурный аудит La Grilla — 16 ноября 2026

Роль: архитектор. Объект: действующие исходники приложения, MusicDomain, AudioDSP, хранилище, экспорт и CI.
База просмотра: ветка `fix/authorized-microphone`, commit `9fb52e01340d060f3424ae5ea3d38a90b0893b83`, кандидат 1.0.0 (17), schema 8.
Дополнительно просмотрен незакоммиченный input-retirement patch в AudioController/LiveMicrophone и его QA-контракты.
Рабочее дерево общее и продолжает меняться; номера строк относятся к моменту просмотра, окончательное доказательство должно ссылаться на финальный SHA.
Это анализ кода и локальная проверка переносимого DSP. Проверки физического iPhone, Apple Intelligence и внешнего MIDI здесь не выполнялись.

## Вывод

Основу приложения имеет смысл развивать: отдельный музыкальный домен, собственный ограниченный DSP и независимый offline render уже существуют.
Главная проблема перед релизом — надежность реальных переходов аудио и неполнота приемки финального кандидата, затем управляемость задержек и памяти.
Переписывать приложение целиком или менять SwiftUI/C++ на другой стек оснований нет.
Новый конкретный P0 в retirement patch при просмотре не обнаружен; его работоспособность на устройстве пока не доказана.
Подтвержден отдельный P1: `lg_create` выпускает исключение выделения памяти через C ABI, хотя Swift ожидает возвращаемый `nil`.

## Фактическая схема и владельцы

| Граница | Действующий контракт | Что сохранять |
| --- | --- | --- |
| SwiftUI → Session | `@MainActor @Observable`, Project как значение, History с монотонными revision | Один путь проверяемого изменения документа |
| Session → AudioController | MainActor публикует музыку и mix, UI опрашивает состояние в 30 Hz | Не принимать UI tick за точное время касания |
| AudioController → AudioDSP | Стабильный KernelHandle, три слота музыкальных/mix snapshots, ограниченные очереди | Единственный render owner для каждого kernel |
| Входной tap → InputDrain | Ограниченный C SPSC ring; конверсия, Speech и CAF на serial worker | Никаких файлов, Task, Speech или блокировок в tap |
| AI → MusicDomain | Ограниченный typed interpretation → proposal → validated candidate → Apply/Undo | Модель не получает право прямо менять Project |
| Session → ProjectStore | Actor сериализует атомарную запись manifest/backup и работу с assets | Хранилище не зависит от доступности аудиовыхода |
| Экспорт | Неизменяемый snapshot и отдельный offline kernel; WAV/stems/ZIP | Экспорт не должен трогать текущий render kernel |

Источники: `App/Session.swift:7,97,189,207,363`; `AudioRuntime/AudioController.swift:99,118,497`;
`AudioRuntime/LiveMicrophone.swift:155,174`; `Packages/MusicDomain/Sources/MusicDomain/ProjectStore.swift:3`;
`Packages/MusicDomain/Sources/MusicDomain/OfflineRenderer.swift:42`; `AudioRuntime/AIComposerController.swift:67`.

## Сильные стороны, подтвержденные кодом

- Render и legacy Speech callbacks создаются вне MainActor с явными Sendable границами; это адресует реальный класс Swift 6 runtime traps.
- DSP использует ограниченные буферы, versioned presets, связанный music/mix/layout commit и стабильные track identities для MIDI.
- RT input ограничен копированием/downmix и атомиками; переполнение становится явной ошибкой вместо неограниченного накопления.
- Project.validate ограничивает длину, дорожки, события, размер документа, числа и ссылки; History применяет проверенный candidate одной операцией.
- Save создает backup только из валидной предыдущей версии и не затирает более новый schema/revision; bootstrap не сохраняет временный demo поверх загружаемого документа.
- Voice Apply повторно проверяет project ID/revision после await записи asset; исходная запись, MIDI и исправления разделены.
- OfflineRenderer использует тот же DSP; WAV/ZIP имеют независимые readers в CI, stems явно описывают gain/pan/mute/solo/master semantics.
- On-device AI имеет конкретные причины недоступности, отдельный язык запроса, Recheck и работающие локальные Commands.
- В просмотренном runtime нет app-owned URLSession/cloud AI transport; Speech требует on-device recognition, FoundationModels остается системным локальным API.
- QA stores отделены от production; shareable input failure report исключает port names/UID/PCM. В исторических QA route snapshots имена портов есть.

## Что проверено в этом аудите и что не проверено

Локально выполнен `bash scripts/test_audio.sh`: все 15 C++ harnesses завершились успешно, включая input ring, MIDI, snapshots, timing и retirement voices.
Проверки allocation counters в этих harnesses показали ноль выделений памяти внутри измеряемого render/tap C++ кода.
Host stress P1/P2/P3: p95 90.937 / 704.944 / 492.302 мкс; это Linux host, 48 kHz, 256 frames, 12 секунд на fixture.
У P3 одиночный max 8643.37 мкс превысил buffer budget 5333.33 мкс. Это образец host scheduling, не доказательство iPhone dropout и не замена 30-минутному device trace.
Внешний fault-injection probe `/tmp/la-grilla-architecture-allocation.cpp` вывел `bad_alloc_escaped_C_API=true`; исходники приложения probe не менял.
По предоставленным координатором данным native run `43864455841` для исходного `9fb52e0`: шесть отдельных PASS, включая реальный HAL PCM/CAF после первого output-only consent, AI availability UI и splash; native suite в этом аудите не перезапускался.
Седьмой Speech journey превысил 120 секунд после grant/capture/project checks; итоговый watchdog — 124. Это не «7 PASS» и не подтвержденный authorization crash.
Эти результаты относятся к activation-only исходнику; незакоммиченный retirement patch обязан пройти новую native проверку.
Физический mic indicator, реальное распознавание речи, поддерживаемая on-device модель, USB/BLE timing, температура и touch latency остаются Pending.

## Задачи по приоритетам

### ARC-01 · P0 · Закрыть текущий пользовательский отказ аудио/микрофона

Статус: отказ сообщен владельцем; исправление I/O activation подготовлено, retirement еще требует native/device приемки.
Доказательства: `AudioController.swift:283,330,353,395`; `LiveMicrophone.swift:126,235,280`; `docs/release/DEVICE_ACCEPTANCE.md:9`.
Retirement правильно останавливает старый input graph до старта нового, сохраняет kernel/MIDI/sampleRate/queues и публикует только работающий replacement.
Pending retry не должен возрождать старый input-enabled graph; lease ID и expected-engine guard защищают от позднего cleanup; observer проверяет identity.
Действия: проверить outputOnly first grant, повторную запись с уже выданным доступом, Stop/Cancel, Speech→Voice→Speech, отказ запуска replacement и последующий Retry.
Приемка: фактический PCM/CAF, неизменные kernel/project/revision/MIDI, ровно один работающий граф, old graph stopped, новый граф без inputNode, продолжающийся callback clock.
На iPhone дополнительно записать поведение privacy indicator и слышимые/измеренные разрывы; сохраненный sample clock не означает непрерывный звук по wall time.
Зависимости: окончательный lifecycle patch, QA receipt с честным `sameEngine=false` при retirement; затем exact-SHA native CI и установленный кандидат.

### ARC-02 · P1 · Не выпускать allocation exceptions через C ABI

Статус: воспроизведено отдельным fault-injection C++ probe.
Доказательства: `AudioDSP/GrillaKernel.cpp:288`, `AudioController.swift:22`, `OfflineRenderer.swift:49`; `LiveInputBuffer.cpp:25` уже обрабатывает аналогичный случай.
`new LGKernel(sr)` и вложенные vector allocations могут бросить `std::bad_alloc`; Swift guard получает `nil` только при корректном возврате C API.
Действия: перехватить construction failures внутри `lg_create`, вернуть nullptr; сохранить полное RAII освобождение частично созданных members.
Приемка: fault injection на внешней и нескольких вложенных allocations возвращает nullptr, не выпускает исключение, следующий нормальный create/render работает.
Проверить существующие render allocation/PCM/snapshot harnesses после правки; runtime cache/musical behavior не менять.
Зависимости: нет; это небольшой изолированный fix. Он не дает обещания восстановиться после системного jetsam.

### ARC-03 · P1 · Измерить и ограничить работу Stop на MainActor

Статус: синхронное ожидание подтверждено кодом; UI hitch/deadlock на телефоне в этом аудите не воспроизведен.
Доказательства: `LiveMicrophone.swift:194,210,235`; `DictationController.swift:15,22,142`; `MIDIOutputWorker.swift:44`.
InputResources.stop вызывает worker.finish через queue.sync; очередь может в это время выполнять CAF write или Speech append, а main может ждать SpeechRequestHandle.lock.
Действия: отдельно измерять tap removal, drain/close, session category и graph retirement; если превышен UI budget — асинхронно ждать worker с явным stopping state.
Сохранить сериализованное управление AVAudioEngine/session, token ownership и запрет нового владельца до определенного безопасного handoff.
Приемка: slow sink и delayed Speech не блокируют интерфейс неопределенно; Stop завершает tap сразу, не допускает двойного finish/новой записи поверх cleanup, сохраняет draft/error.
Зависимости: ARC-01 и device signposts; не переносить вызовы AVAudioEngine на произвольную очередь ради косметического ускорения.

### ARC-04 · P1 · Убрать масштабирование стоимости любого edit по всему проекту

Статус: тяжелый путь MainActor подтвержден; его p95 на реальном iPhone пока не измерен.
Доказательства: `Session.swift:189,196`; `Model.swift:250,300,354`; `AudioController.swift:497`; `Compiler.swift:8`.
History.apply валидирует candidate с компиляцией нот и JSON encode; sync снова компилирует музыку, включая mixer gestures. DSP callback от этого отделен, UI — нет.
Действия: получить signposts на P1/P2/P3; отделить проверку mix-only edit от структурного edit, кэшировать compilation по музыкальному revision/layout с проверкой эквивалентности.
Не ослаблять import/full-document validation и не отдавать DSP непроверенные либо частичные поколения.
Приемка: measured edit/fader p50/p95, стабильный UI frame budget на целевом устройстве; compiled music/export совпадают; live layout/MIDI suites остаются зелеными.
Зависимости: воспроизводимые project fixtures, ARC-01; оптимизировать подтвержденный bottleneck, не весь домен заранее.

### ARC-05 · P1 · Ограничить память библиотеки и стоимость каждого autosave

Статус: O(число проектов × полная загрузка/валидация) подтвержден кодом; OOM устройства не воспроизведен.
Доказательства: `ProjectStore.swift:26,31`; `Session.swift:103,207,217`; `Model.swift:355,361`; `ProjectArchive.swift:93`.
Entry держит полный Project; list загружает/валидирует каждый manifest и вызывается после каждого save. History держит до 80 value snapshots, portable import читает до 128 MB.
Действия: сначала снять peak RSS/launch/save latency для 1/25/100 проектов; затем lightweight listing metadata + загрузка выбранного документа, ограниченный cache и byte-aware history budget.
Поддержать поврежденные/future-schema документы как отдельные записи recovery; не скрывать ошибки ради ускорения каталога.
Приемка: измеренные launch/save/peak-memory budgets на минимальном поддерживаемом устройстве; библиотека не держит все большие документы; backup/last-opened/recovery сохраняются.
Зависимости: ARC-04 fixtures; для ввода больших архивов оценить streaming decode отдельно, без обещания произвольного размера.

### ARC-06 · P2 · Привести Rename неактивного проекта к revision contract

Статус: конкретное расхождение подтверждено кодом, случившаяся потеря rename не установлена.
Доказательства: `Features/ProjectsView.swift:25`; `ProjectStore.swift:18,37`; `Model.swift:358`.
Ветка неактивного проекта меняет copy.name без revision/modified; содержимое меняется с прежним revision и не обновляет порядок по времени.
Действия: metadata transaction/rename в одном owner с expected revision, проверкой имени, новым revision/modified и сохранением backup.
Приемка: rename активного и неактивного документа одинаково меняет revision/time; stale snapshot не отменяет rename; ошибка записи оставляет прежний документ.
Зависимости: нет; не создавать отдельную несогласованную систему revision только для каталога.

### ARC-07 · P1 · Разделить software gate, beta и фактический release-ready

Статус: существующий exact-source CI gate хорош, но не проверяет физическую приемку.
Доказательства: `distribution.yml:28,46`; `require_native_acceptance.py:5,28`; `DEVICE_ACCEPTANCE.md:27`.
Действия: добавить версионированный device/model receipt с source/build/route и результатами, проверяемый перед статусом release-ready/App Review.
Внутренний TestFlight может оставаться неприемленной beta для проведения этих тестов; Pending C8 не следует выдавать за завершенную приемку или запрещать тестовую установку.
Приемка: CI, beta upload, устройство и App Review имеют отдельные результаты; stale SHA/неполный receipt не дает release-ready; секреты в отчет не попадают.
Зависимости: ARC-01, закрытие открытых full regression failures, доступная реальная device/model сессия и затем дистрибуционная учетная запись.

### ARC-08 · P1 · Сократить цикл надежной native проверки

Статус: focused workflow уже имеет watchdog; общий workflow остается длинным монолитом.
Доказательства: `.github/workflows/ios.yml:12,61,83,126`; `.github/workflows/microphone-recovery.yml`; outcome run `43864455841`.
Действия: распространить bounded subprocess supervision и always-preserved stdout/status/crash evidence; разделить audio-permission, functional UI и screenshot сценарии на независимые свежие Simulator jobs.
Сохранить coherent exact-SHA aggregation; screenshot-only/focused successes не должны замещать функциональную приемку; не увеличивать method timeout вместо устранения лишней навигации.
Приемка: hung test останавливается до job timeout, его частичный log/artifact сохраняется; все обязательные shards одного SHA участвуют в общем результате.
Зависимости: существующий focused supervisor; измеренный runtime каждого shard и проверка TCC isolation.

### ARC-09 · P2 · Закрепить интерфейсы перед расширением музыкальных функций

Статус: поддерживаемость; существующая функциональность не требует переписывания.
Доказательства: `Session.swift:7–453` объединяет UI navigation, edits, I/O lifecycle, persistence, export и MIDI; `Features/GridView.swift`, `AssistantView.swift` содержат плотные ViewBuilder paths.
Действия: при следующих изменениях выделять маленькие компоненты и typed commands; Session оставить координатором. Сначала вынести export job и document metadata operations, затем общий capture state contract.
AI расширять через новые валидируемые domain operations; текущая модель описывает форму/гармонию и копирует исходные rhythm/melody (`AIComposerController.swift:134`).
Новые drums/bass/motif generation, размеры кроме 4/4, arbitrary audio tracks, AUv3 или sync потребуют отдельных моделей/limits/migrations; в текущей реализации это не готовые возможности.
Приемка: один owner у async job, cancel/stale guard виден в одном месте; изменение фичи не требует обходить History/validation или писать непосредственно в kernel из View.
Зависимости: сначала ARC-01/02/06; рефакторинг только вместе с конкретным изменением и существующей behavioral проверкой.

## Последовательность выполнения

1. **Стабилизация кандидата:** ARC-02 и ARC-06 параллельно; ARC-01 lifecycle и QA, точный SHA, build/archive/compatibility и завершенная native regression. Screenshot provenance хранить отдельно от PASS.
2. **Приемка на телефоне:** repeated capture/Stop/Retry, Speech grant+actual frames, global AI readiness+supported locale+real proposal, save/reopen/export, microphone indicator, route/background/interruption. Зафиксировать source/build/device.
3. **Предсказуемая производительность:** ARC-03/04/05 — signposts и память P1/P2/P3, затем узкие исправления измеренных задержек; 30 минут mixed-use и два реальных DAW imports.
4. **Устойчивый release pipeline:** ARC-08, ARC-07; собрать один coherent source receipt с software, hardware/model и media provenance. Лишь затем объявлять release-ready.
5. **Развитие продукта:** ARC-09 и согласованный продуктовый backlog; новые возможности сохраняют deterministic edit/export/Undo и ограничения устройства.

Готовность каждого этапа определяется воспроизводимым результатом и связанной версией, а не числом реализованных экранов или наличием красивого промо.
