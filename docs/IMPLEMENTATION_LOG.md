# Журнал завершения исходного видения

План: [ORIGINAL_VISION_COMPLETION](ORIGINAL_VISION_COMPLETION.md). База: `main` `1ddf660` / 1.0.0 (12), schema 7. Проверены 64 Swift tests, 11 C++ suites, 19 Studio flows и обе SDK-сборки/архив; 54 кадра относятся к прежнему объёму функциональности и не доказывают ещё не реализованные расширения.

## C0 — сверка и начало реализации

- **Статус:** техническая сверка выполнена; план и контракты записаны, реализация начата.
- **Обнаруженные пробелы:** ограниченный Assistant вместо free-form AI; нет clip/section drag; Stop при изменении структуры/микрофоне; restart в A/B; неполный практический каталог/нет формул пользователя; фильтр Slider вместо круговой ручки; открытая физическая приёмка.
- **Разделение работы:** гармоническая модель/редактор; clip/section domain+жесты; atomic DSP snapshot; shared microphone; typed AI/provider+review; circular live filter. Интеграция Session/schema/CI/localization/screenshots централизована.
- **Согласованные контракты:** schema 8; optional customIntervals; clip-specific note selection; project snapshot с notes+mix+presets+layout token+revision; один duplex input tap; validated whole-song Assistant proposal.
- **Проверки пока:** исходные acceptance-результаты базы; новые этапы не отмечены выполненными до фактических проверок.

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

- **Статус:** software/native приёмка пройдена, кандидат **1.0.0 (13)**, [PR #14](https://github.com/alexgazin/la-grilla/pull/14). Проверенные кадры и исходники сохранены; merge выполняется после review. Публикация в App Store не выполнялась.
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
