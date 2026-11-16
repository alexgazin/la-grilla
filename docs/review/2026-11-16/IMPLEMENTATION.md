# Итог работ после независимого аудита — кандидат20

**Срез:** 16 ноября2026, **1.0.0 (20), schema10**. Пакет20 добавляет полный диапазон первого portable-import/повторного открытия и уточняет возможную паузу начала/завершения записи; результаты19 ниже остаются отдельными источниками. Интеграционные изменения находятся поверх `fefa036ace0e10713689a8d22c3c0b69abfc0fbf`; это SHA кандидата 18, а не приёмка нового кандидата 19.
Полный реестр **34 находок**, приоритеты, зависимости и этапы остаются в [PLAN.md](PLAN.md). Четыре независимых исходных отчёта не переписывались. Ниже — результат исполнения и границы имеющихся доказательств.

## Что действительно проверено

| Проверка | Фактический результат | Граница вывода |
| --- | --- | --- |
| Текущий музыкальный domain | **186 tests PASS** на host | Включает writing/sketch/projection regression checks; native-путь кандидата 19 ещё Pending. |
| C++ DSP | **16 harnesses PASS** для DSP source кандидата 18; в пакете 19 этот source не изменён | Сохраняются allocation/snapshot/MIDI/render проверки; аппаратный timing не установлен. |
| CI/release gate scripts | **63 checks PASS**, включая SDK/native retry и два воспроизводимых unread-console случая | Receipt остаётся привязан к фактическому native job attempt; старый receipt нельзя принять после нового native retry. |
| Кандидат 17, source `5adbadb37c39911c4acc2c2ef511198867098040` | [43876565702, attempt 2](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2): **7 native PASS**, 379.622 с; Debug/archive/compatibility также прошли | Software repair подтверждён своим source. Физический телефон остаётся Pending. |
| Кандидат 18, source `fefa036` | [43879719411, attempt 1](https://github.com/alexgazin/la-grilla/actions/runs/43879719411/attempts/1): **7 PASS / 2 assertion FAIL / 2 execution allowance timeout**, exit 65, финализированный xcresult | Три FirstResult действительно прошли. Общей приёмки 11 методов нет. |
| Кандидат 19, source `f005854` | [Focused 43890521487](https://github.com/alexgazin/la-grilla/actions/runs/43890521487): **13 PASS / 2 assertion FAIL / 0 timeout**, 700.813 s, exit 65; Debug/archive/обе compatibility PASS | Sketch/writing/harmony/AI/PCM методы прошли. Исправлены два Transposition test defects; новый focused 16/full 64 Pending. Полный 43890521274 завершился FAILURE: потеря связи с hosted runner, нативные исходы неизвестны. |

Локальные проверки и старые Simulator PASS не заменяют установленный бинарник, реальную доступную модель и внешние DAW. Источник и результат каждого запуска сохраняются отдельно.

## Исполненные рабочие потоки

| Поток плана | Что реализовано | Что остаётся до приёмки |
| --- | --- | --- |
| W1 — звук и микрофон | Output-only startup, реальный разрешённый input, lease/callback isolation, retirement в свежий output graph с тем же kernel/rate/MIDI; отдельные Stop timing stages | Phone routes/indicator/dropouts, повторные capture/Stop/retry и согласованный latency budget. |
| W2 — первый свой результат | Empty/Starter, действия пустого Grid, постоянный отдельный пример, guarded project transitions и SaveCopy escape из повреждённого workspace | Три сценария приняты на source 18; повтор после интеграции 19 и наблюдаемые сессии музыкантов. |
| W3 — помощник | Компактный setup, независимые языки/availability/Recheck/Commands; новый bounded `createSketch` intent | Реальные Foundation Models prompts и RU/EN диктовка на совместимом устройстве. |
| W4 — напев | Исправлена quantization projection для короткого take/partial grid; original/source/review сохранены | Human note segmentation и физический напев ещё требуют улучшения/приёмки; F1 не изменена. |
| W5 — музыкальная математика | Настоящее transpose; schema 10 хранит выбранные root/slash letters, chord-aware tone names и degrees | Native writing/transpose round-trip, старые failures и runtime миграции на установленном кандидате. |
| W6 — студийный перенос | MIDI/WAV/stems/portable, immutable offline render и independent readers сохранены; новые партии — обычные редактируемые события | Один собственный скетч в двух реальных DAW, USB/BLE timing/reconnect/sustain/Panic. |
| W7 — интерфейс | Единый бренд, shell/splash/settings, доступные первые действия; исправляется прямой 44 pt путь к Settings | Текущие RU/EN, темы, compact/large text/keyboard/VoiceOver originals и device проверка. |
| W8 — архитектура и QA | Constructor exception containment, revision-safe rename, metadata library/одиночный autosave refresh, guarded mix fast path, native inventory/watchdog/receipts | Полный coherent software run нового source; device memory/CPU/thermal/touch timing. |
| W9 — release | Разделены software/internal beta/release-ready; device receipt и source/attempt-aware gate | Signed exact-source binary, заполненная device/model/DAW matrix, Store metadata и App Review. |
| W10 — первоначальное видение | Новый материал из пустого проекта и сохранённое chord spelling реализованы отдельными музыкальными контрактами | Широкая музыкальная оценка, устойчивость на телефоне и улучшение voice; расширения не объявляются завершёнными по наличию экрана. |

## Сохранённое написание и реальные ноты

В schema 10 аккорд хранит `rootSpelling` и `slashBassSpelling`: выбранная буква и знак сохраняются в канонической форме, например `Db/Fb` → `D♭/F♭`. Sounding pitch class остаётся отдельно и проверяется на соответствие написанию. Поддержаны ASCII/Unicode accidental forms, включая ограниченные двойные знаки; malformed/mismatched writing отвергается.
Auto уважает сохранённый выбор; Sharps/Flats меняют отображение. Изменение root/slash очищает несовместимую старую букву, воисинг/quality edits сохраняют корректную. Transpose обновляет либо очищает writing, одна Undo возвращает исходные буквы и музыку. Save/portable/frozen sources и миграции 1…9 проверяются domain tests.
Chord tone names учитывают формулу: minor third пишется E♭, dominant seventh B♭, flat ninth над C — D♭. Эти уточнения орфографии не меняют MIDI pitches. Plain display preference из кандидата 18 больше не используется как доказательство persistent writing.

## Новый editable sketch: локальный композитор и роль модели

`SketchComposer` действительно создаёт новые **Harmony, Drums, derived root Bass и Melody** из ограниченного `SketchPlan`. Сейчас доступны **House / Hip-hop / Jazz**, **4 / 8 / 16 тактов**, BPM/key/mode и seed. Изменение seed меняет события; повторный review тех же параметров даёт одинаковые события/IDs.
Генерация допускается только в пустом проекте без записей/performance take. Непустая работа сохраняется; неподдержанный жанр не подменяется другим незаметно. Каждая партия — обычные MIDI/clip события: preview/A/B, одна Apply/Undo, редактирование, save/reopen и существующий MIDI/WAV/stems export.
Локальные RU/EN Commands работают без Apple Intelligence. Foundation Models получает отдельный `createSketch` intent и интерпретирует запрос в параметры; ноты строит тот же детерминированный локальный композитор. Language model не объявляется источником готового аудио или произвольных note arrays. Реальный успех модели остаётся Model Pending.
Domain проверки охватывают все поддержанные styles/keys/modes/lengths, безопасные параметры и schemas, seed determinism, сохранение исходного проекта, Apply/Undo, MIDI и nonzero audio каждой новой партии через настоящий offline DSP. Native генерация из пустого проекта пока Pending.

## Voice-to-MIDI: исправленный дефект, неизменная human accuracy

Для take короче выбранной сетки старое `length-grid` давало отрицательный onset; при неполной последней клетке могло создавать off-grid позицию — **520 вместо 960** при length 1000/grid 480. Теперь onset ограничен последней настоящей grid line, tail обрезается по capture region.
Targeted **21 Voice/Plan/Asset tests PASS**: короткие/неполные границы, offset loop, synthetic CAF → анализ → Apply → store/reopen → одна Undo/Redo с неизменными source bytes.
Production control на фиксированных development clips **1–8** до/после совпал целиком: **18 329 raw F0 frames, segments и 587 unquantized notes**. F0 accuracy **95.88%**, onset/pitch F1 **60.28% / 54.95%**, strict F1 **42.76% / 38.36%** остались прежними.
Две offline segmentation-гипотезы отклонены по заранее записанным guards; ни одна не попала в production. Holdout audio/annotations IDs 9–16 не открывались. [Raw reports, протоколы, exact hashes и runnable replay](voice/README.md) сохраняют также отрицательный результат экспериментов. Это corpus/host evidence, не phone capture acceptance.

## Что именно произошло в native кандидата 18

Источник: `fefa036`, build 18/schema 9; [job 133342040726](https://github.com/alexgazin/la-grilla/actions/runs/43879719411/job/133342040726), artifact `14232769005`. Итог **7 / 2 / 2**, не полный PASS.

**Три принятых FirstResult:**

- `testAcceptedMIDIInterleavingsKeepLatestWorkAndActiveRetryPreservesDisk` — **25.696 с**: настоящий Session MIDI/edit path на await boundaries, current work и bad bytes сохранены; физический MIDI не заявлен.
- `testEmptyProjectGuidesFirstChordToRealOutputAndPersists` — **107.847 с**: пустой документ → своё содержимое → фактический output → сохранение/возврат.
- `testStarterAndExampleAreAudibleIndependentAndKeepSavedProject` — **69.224 с**: starter и отдельный пример слышимы и не подменяют собственную работу.

Остальные четыре PASS — реальная unavailable-model/Recheck/local jazz ветка и три output/input/CAF continuity сценария. Их успех не является успешной Foundation Models-генерацией или живой человеческой транскрипцией.

| Неуспешный метод 18 | Фактическая причина | Исправление 19 и статус |
| --- | --- | --- |
| `HarmonyCatalogTests/testCustomFormulaPersistsEveryToneAndIsUndoable`, line 41 | Key-only note naming показало **D♯4** вместо ожидаемого chord-aware **E♭4** | Chord-aware spelling реализована; повтор native Pending. |
| `HarmonyCatalogTests/testAlteredNotationAndInvalidFormulaNeverSilentlySave`, line 65 | Показано **A♯4** вместо dominant **B♭4** | Chord-aware spelling реализована. Flat ninth expectation уточнено до D♭5 по формуле b9; MIDI 73 сохранён. Native Pending. |
| `TranspositionUITests/testFlatsAndScaleDegreesPersistWithoutNotationChangingMusic` | Собственный **120 с allowance**, до Settings: системное menu animation wait около 60 с и invalid activation point/retry | Открывать те же настоящие Settings прямой 44 pt tempo/key button; cap и assertions сохранены. Native Pending. |
| `TranspositionUITests/testTransposePreviewCancelApplyLiveUndoRedoAndReopen` | Такой же timeout **до первого transposition control** | Тот же прямой Settings path; это ещё не пройденный transpose journey. Native Pending. |

Эти timeouts не доказывают отказ самой transpose-математики, но оставляют её UI-приёмку открытой. Два spelling failures не переименованы в успех: они требуют фактического повторения после исправления.

## Что требуется дальше

1. Зафиксировать source кандидата 19 и выполнить Debug/archive/compatibility, все обязательные native cases и coherent full inventory; собрать новые оригинальные кадры с source/run/hash.
2. Повторить полный первый сеанс на установленном iPhone: Play/Jam, реальные Mic/Speech permissions, Stop/Cancel/retry/routes, save/reopen/export. Системный indicator, gaps и Stop latency измеряются отдельно.
3. На готовой eligible модели принять настоящие prompts → proposal/sketch parameters → A/B/Apply/Undo; отдельно RU/EN Speech и живой mono напев с reference notes/bleed.
4. Проверить тот же результат в **двух реальных DAW**, USB/BLE и 30 минут performance/memory/thermal/accessibility на hardware.
5. После device/model/DAW receipts — signed distribution, Store metadata и App Review. Внешние gates остаются Pending; наличие всех новых функций и локальных PASS не означает, что все 34 критерия приёмки закрыты.

## Следующая корректирующая проверка

Сохранены исходные 120 s на метод и все музыкальные утверждения. Для Am+2 ожидается Bm; Settings control должен целиком лежать внутри видимого Form, после проверки persistence восстанавливаются фактические исходные preferences. Anchored pinch использует один immutable public AX snapshot для согласованных ruler/viewport/diagnostic/transport данных; оба настоящих pinch и прежние допуски сохранены.

Локально воспроизведено блокирование supervisor при непрочитанном stdout pipe. Неблокирующий console mirror не теряет исходный logfile; две subprocess проверки подтверждают timeout/cleanup и разбор обязательного PASS из полного лога. Теперь 63 host checks PASS. Secondary step limits 65/31 min сохраняют process limits 60/30 min. Полный Mac-run завершился потерей связи с hosted runner; underlying cause неизвестна. [Source-specific итог](performance/native19-hosted-runner-failure.json) сохраняет аннотации и отсутствие native receipt.

Шесть оригинальных кадров кандидата 19 с владельцами PASS и полным раскрытием результата 13/2 находятся в [Screenshots/AuditImprovements](../../../Screenshots/AuditImprovements/README.md). Скриншоты не заменяют приёмку всего запуска.

## Уточнение native source 4e85930

[Focused16](https://github.com/alexgazin/la-grilla/actions/runs/43906210190) завершён **14 PASS / 1 assertion FAIL / 1 execution allowance timeout**, exit65, 1063.083 s. Обе AI, FirstResult3, Harmony2, Sketch2, ChordWriting, PCM3 и полный transpose/live/Undo/Redo/reopen прошли. Process timeout/signal отсутствовали, console drops0.

Оригинальные pan и оба pinch waiters completed; ошибки anchor 0.000141/0.000636 bars остаются меньше неизменного допуска 0.04. Snapshot transport value обрезан ровно до512 символов, поэтому финальные kernel/playing/pending/clock invariants не были приняты. Исправление сохраняет coherent geometry и отдельно читает полное фактическое post-gesture XCUIElement.value. [Source-specific замеры и hashes](performance/native19-pinch-observation-failure.json).

Preferences-case достиг настоящего root picker, но попытка нативного F menu activation закончилась invalid activation point и120s timeout. Поздняя hierarchy содержит видимый finite F frame; исходный video является60-byte error payload и не используется как визуальное доказательство. Коррекция должна использовать измеренный центр настоящего видимого native menu item с проверкой F/IV/persistence и восстановлением реальных исходных preferences.

Два полных ARM задания source4e не получили runner до исполнения, включая один адресный retry. Новый full job переводится в macos-15-intel; реальный Simulator arch выводится из uname и проверяется по lipo, SDK/runtime/source записываются в receipt. iPhone/archive остаются arm64. Inventory64, real HAL/CAF и process/method/time/evidence budgets не ослабляются; первое Intel-исполнение ещё Pending.

## Две конечные корректировки20

Проверка исходных шести блоков не обнаружила отсутствующего core-модуля. Исправлены два конкретных остатка существующего scope: A02/PM06 перестали обещать бесшовную подготовку/завершение микрофона; переносимый8/16-тактовый проект теперь получает полный listening range для нового ID и сохраняет его после перезапуска. Длина восстановления ограничена оставшейся аранжировкой, а не одной первой секцией. Новая preference создаётся сразу после successful install; поздняя принятая MIDI-правка всё ещё отменяет activation, но сохранённая отдельная копия остаётся пригодной для полного прослушивания. Музыка и исходные preferences не меняются.

[Политика и regression](../../../docs/PORTABLE_LISTENING.md): настоящие encoder → production import → canonical store → свежий процесс → реальный DSP за старой4-тактовой границей. Добавлен один120s метод; итоговый обязательный scope **17 focused /65 functional**, пока Pending. Frontend parse,703 EN/RU presentation audit, release20 audit и63 CI/release host tests PASS; неизменный domain остаётся186 tests. Подготовленный native-тест не считается выполненным.

Предшествующий19/a61 подтвердил x86_64 build/HAL, но не смог завершить Simulator boot. [Оригинальное наблюдение](performance/native19-intel-boot-observation.json) и [проверка реальных бинарников](performance/native19-intel-simulator-build-verification.json) сохранены отдельно. Новый source20 использует официальный macos-26 ARM image с тем же Xcode/SDK; strict audio, inventory и бюджеты сохранены, фактическое выполнение ещё Pending.

## Минимальные исправления после focused20/b3

[17-методный run43923399762](https://github.com/alexgazin/la-grilla/actions/runs/43923399762) дал15PASS/2FAILED; один failedcase также получил120s marker. Настоящий новый portable-import8/16 сfreshrelaunch/живымDSP прошёл62.431s; Empty52.313, pinch46.522 иtranspose78.351s прошли. Modal snapshot скрывает нижележащийGrid, поэтому только два фоновых UI-поля снова читаются напрямую, а видимая Review-панель остаётся coherent snapshot. Синтезированный switch event попал вцентр строки220/281, в то время как оригинальный video показывает контрол~371/281. Исправлен один реальный относительный touch по trailing control с bounded проверкой значения; повторной слепой попытки и state injection нет.

Исходный artifact14257805673:198385494bytes, SHA2563585079e131a4d50ac2bf4b45182e3046dccbafc26e7d3167d8a1a7ca833f479, CRC/bytes проверены. Весь запуск не принят. Оба macos15 SDK jobs не получилиrunner доcode; source переключает их HOST на официальныйmacos26, сохраняяXcode26.3/iPhonearm64 и все бюджеты.

Отдельно воспроизведён false-pass parser: actuala61 allowance marker с последующим latePASS давалfocused-pass приchildexit0. Теперь line-anchored marker остаётся per-case time-allowance-exceeded; rawstdout и исходныйsubprocess exit сохранены. Четыре meaningful regressions довели host-пакет до67PASS. Нормальные terminal outcomes/лимиты и inventory17/65 не меняются. Текущий app-код20 неизменён относительноb3; это observer/input/CI исправления.
