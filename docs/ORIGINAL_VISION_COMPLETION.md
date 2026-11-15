# Полное исходное видение — технический план реализации

Обновлено: 15 ноября 2026. Исходная база сверки: `1ddf660`, 1.0.0 (12). Последний принятый `main`: `912dc483`, 1.0.0 (13), exact-main run `43719321757`. Интеграционный кандидат: 1.0.0 (14), schema 8; его финальная приёмка продолжается. Источник цели — первоначальная идея владельца и последующая сверка с кодом.

Рабочая ветка: `feat/complete-original-vision`. Детальные факты каждого этапа записываются в [журнал реализации](IMPLEMENTATION_LOG.md); общий статус — [ROADMAP](../ROADMAP.md).

## 1. Функциональные пробелы на момент исходной сверки

| Область | Работает в исходной базе | Незакрытая на старте часть |
| --- | --- | --- |
| Музыкальная модель | Такты/PPQ 960, секции, до 8 дорожек и 64 тактов; единый compiler для playback/MIDI/WAV; History, autosave и recovery | Полноценное редактирование и перенос целых клипов в аранжировке |
| Сетка | Мультитрек, pinch, long-press перенос аккордов; piano roll с переносом/resize нот | Перенос/копирование/resize клипов; совместимые междорожечные drop; перестановка секций пальцем |
| Голос/текст | On-device Apple Speech, RU/EN ограниченный парсер, preview/Apply/Cancel/Undo | Реальная генеративная модель, свободная формулировка, создание многосекционной песни и естественная команда «поджазовать» |
| Гармония | 23 семейства, расширения/альтерации, slash/inversions, четыре алгоритмических стиля, A/B | Дополнить практический джазовый каталог/синонимы; формулы пользователя; музыкально корректное опускание необязательных ступеней |
| Jam | 16 пэдов, quantize, overdub, step editor, непрерывная обычная навигация | Добавление/удаление дорожек и структурные операции вызывают Stop; A/B перезапускает фрагмент |
| Микрофон | Запись mono до 30 s, YIN, confidence, ручная правка, исходник и экспорт | Захват поверх работающего бита; общий duplex audio graph; реальная человеческая приёмка качества |
| DJ | Запуск секций, jumps/repeat, low/high-pass, ping-pong delay, запись/replay/export исполнения | Настоящая круговая ручка вместо Slider и её взаимодействие/доступность |
| Mixer/export/MIDI | Вертикальные фейдеры, pan/M/S/master; MIDI/WAV/stems; Core MIDI USB/BLE/Learn/Panic | Повторная интеграционная проверка после новой модели; физические MIDI/маршруты/DAW |
| Выпуск | Современный UI, 54 PNG, 12 Store-копий, privacy/store/support, archive/signing scripts | Новый финальный RC, установленная подписанная сборка, физическая приёмка, TestFlight/App Review |

## 2. Правила завершения

1. Работа продолжается автономно по исходному поручению владельца. Параллельные задачи имеют явные границы файлов и единые контракты данных.
2. «Реализовано» означает настоящий связанный сценарий: действие → данные → звук/экспорт → Undo/save/reopen. Декоративная кнопка, заглушка модели или нарисованный скриншот критерием не являются.
3. Для этапа нужны подходящие поведенческие тесты, native SDK-проверка и UI-проверка изменённого сценария. После визуального изменения снимаются реальные оригинальные кадры с source/run/hash.
4. Проверенные этапы идут через PR в `main`. Для финального `main` проходят все необходимые проверки именно этого коммита. Диагностические ветки не заменяют интеграцию.
5. Никакой потери старых проектов/исходных голосовых файлов. Новая семантика получает schema migration; старые приложения должны отклонять более новую схему, сохраняя оригинал.
6. Music/mix/preset layout принимаются согласованно. В audio/input callbacks нет файлового I/O, блокировок, акторных переходов и неограниченных аллокаций.
7. Не выдавать ограниченный regex за генеративный ИИ. Наличие/язык локальной модели проверяются реальным API. На неподдерживаемом устройстве сохраняется рабочий локальный режим с явной границей возможностей.
8. Не помещать API-ключи в iOS-клиент, репозиторий, артефакты или чат. Запросы к внешнему провайдеру возможны только через безопасный сервер и явно выбранный пользователем режим.
9. Физические измерения, человеческий голос, Apple signing и App Review нельзя закрыть результатом симулятора. Это реальные внешние зависимости, а не основание оставить независимую разработку незавершённой.

