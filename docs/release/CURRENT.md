# Текущий кандидат и границы приёмки

**Код текущей ветки — 1.0.0 (22), schema 11.** По ручному отзыву добавлены нативные multi-touch пэды с лёгким contact path, live-preview нот, настоящие Classic/Warm/Bright и опциональный наклон для фильтра/громкости. Локально прошли 200 Swift tests, 17 C++ harnesses и 10 mapping contracts. Apple SDK и новый focused набор 10 / полный native набор 73 ещё Pending. [Изменения, доказательства и этапы](../review/2026-11-17/TOUCH21.md). Последняя ручная IPA ниже остаётся 20; её байты и результаты не являются проверкой нового кода 21.


Срез: **17 ноября 2026**. Этот файл — единая текущая сводка; [журнал](../IMPLEMENTATION_LOG.md) сохраняет последовательность попыток, а [роадмап](../../ROADMAP.md) — следующую работу.

## Текущий статус

**Последняя IPA для ручного тестирования — [1.0.0 (20), ZIP с IPA](https://github.com/alexgazin/la-grilla/actions/runs/43957824077/artifacts/14273365913)**, source `6bb06b5c1f05e0b937e2c4aba670efc72f629c41`, schema 10, 703 EN/RU ключа. [Инструкция и SHA-256](../../Builds/Testing/README.md). Это unsigned test candidate для подписи своим Apple ID; Debug/Release archive прошли, полная программная и аппаратная приёмка не завершена.

**Код этой ветки — 1.0.0 (20), schema 10**, 703 EN/RU ключа. Это интеграционный кандидат, не завершённая software/physical приёмка. Исторический пакет 17 (`5adbadb37c39911c4acc2c2ef511198867098040`) интегрирован через [PR #20](https://github.com/alexgazin/la-grilla/pull/20); его семь focused recovery-сценариев, Debug/archive и compatibility сохраняют собственные результаты и не принимают новые изменения.

[PR #21](https://github.com/alexgazin/la-grilla/pull/21) кандидата 20 ещё открыт как draft, head `f6cea328d7fb80936334c80b340675ac03f53fef`; последующие исправления проверяются отдельно. Последний полный прогон этого source — **64/66 PASS**, focused — **18/20 PASS**. Перетаскивание клипа и сценарий настроек нотации ещё не имеют завершённого успешного результата. Ни эти частичные результаты, ни новая тестовая IPA не объявляются принятой App Store-сборкой.

Текущая [диагностика `8c91eca4b34cbb52b34c4211949dbffc8cc42466`, run 44009053214](https://github.com/alexgazin/la-grilla/actions/runs/44009053214) ещё выполняется: **Pending**, результат не объявлен заранее.

Предыдущая двухсценарная [диагностика `f5437fd`](https://github.com/alexgazin/la-grilla/actions/runs/43966306399) завершилась **0 PASS / 1 execution-allowance timeout / 1 unobserved**. Подготовка DragUI остановилась до запуска сервиса: неверный порядок аргументов `lipo` в helper; drag не исполнялся. Нотация достигла 120-секундного лимита до подтверждённого выполнения нового жеста переключателя. Компиляция приложения и тестов, проверка архитектуры приложения, HAL и boot прошли. Найденная ошибка инфраструктуры не является PASS функционального сценария.

Последняя полная принятая программная база — **main 1.0.0 (16)**, точный source `9dfec7e117ef768c28cdfe12f342baf466f55682`: [run 43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785) завершился успешно всеми тремя jobs, **51 functional native PASS / 0 FAIL / 1 opt-in diagnostic SKIP**. Bulk capture повторно не запускался. Этот результат не переносится на изменения кандидата 17 и не подтверждает устранение пользовательского дефекта на телефоне.

## Доказательства по исходникам

| Исходник и проверка | Фактический результат и его предел |
| --- | --- |
| **20 / `6bb06b5` — последняя тестовая IPA** | [Debug/archive 43957824077](https://github.com/alexgazin/la-grilla/actions/runs/43957824077): оба PASS; native job SKIPPED в диагностическом scope. [Диагностика 43957824262](https://github.com/alexgazin/la-grilla/actions/runs/43957824262): нотация — 120s allowance до нового switch gesture, drag — UNOBSERVED. IPA 3,564,207B, SHA-256 `b85ef6b7c81082a63bb861cd2d72fadd9fa822596dfa8efbbf7617af622d15d2`; исходные байты, ZIP CRC, все 16 файлов, arm64/iPhoneOS18/weak FoundationModels/dSYM проверены. Полной native/physical приёмки нет. |
| **20 / `f6cea328` — head PR #21** | [Full 43934434713](https://github.com/alexgazin/la-grilla/actions/runs/43934434713): **64 PASS / 2 FAIL**, 0 allowance; [focused 43934434777](https://github.com/alexgazin/la-grilla/actions/runs/43934434777): **18 PASS / 2 FAIL**, 0 allowance. Остатки — native clip drag и настройки нотации. Debug/archive этого source PASS; полный gate не принят. |
| **20 / `f5437fd` — завершённая диагностика** | [43966306399](https://github.com/alexgazin/la-grilla/actions/runs/43966306399): **0 PASS / 1 allowance / 1 unobserved**. Неверный порядок аргументов `lipo` не дал helper проверить runtime launchctl и запустить DragUI; реальный drag отсутствует. Switch gesture 100 не подтверждён фактическим Synthesized event до 120s allowance. Эти исходы не заменяются успехом компиляции. |
| **17 / `5adbadb` — историческая recovery-база** | [Debug / archive 43876565718](https://github.com/alexgazin/la-grilla/actions/runs/43876565718): оба PASS на Xcode 26.3 / iPhoneOS SDK 26.2; архив — arm64, minimum iOS 18, weak FoundationModels, ресурсы и dSYM проверены. [Compatibility 43876575685](https://github.com/alexgazin/la-grilla/actions/runs/43876575685): полные приложения с ресурсами на Xcode 16.4 / SDK 18.5 и 26.0.1 / SDK 26.0 PASS. [Focused 7 native 43876565702, attempt 2](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2): **7 PASS / 0 FAIL / 0 SKIP, 379.622 s**. Обе первоначальные queued cancellation были отказами выдачи hosted runner; методы в них не исполнялись. Семь методов текущего исходника теперь исполнены успешно, включая granted Speech → typed Review/Apply/Undo. Это focused scope, не полная native-регрессия и не физический повтор. |
| **17 / `29adf6c398173faf830de8f6249702628b8a3f76`** | [Native 43870504379](https://github.com/alexgazin/la-grilla/actions/runs/43870504379): **5 PASS / 2 execution-allowance timeouts по 120 s**. Все строгие PCM/CAF, input retirement и Splash прошли. Два целых метода — granted Speech/Assistant и AI availability — не прошли; xcodebuild завершился 65, отдельный 600 s watchdog не сработал. Реальная Speech-цепь получила **842 752 frames** после настоящих разрешений, затем сообщила NoSpeech 1110; timeout наступил позднее при Review. Это не подтверждение транскрипции человеческого голоса и не PASS всего Speech-метода. |
| **17 / `9fb52e01340d060f3424ae5ea3d38a90b0893b83`** | [Native 43864455841](https://github.com/alexgazin/la-grilla/actions/runs/43864455841): **6 PASS / 1 granted-Speech timeout по 120 s**, затем сработал общий watchdog. Сценарий и run не объявляются принятыми. Эта версия исправила первоначальную ошибку компиляции splash `bde2caa`; исходная ошибка и неисполненные тесты сохранены в журнале. |
| **16 / точный main `9dfec7e`** | [Полная проверка 43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785): все три jobs SUCCESS; 51 functional native PASS, 0 FAIL, 1 diagnostic SKIP. Старый результат ветки `01fb8b7` с 49 PASS / 2 FAIL / 1 SKIP остаётся отдельной историей, а не текущим результатом main 16. |

У первого запуска `5adbadb` focused job и archive были отменены **до исполнения**: GitHub сообщил “The job was not acquired by Runner of type hosted even after multiple attempts”. Это проблема доступности hosted ARM runner, без результатов native-методов. Повторены только эти задания; успешные Debug и compatibility сохраняют собственные подтверждения. Состояние очереди не является ни PASS, ни выявленным app assertion.

## Что реализовано в кандидате 20

Редактируемые House/Hip-hop/Jazz скетчи с аккордами, ударными, басом и мелодией, A/B и одной Apply/Undo; пустой проект/Starter и первый звук; транспонирование и сохранённое написание аккордов; portable import на 8/16 тактов с полным диапазоном воспроизведения и fresh reopen. Новые команды и скетчи работают без Apple Intelligence. Полная текущая программная приёмка и настоящие model/voice/device/DAW результаты остаются открытыми.

## Что изменено в историческом пакете 17

- Разрешённый захват подготавливает duplex I/O до первого доступа к ленивому input node; проверяет реальные разрешения, маршруты и hardware/engine formats. В конфигурации разрешён Bluetooth HFP для входа, A2DP — для выхода; реальные Bluetooth-маршруты остаются аппаратной проверкой.
- После захвата input-использующий граф может быть заменён на input-free граф. DSP/kernel, музыкальное состояние и MIDI сохраняются; одновременно работает один граф. Native retirement проверил новую identity графа, отсутствие input и продолжающийся clock. Переходы могут давать паузу звука; zero-gap и поведение индикатора микрофона на физическом iPhone пока не приняты.
- AI и диктовка имеют отдельные явно выбранные языки. Есть Recheck и пояснения причин недоступности. Переключатели Siri для отдельного приложения не показывают глобальную готовность FoundationModels. Локальные Commands остаются отдельным рабочим механизмом.
- Помощник показывает ввод идеи первым, а AI setup — компактно. Музыкальный review использует такты, доли и ноты без служебных ticks. Это не новый генератор ударных, баса и мелодии: существующая модель управляет формой/гармонией и переиспользует музыкальный материал.
- Добавлены статичный системный Launch Screen и анимация сетки/курсора во время настоящего bootstrap, без искусственного минимального ожидания и процентов.

## Splash и медиа

OS Launch Screen следует системной Light/Dark-теме; сохранённая тема самого приложения может отличаться от неё. Статичная и SwiftUI-композиции согласованы, но универсальный pixel-perfect переход между разными темами не заявляется.

`--uitesting --splash-preview` показывает **тот же компонент** после настоящего bootstrap, удерживая только представление для воспроизводимого кадра. QA receipt отдельно записывает `qaPreview`, `bootstrapReady`, системный Reduce Motion и явный preview override. Три preview-кадра и реальный normal launch / Welcome Skip / relaunch проверяются отдельно. PASS preview не измеряет cold-launch latency.

Ранее принятые [DeviceRepair PNG](../../Screenshots/DeviceRepair), [ProfessionalShell PNG](../../Screenshots/ProfessionalShell) и [рабочая запись](../../Media/WorkingDemo/README.md) сохраняют собственные версии/source/hash. Новые кадры кандидата 17 публикуются только после индивидуального просмотра и манифеста; прошлые изображения не переименовываются в evidence нового source.

Два новых оригинальных [кадра сборки 20](../../Screenshots/Build20Preview/manifest.json) относятся к прошедшим методам Harmony/Commands и Perform/Export из source `deeb701`; исходные пиксели не изменены.

Нового принятого видео работы 20 пока нет. [Capture `deeb701`, run 43966102437](https://github.com/alexgazin/la-grilla/actions/runs/43966102437) завершился по 35-минутному лимиту задания: **2 PASS / 1 allowance / 1 interrupted** из четырёх сценариев. Исходный MP4 не финализирован и не воспроизводится; наличие реального PCM не подтверждает звуковое покрытие всех сцен. Эта попытка сохранена как диагностика, без готового проморолика или подмены исторического видео 15.

## Что ещё требуется

1. Завершить два оставшихся сценария и полный набор 66 functional native кандидата 20 с его собственными SDK/archive/compatibility результатами; затем интеграция и новый exact-main run. Успешные семь recovery-методов 17 и частичные результаты 20 сохраняют собственные источники и scope.
2. Повторить на установленном кандидате первоначальный дефект: Play, granted/denied dictation, повторный capture/Stop, новые проекты, save/reopen/export; записать точные модель, iOS и build. Проверить реальный mic indicator и маршруты.
3. Отдельно принять настоящий человеческий напев и FoundationModels на eligible-устройстве с выбранным поддерживаемым языком. PCM loopback и proposal fixtures не заменяют эти проверки.
4. Закрыть [аппаратную C8-матрицу](DEVICE_ACCEPTANCE.md): 30-минутные сессии, latency/thermal/dropouts, USB/BLE MIDI и импорт в две DAW. Затем — distribution signing, TestFlight и App Review по [процедуре](RELEASE.md).

Формальные hardware-поля остаются **Pending**. Отчёты владельца не отвергаются зелёным Simulator CI; устранение симптомов на его телефоне пока не подтверждено.

## Независимые аудиты

- [Архитектура](../review/2026-11-16/architecture.md).
- [Продуктовый аналитик](../review/2026-11-16/analyst.md).
- [Product Manager](../review/2026-11-16/product-manager.md).
- [QA](../review/2026-11-16/qa.md).

Каждый отчёт сохраняет свой audited source, доказательства и список задач. Рекомендация, host benchmark и изменение в отдельной ветке не считаются принятой функцией кандидата 17. Последующие исправления проходят собственную приёмку; аппаратная и Store-готовность из этих отчётов не следуют.
