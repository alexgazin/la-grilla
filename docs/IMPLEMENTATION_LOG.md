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

Рабочий интеграционный кандидат — **1.0.0 (14), schema 8**; предыдущий проверенный baseline остаётся 1.0.0 (12), пока новая версия не пройдёт CI. Новые источники не объявляются проверенными только потому, что синтаксический parser Linux их принимает. Для C7 выполняются полные host/export checks, обе Apple SDK, optimized archive, native сценарии и новые original screenshots. Source SHA/run/merge/manifest будут записаны после фактических результатов.

Для C8 нужны реальные Apple signing ресурсы и оборудование: установленная сборка, человеческие напевы, USB/BLE MIDI, route/latency/thermal/background сессии, настоящая локальная модель, TestFlight и App Review. Независимая программная работа продолжается; недоступность этих ресурсов не превращается в выдуманную отметку «готово».

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