## 3. Этапы и зависимости

| Этап | Результат | Зависимость | Статус |
| --- | --- | --- | --- |
| C0 | Сверка исходных идей, подробные контракты и журнал | База 1ddf660 | План и журнал записаны |
| C1 | Расширенная гармоническая модель и schema 8 | C0 | Host и отдельные native сценарии прошли; финальная регрессия C7 впереди |
| C2 | Настоящая круговая DJ-ручка | C0 | Native приёмка пройдена; слито в main, PR #14 |
| C3 | Clip/section arranger: операции и жесты | C0; интеграция с C1/C4 | Clip операции реализованы; e428 short drag intermittent, новый anchored pinch ожидает native44/C7 приёмку |
| C4 | Атомарные live-правки и непрерывный transport | C0; принимает C1/C3/C6 | Host DSP/MIDI, native live edits и drum overdub прошли; расширенная audition-регрессия ожидает C7 |
| C5 | Общий duplex микрофон и голос поверх бита | C4 | Focused cold/warm реальная CAF/analysis/review/store/Undo цепь прошла; render timestamp gaps/физическая непрерывность отдельно, финальная регрессия C7 впереди |
| C6 | Свободный AI Assistant и многосекционные предложения | C1/C3/C4; диктовка C5 | Commands/native review проверены; реальная модель — C8 |
| C7 | Интеграционная стабилизация и новый RC | C1–C6 | 118 Swift tests/19 suites,15 C++ и603 EN/RU keys проходят; полная native44/capture73 приёмка идёт |
| C8 | Установленная сборка, устройства, TestFlight/App Store | C7 и реальные ресурсы | Внешняя приёмка открыта |

Порядок интеграции: данные/безопасность → простые независимые контролы → аранжировка и live audio → duplex → AI → общая приёмка. Параллельная разработка не означает зависимость UI от ещё несуществующих API в `main`.

## C0. Базовая сверка и рабочий журнал

**Сделать:** сохранить матрицу выше, отделить готовые функции от ограниченных и от непроверенных на устройстве. Зафиксировать базовый SHA/схему/версию, контракты совместимости, границы каждого этапа и правила доказательств. Уточнить README/ROADMAP: после R0–R10 остаются функциональные этапы C1–C7.

**Артефакты:** этот документ; `IMPLEMENTATION_LOG.md`; ссылки из ROADMAP/README. Никаких новых обещаний о качестве модели/микрофона или состоявшейся публикации.

**Готовность:** план находится в репозитории, список пробелов покрывает все шесть исходных блоков; первый этап разработки уже начат.

## C1. Гармонический каталог, формулы и совместимость

**Данные:** сохранить существующие `Quality` raw values и Codable поля. Добавить практические семейства dim7, minor-major, расширенные major/minor, 6/9, sus/add и сочетания альтераций. Парсер различает `C7`, `CM7`, `Cm7`, символы ♯/♭/Δ/ø/° и slash-бас; внутренний формат остаётся каноническим.

**Произвольные формулы:** опциональный `Chord.customIntervals`, 2–8 строго возрастающих уникальных интервалов 0…48, обязательно 0. Каноническое представление и parse/symbol round-trip, включая отдельный slash-бас. UI редактора должен позволять ввести/проверить формулу, показать реальные ноты, прослушать, применить или отменить. Ошибка не меняет музыку.

