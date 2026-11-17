# Текущая сборка и границы приёмки

**В main — 1.0.0 (22), schema 11, 758 EN/RU ключей.** Исходник [`b478021ca4281527b0b1cbfbcae38eb80ba51392`](https://github.com/alexgazin/la-grilla/commit/b478021ca4281527b0b1cbfbcae38eb80ba51392) содержит локальные скетчи, нотацию, транспонирование, полный portable listening range и доработки контакта/звука. Статус — функциональная альфа. Срез: **17 ноября 2026**.

## Скачать и проверить на телефоне

**[Тестовая IPA22 из точного main](https://github.com/alexgazin/la-grilla/actions/runs/44038751086/artifacts/14307869946)**, без подписи; бесплатная Personal Team подходит. [Инструкция и проверка файла](../../Builds/Testing/README.md). IPA **3,678,397B**, SHA-256 `66de218921b4d3aa6effc1259b04a07c5adf78e8af47819edeb168e040b1d53b`. Исходные байты, ZIP CRC, все16 файлов приложения, arm64/iOS18/SDK26.2, weak FoundationModels, CoreMotion и UUID dSYM проверены независимо. Это проверка целостности/сборки, не физический запуск.

## Что изменилось по ручному отзыву

- Пэды получают начало независимых UIKit-контактов; живой удар идёт до обработки записи, квантование меняет записанный ритм.
- Piano roll показывает snapped draft, линию и позицию конца во время движения; 44pt рукоятка и один Undo после завершения.
- «Звук» открывает настоящие Classic/Warm/Bright, Preview/Cancel/Apply, сохранение выбранного тембра и Undo.
- Perform предлагает выключенное по умолчанию управление наклоном: Filter или Master volume, калибровка и ограниченный диапазон. Физические датчики/громкость ещё Pending.

Ночная тема сохранена. [Технический отчёт](../review/2026-11-17/TOUCH21.md) · [Оригинальные кадры22](../../Screenshots/Build22Touch/README.md) · [Дальнейшие этапы](../../ROADMAP.md).

## Текущие доказательства

| Исходник и проверка | Фактический результат и предел |
| --- | --- |
| **main22 / `9b94561`** | [44042481187](https://github.com/alexgazin/la-grilla/actions/runs/44042481187): host-проверка supervisor остановилась до Simulator; resistant-process fixture получил fatal127 вместо124. Исходные status/stdout были временными и не попали в assertion, поэтому errno не установлен. Все73 native-метода **UNOBSERVED**. Следующий диагностический патч сохраняет errno и безопасные frames;127 остаётся ошибкой, лимиты и functional inventory не меняются. |
| **main22 / `b478021`** | [44038751086](https://github.com/alexgazin/la-grilla/actions/runs/44038751086): iPhone Debug и Release archive PASS. [Compatibility44038751177](https://github.com/alexgazin/la-grilla/actions/runs/44038751177): полные приложения Xcode16.4 и26.0.1 PASS. Полный functional inventory73 **не принят**: первый main-запуск остановился на служебной подготовке DragUI до исполнения native flows; 73 не объявляются ни PASS, ни 73 app-failures. Требуется завершённый coherent main-run всех обязательных методов. |
| **22 / `60c24ce`** | [Focused44033597734](https://github.com/alexgazin/la-grilla/actions/runs/44033597734): **9 PASS / 1 FAIL / 0 allowance**, exit65. Resize уже завершился и показал1440ticks; тест ожидал строку без английского разделителя тысяч вместо фактической `1,440 ticks`, затем прекратился до Undo. Остальные9, включая оба пэда, перенос ноты, три звуковых сценария, запись/Undo/landscape прошли. |
| **22 / `aded2ff`** | [Resize-only44036545312](https://github.com/alexgazin/la-grilla/actions/runs/44036545312): **1 PASS,81.274s**, child/wrapper0, без allowance. Сохранены проверки1440ticks/count1 → Undo480 → Undo count0. Production-файлы совпадают с60c24 и исходным main22; изменились только тестовое ожидание форматирования и явный workflow scope. **9+1 не являются свежим полным10 или73.** |
| **21 / `7e01f21` — исправленная историческая ошибка** | [44027685543](https://github.com/alexgazin/la-grilla/actions/runs/44027685543):9PASS/1resizeFAIL. Embedded IPS подтвердил реальный SIGABRT при одновременном Observation-чтении history и inout-изменении проекта. В22 все восемь History-путей изменяют локальные значения и публикуют их после inout; native resize и оба Undo затем прошли. Старый бинарник21 не выдаётся за исправленную22. |

Последняя полностью принятая программная база до текущих изменений — **16**, exact main `9dfec7e117ef768c28cdfe12f342baf466f55682`: [43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785),51functionalPASS/0FAIL/1opt-in diagnosticSKIP и все три jobsSUCCESS. Этот результат не наследуется сборкой22 и не закрывает hardware-проверку.

## Исторические результаты до22

| Исходник и проверка | Фактический результат и его предел |
| --- | --- |
| **20 / `6bb06b5` — историческая тестовая IPA** | [Debug/archive 43957824077](https://github.com/alexgazin/la-grilla/actions/runs/43957824077): оба PASS; native job SKIPPED в диагностическом scope. [Диагностика 43957824262](https://github.com/alexgazin/la-grilla/actions/runs/43957824262): нотация — 120s allowance до нового switch gesture, drag — UNOBSERVED. IPA 3,564,207B, SHA-256 `b85ef6b7c81082a63bb861cd2d72fadd9fa822596dfa8efbbf7617af622d15d2`; исходные байты, ZIP CRC, все 16 файлов, arm64/iPhoneOS18/weak FoundationModels/dSYM проверены. Полной native/physical приёмки нет. |
| **20 / `f6cea328` — исторический source PR #21** | [Full 43934434713](https://github.com/alexgazin/la-grilla/actions/runs/43934434713): **64 PASS / 2 FAIL**, 0 allowance; [focused 43934434777](https://github.com/alexgazin/la-grilla/actions/runs/43934434777): **18 PASS / 2 FAIL**, 0 allowance. Остатки — native clip drag и настройки нотации. Debug/archive этого source PASS; полный gate не принят. |
| **20 / `f5437fd` — завершённая диагностика** | [43966306399](https://github.com/alexgazin/la-grilla/actions/runs/43966306399): **0 PASS / 1 allowance / 1 unobserved**. Неверный порядок аргументов `lipo` не дал helper проверить runtime launchctl и запустить DragUI; реальный drag отсутствует. Switch gesture 100 не подтверждён фактическим Synthesized event до 120s allowance. Эти исходы не заменяются успехом компиляции. |
| **17 / `5adbadb` — историческая recovery-база** | [Debug / archive 43876565718](https://github.com/alexgazin/la-grilla/actions/runs/43876565718): оба PASS на Xcode 26.3 / iPhoneOS SDK 26.2; архив — arm64, minimum iOS 18, weak FoundationModels, ресурсы и dSYM проверены. [Compatibility 43876575685](https://github.com/alexgazin/la-grilla/actions/runs/43876575685): полные приложения с ресурсами на Xcode 16.4 / SDK 18.5 и 26.0.1 / SDK 26.0 PASS. [Focused 7 native 43876565702, attempt 2](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2): **7 PASS / 0 FAIL / 0 SKIP, 379.622 s**. Обе первоначальные queued cancellation были отказами выдачи hosted runner; методы в них не исполнялись. Семь методов текущего исходника теперь исполнены успешно, включая granted Speech → typed Review/Apply/Undo. Это focused scope, не полная native-регрессия и не физический повтор. |
| **17 / `29adf6c398173faf830de8f6249702628b8a3f76`** | [Native 43870504379](https://github.com/alexgazin/la-grilla/actions/runs/43870504379): **5 PASS / 2 execution-allowance timeouts по 120 s**. Все строгие PCM/CAF, input retirement и Splash прошли. Два целых метода — granted Speech/Assistant и AI availability — не прошли; xcodebuild завершился 65, отдельный 600 s watchdog не сработал. Реальная Speech-цепь получила **842 752 frames** после настоящих разрешений, затем сообщила NoSpeech 1110; timeout наступил позднее при Review. Это не подтверждение транскрипции человеческого голоса и не PASS всего Speech-метода. |
| **17 / `9fb52e01340d060f3424ae5ea3d38a90b0893b83`** | [Native 43864455841](https://github.com/alexgazin/la-grilla/actions/runs/43864455841): **6 PASS / 1 granted-Speech timeout по 120 s**, затем сработал общий watchdog. Сценарий и run не объявляются принятыми. Эта версия исправила первоначальную ошибку компиляции splash `bde2caa`; исходная ошибка и неисполненные тесты сохранены в журнале. |
| **16 / точный main `9dfec7e`** | [Полная проверка 43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785): все три jobs SUCCESS; 51 functional native PASS, 0 FAIL, 1 diagnostic SKIP. Старый результат ветки `01fb8b7` с 49 PASS / 2 FAIL / 1 SKIP остаётся отдельной историей, а не текущим результатом main 16. |

## Реализованный музыкальный объём

В22 сохранены редактируемые House/Hip-hop/Jazz скетчи с аккордами, ударными, басом и мелодией, A/B и одной Apply/Undo; Empty/Starter, транспонирование, сохранённое написание аккордов и portable import8/16 тактов с полным диапазоном/fresh reopen. Commands и локальный композитор работают без Apple Intelligence. Реальная FoundationModels, Speech и human Voice-to-MIDI остаются отдельной проверкой устройства.

## Что изменено в историческом пакете 17

- Разрешённый захват подготавливает duplex I/O до первого доступа к ленивому input node; проверяет реальные разрешения, маршруты и hardware/engine formats. В конфигурации разрешён Bluetooth HFP для входа, A2DP — для выхода; реальные Bluetooth-маршруты остаются аппаратной проверкой.
- После захвата input-использующий граф может быть заменён на input-free граф. DSP/kernel, музыкальное состояние и MIDI сохраняются; одновременно работает один граф. Native retirement проверил новую identity графа, отсутствие input и продолжающийся clock. Переходы могут давать паузу звука; zero-gap и поведение индикатора микрофона на физическом iPhone пока не приняты.
- AI и диктовка имеют отдельные явно выбранные языки. Есть Recheck и пояснения причин недоступности. Переключатели Siri для отдельного приложения не показывают глобальную готовность FoundationModels. Локальные Commands остаются отдельным рабочим механизмом.
- Помощник показывает ввод идеи первым, а AI setup — компактно. Музыкальный review использует такты, доли и ноты без служебных ticks. Это не новый генератор ударных, баса и мелодии: существующая модель управляет формой/гармонией и переиспользует музыкальный материал.
- Добавлены статичный системный Launch Screen и анимация сетки/курсора во время настоящего bootstrap, без искусственного минимального ожидания и процентов.

## Splash и исторические медиа

OS Launch Screen следует системной Light/Dark-теме; сохранённая тема самого приложения может отличаться от неё. Статичная и SwiftUI-композиции согласованы, но универсальный pixel-perfect переход между разными темами не заявляется.

`--uitesting --splash-preview` показывает **тот же компонент** после настоящего bootstrap, удерживая только представление для воспроизводимого кадра. QA receipt отдельно записывает `qaPreview`, `bootstrapReady`, системный Reduce Motion и явный preview override. Три preview-кадра и реальный normal launch / Welcome Skip / relaunch проверяются отдельно. PASS preview не измеряет cold-launch latency.

Ранее принятые [DeviceRepair PNG](../../Screenshots/DeviceRepair), [ProfessionalShell PNG](../../Screenshots/ProfessionalShell) и [рабочая запись](../../Media/WorkingDemo/README.md) сохраняют собственные версии/source/hash. У каждой коллекции собственные version/source/run/hash; прошлые изображения не переименовываются в evidence нового source.

Два новых оригинальных [кадра сборки 20](../../Screenshots/Build20Preview/manifest.json) относятся к прошедшим методам Harmony/Commands и Perform/Export из source `deeb701`; исходные пиксели не изменены.

Нового принятого видео работы 20 пока нет. [Capture `deeb701`, run 43966102437](https://github.com/alexgazin/la-grilla/actions/runs/43966102437) завершился по 35-минутному лимиту задания: **2 PASS / 1 allowance / 1 interrupted** из четырёх сценариев. Исходный MP4 не финализирован и не воспроизводится; наличие реального PCM не подтверждает звуковое покрытие всех сцен. Эта попытка сохранена как диагностика, без готового проморолика или подмены исторического видео 15.

## Что ещё требуется

1. Завершить обязательный coherent main-набор **73** на одном точном source с SDK/archive. Служебная preflight-ошибка и раздельные9+1 не заменяют исполнение всех методов.
2. На установленной22 повторить первый звук, два пальца, плотный ритм, drag/resize возле краёв, Preview/Apply/Undo звука и изменение тембра при лупе. Проверить Tilt Filter/Volume, нейтраль, ручное управление, фон и ориентации; измерить палец→выход на speaker/wired/Bluetooth.
3. Повторить granted/denied dictation, capture/Stop/повтор, новые проекты/save/reopen/export. Настоящий человеческий напев и FoundationModels на eligible-устройстве с поддерживаемым языком принимаются отдельно от PCM и fixtures.
4. Закрыть [C8](DEVICE_ACCEPTANCE.md):30мин latency/thermal/dropouts, маршруты, USB/BLE MIDI, две DAW и minimum-iOS18 installed launch. Затем — signed distribution, TestFlight и App Review по [процедуре](RELEASE.md).

Hardware-поля остаются **Pending**. Отзыв владельца о ночной теме и удобстве аккордов/мелодии учтён; измерение задержки, реальные датчики и устранение всех прежних симптомов на его телефоне из Simulator не следуют.

## Независимые аудиты

- [Архитектура](../review/2026-11-16/architecture.md).
- [Продуктовый аналитик](../review/2026-11-16/analyst.md).
- [Product Manager](../review/2026-11-16/product-manager.md).
- [QA](../review/2026-11-16/qa.md).

Каждый отчёт сохраняет свой audited source, доказательства и список задач. Рекомендация, host benchmark и изменение в отдельной ветке не считаются принятой функцией текущей сборки 22. Последующие исправления проходят собственную приёмку; аппаратная и Store-готовность из этих отчётов не следуют.