**Voicing:** стандартные расширения могут опускать только явно необязательные ступени. Сохранять идентичность терции/септимы/альтерации/главного расширения. Пользовательская формула сохраняет заданные интервалы; без произвольных посторонних нот. Крайние регистры дают понятную ошибку либо допустимое размещение, а не неверный аккорд.

**Migration:** schema 7→8; обратное чтение прежних схем и frozen performance sources. Проверить плотность compiler/export при максимальном числе нот и slash-басе; validators и JSON-предложения учитывают optional formula. Не менять существующим проектам preset version или музыку при простом открытии.

**Проверки:** все 12 корней × каталог; алиасы/энгармоника; неизвестные/вредные формулы; сложный slash; round-trip; допустимые/недопустимые omissions; исходные JSON/portable packs; одинаковые pitches MIDI/WAV/playback; Apply/Undo/save/reopen.

**Native/кадры:** редактор расширенного аккорда и формулы, Harmony A/B, RU/EN, узкий экран. Закрывать этап только после SDK/UI-проверки и миграционных тестов.

## C2. DJ — круговой фильтр

**UI:** круговая шкала low-pass ↔ bypass ↔ high-pass, заметный нейтральный detent и числовое значение; реальный rotary drag без скачка при первом касании и переходе углового разрыва. Reset минимум 44 pt; сама ручка удобна пальцем. Состояние отключения при replay и доступность значения видимы.

**Связь:** та же `PerformanceController.setEffects` и существующие DSP ramps, запись автоматизации/replay/export. Не создавать вторую несвязанную переменную только для картинки. MIDI Learn/filter должен менять тот же параметр.

**Доступность:** adjustable Slider representation, локализованные имя/значение, Reduce Motion/Contrast/Transparency по общей теме, крупный текст. Проверить minimum/neutral/maximum, reset и disabled.

**Приёмка:** native касание меняет настоящий эффект, значение и сохранённое исполнение; reset возвращает bypass. Реальные кадры обычного/крупного UI; существующие PCM/CC regression остаются зелёными.

## C3. Аранжировка клипов и секций

**Domain API:** отдельные чистые операции move/copy/resize с project ID, revision, clip ID и destination. Snap, bounds и overlap проверяются до изменения. Copy создаёт независимые pattern/source references с сохранением исходного голоса; move сохраняет музыкальный смысл offset/repeat. Схема не должна позволять пересечь несовместимые типы содержимого.

**Совместимость:** перенос между совместимыми дорожками действительно переносит данные. Барабаны не превращаются молча в мелодию; производный root bass не выдаётся за редактируемый MIDI-клип. Объяснять недопустимый drop. Увеличение таймлайна ограничено 64 тактами, выполняется в одной транзакции и не растягивает посторонние клипы.

**Жесты:** явный режим Clips, перемещение блоков пальцем, copy, resize-ручки, target highlight и отмена. Сохранить редактирование аккордов/нот и pinch/scroll arbitration. Drag payload не доверять: иностранный проект, устаревшая revision, неизвестный clip/section отклоняются.

**Секции:** прямой drag меняет порядок вместе со всем содержимым. Корректно разрезать/перенести пересекающие границы экземпляры, учитывать повторения/offset/voice source. Один жест = одна Undo-транзакция.

**Piano roll:** открывать конкретный clip через `Session.noteClipID`; playhead/редактирование привязаны к его start/offset, даже если он не начинается на границе секции.

**Проверки:** move/copy/resize каждого поддерживаемого типа; foreign/stale; overlap; clip за концом; section reorder с crossing clips; source hash/reference retention; Undo/Redo/round-trip; live commit из C4. Native жест, а не вызов доменной функции вместо жеста.

## C4. Непрерывное live-редактирование

**Проблема базы:** ноты принимаются на границе такта, а mixer/preset layout мог меняться сразу. Простое удаление `audio.stop()` переносит риск на неверные индексы, MIDI и фейдеры.

**C API:** атомарный project snapshot: notes, BPM, range/loop, revision, layout token, track mix/presets/master/FX. Согласованное принятие на музыкальной границе; stopped принимает сразу. Старый API сохраняется для проверенных export/legacy callers. Revision-aware mix update не применяет новый layout к старой музыке.

**Kernel:** без Stop/seek/restart при обычных live edits; сохранить sample clock/playing и определённую фазу. Смена layout освобождает старые live MIDI/sustain/voice references, не направляет их на другую дорожку. Pending/latest-wins, Panic/Stop имеют приоритет; render callback не аллоцирует и не ждёт.

**Session:** добавление/дублирование/удаление melody, bass toggle и секции используют новый safe commit. Показать pending commit до реального принятия; MIDI/controller mapping конфигурировать согласованно. Не помечать данные применёнными только по отправке команды.

**A/B:** при уже работающем Jam менять гармоническое предложение на границе без перезапуска барабанов/общего clock. При остановленном transport разрешён отдельный явный audition. Выход из A/B восстанавливает исходную музыку без отката времени к старой позиции. Preview не записывается в project; Apply одна History-транзакция.

**Проверки:** реальные PCM/C API для add/remove/layout swap/preset/mix, старые Off перед новыми On, отсутствие early remap, неподвижный playing flag, монотонный clock, no callback allocations, dense fixtures. Native проигрывание → новый bass/melody → section drag → A/B → Undo, без нажатия Play заново.

## C5. Голос поверх работающей студии

**Архитектура:** один существующий AVAudioEngine graph и input tap; single-owner lease на потребителя микрофона, а не запрет output playback. Voice capture и dictation не создают конкурирующий output transport. Permission только по действию пользователя; monitoring off, наушники рекомендованы.

**Realtime transport:** bounded SPSC mono ring из входного callback, ограниченная длительность/память. Дренирование/конверсия/CAF file I/O и Speech append вне realtime callback; переполнение выдаёт ошибку, не скрытую потерю начала. Сохранять source timestamps/rate/latency metadata и исходные PCM.

**Audio session:** playAndRecord, корректный input/output route, обработка categoryChange без безусловного `Session.interrupt()/audio.reset()`. Реальное изменение формата и interruptions обрабатываются с сохранением transport intent/позиции; никакого тайного fallback на Stop ради успешного теста. После Stop/Cancel снимается tap/lease, запись в фоне не продолжается.

**Запись:** count-in без второго несогласованного clock; фиксировать beat/offset относительно backing timeline, правильный старт размещения записанных нот. Pause/cancel/permission denied/route loss не повреждают уже записанный source. Apply добавляет ноты во время работающего бита через C4. Original solo audition — отдельное понятное действие.

**Проверки:** bounded buffer order/overflow/ownership, resample, PCM/source hash, cancellation/races; native Start/Stop/Cancel capture с продолжающимся output clock. Синтетическая проверка помечается fixture; не выдавать её за живой напев. Реальные голоса/акустическая утечка/маршрутная задержка — C8.

## C6. Настоящий Assistant и структура песни

**Три слоя:** (1) typed domain proposal; (2) local intent/parser fallback; (3) реальная generative provider adapter. UI показывает активный режим/доступность, происхождение и scope. Apple FoundationModels используется только при доступности framework/OS/device/model/language; не обещать LLM на любом iPhone.

**Свободный ввод:** пользователь описывает интро/куплет/припев/бридж, размеры и аккорды. Модель формирует bounded structured intent, после чего domain строит candidate. Несколько секций и гармоническая стилизация входят в одну понятную transaction. «Поджазовать», «сделать мягче/сложнее», tonal context имеют настоящую связь с HarmonyLab.

**Схема предложения:** project ID/base revision/scope; не более 8 секций/64 тактов/8 дорожек; chord literals проходят Chord.parse; durations и coverage проверяются. Сохранять track IDs/mix/voice assets при перестройке. Использование/повтор/обрезка имеющейся ритмики явно отображается в assumptions. Ошибку модели/unsupported intent не превращать молча в случайный трек.

**Review:** до/после всех затронутых секций, BPM/key, предупреждения про trimming/reuse/chromaticity, A/B, Apply/Cancel, одна Undo. Stale/duplicate/cancel после новой генерации блокируются. Текст/диктовка — одинаковый pipeline; Apply во время playback использует C4.

**Провайдеры/приватность:** по умолчанию локально. Интеграционный контракт допускает серверного провайдера, но пустой URL/нет credentials не считаются работающим облаком. Любой внешний режим требует реального endpoint, серверного ключа, disclosure и нового privacy audit. Модели и SDK проверять по актуальным официальным API, не по предполагаемым названиям.

**Проверки:** RU/EN intent corpus; whole-song/multi-section/reorder/style; неверный JSON, чужие IDs, malicious prompt, слишком большой ответ, unsupported chords, network/model unavailable/cancel; one Undo/save/reopen/MIDI/WAV. Native review/apply/undo с явно помеченным deterministic fixture; отдельно реальный on-device model acceptance на C8.

## C7. Общая стабилизация и RC

1. Прогнать domain + independent MIDI/WAV/ZIP/CAF readers + все C++ timing/concurrency/allocation suites. Не заменять реальные regression проверкой равенства констант.
2. Перегенерировать Xcode project, согласовать version/build и schema. Обе SDK-сборки и оптимизированный archive/dSYM/privacy/resources на актуальном App Store toolchain.
3. Native сценарии всего исходного видения: клипы/секции пальцем, непрерывный loop при структурных правках и A/B, circular filter/record/replay, AI whole-song review/apply/cancel/Undo, shared voice capture, exports и MIDI regression.
4. RU/EN, dark/light, 375 pt, large text, landscape, VoiceOver semantics, Reduce Motion/Transparency/Contrast; минимум 44 pt для стандартных контролов и доступные альтернативы точным музыкальным canvas.
5. Реальные PNG в `Screenshots/OriginalVision/`; дополнительные сцены новой функциональности; 12 соответствующих Store-копий без выдуманного UI. Source/run/dimensions/SHA-256 и явные fixture labels.
6. Обновить metadata, support/privacy, review notes и руководство сценариев. Проверить, что описание не обещает модель/язык/качество или аппаратную задержку без доказательства.
7. PR/merge в main, все обязательные checks точного main SHA. Только затем программный этап считается завершённым.

## C8. Внешняя приёмка и публикация

**Устройство/звук:** установленная подписанная сборка на минимально поддерживаемом и актуальном iPhone; 30 минут P1/P2/P3, CPU/thermal/memory/dropouts; touch/audio/MIDI timing; speaker/wired/USB/Bluetooth; call/Siri/unplug/media reset/background; mic/speech denied.

**Реальный голос/ИИ:** человеческие голоса/свист/вибрато/глиссандо/повторы/шум и зафиксированный набор ожидаемых нот; качество pitch/onset, UI коррекция и headroom. Реальные FoundationModels/model language/availability/latency; unsupported device fallback; adversarial/ambiguous requests.

**MIDI/DAW:** USB и BLE input/output, sustain/Learn/Panic, unplug/reconnect; импорт MIDI/WAV/stems и source assets в две DAW. Установленный RC, а не только host-generated fixture.

**Apple:** signing/certificate/profile/account data → TestFlight → device acceptance → listing/privacy/age rating/rights/export compliance → App Review → production smoke. Секреты в owner-controlled secrets; не в переписке. Процедура — [release](release/RELEASE.md), фактическая форма — [DEVICE_ACCEPTANCE](release/DEVICE_ACCEPTANCE.md).

Эти пункты остаются открытыми при отсутствии реального устройства/модели/Apple доступа. Все независимые программные этапы C1–C7 продолжаются; отсутствие аппаратуры не используется для остановки разработки или фиктивного закрытия приёмки.
