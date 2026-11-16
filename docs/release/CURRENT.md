# Текущий кандидат и границы приёмки

Срез: **16 ноября 2026**. Этот файл — единая текущая сводка; [журнал](../IMPLEMENTATION_LOG.md) сохраняет последовательность попыток, а [роадмап](../../ROADMAP.md) — следующую работу.

## Текущий статус

**Функциональная альфа.** В `main` интегрирован **1.0.0 (17), schema 8**, [PR #20](https://github.com/alexgazin/la-grilla/pull/20). [IPA для тестировщика](../../Builds/Testing/README.md) собрана из проверенного app/test source `5adbadb37c39911c4acc2c2ef511198867098040`, 651 EN/RU ключ. Она не подписана; тестировщик подписывает её своим Apple ID на ноутбуке. Физическая приёмка открыта.

Следующий [PR #21](https://github.com/alexgazin/la-grilla/pull/21) — **1.0.0 (19), schema 10**, app source `0ed624a`; предыдущий test/CI source `f005854`, **703 EN/RU ключа**. После четырёх независимых аудитов реализованы первый звук в пустом проекте, starter/example, безопасные переходы документов, transpose/writing/ступени, новый local editable SketchComposer, timing fix Voice-to-MIDI, metadata/cache/mix оптимизации, C ABI exception guard и exact-source CI/device gates. [Подробный отчёт](../review/2026-11-16/IMPLEMENTATION.md). Кандидат 19 прочитывает проекты 1…9; старые приложения отклоняют schema 10.

Локально для 19: **186 Swift tests PASS**, **63 CI/release host test PASS**, presentation/release/schema audits; DSP остаётся неизменным после 16 пройденных C++ harnesses кандидата 18. Новый scope **16 focused / 64 functional native — Pending**. Проверенные 7/11 методов прежнего 18 не считаются PASS новой версии. Этот пакет не является принятой App Store-сборкой.

Последняя полная принятая программная база — **main 1.0.0 (16)**, source `9dfec7e117ef768c28cdfe12f342baf466f55682`: [43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785), три jobs SUCCESS, **51 functional PASS / 0 FAIL / 1 opt-in diagnostic SKIP**. Это историческая база, не приёмка нового source или телефона владельца.

## Доказательства по исходникам

| Исходник и проверка | Фактический результат и его предел |
| --- | --- |
| **17 / `5adbadb` — опубликованная тестовая IPA** | [Debug / archive 43876565718](https://github.com/alexgazin/la-grilla/actions/runs/43876565718): оба PASS на Xcode 26.3 / iPhoneOS SDK 26.2; архив — arm64, minimum iOS 18, weak FoundationModels, ресурсы и dSYM проверены. [Compatibility 43876575685](https://github.com/alexgazin/la-grilla/actions/runs/43876575685): полные приложения с ресурсами на Xcode 16.4 / SDK 18.5 и 26.0.1 / SDK 26.0 PASS. [Focused 7 native 43876565702, attempt 2](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2): **7 PASS / 0 FAIL / 0 SKIP, 379.622 s**. Обе первоначальные queued cancellation были отказами выдачи hosted runner; методы в них не исполнялись. Семь методов текущего исходника теперь исполнены успешно, включая granted Speech → typed Review/Apply/Undo. Это focused scope, не полная native-регрессия и не физический повтор. |
| **19 / `f005854`** | [Focused 43890521487](https://github.com/alexgazin/la-grilla/actions/runs/43890521487): **13 PASS / 2 assertion FAIL / 0 timeout**, 700.813 s, exit 65. Оба Sketch, ChordWriting, Harmony, AI и strict PCM прошли. В Transposition исправлены неверное ожидаемое Am+2 (Bm) и попадание в невидимый край Settings. Debug/archive и обе compatibility сборки PASS. Полный [43890521274](https://github.com/alexgazin/la-grilla/actions/runs/43890521274) не завершился к последнему наблюдению 16:13 UTC; неизвестные исходы не считаются PASS. Следующий corrective source требует нового native результата. |
| **17 / main `8eaac4c`** | [Full 43887481738](https://github.com/alexgazin/la-grilla/actions/runs/43887481738): **54 PASS / 1 anchored-pinch FAIL / 1 diagnostic SKIP**. Семь recovery методов прошли повторно. Сохранённые кадры/геометрия первого pinch соответствовали допуску; последовательные AX-запросы исчерпали 6 s waiter. В кандидате 19 тест читает единый public snapshot, сохраняя оба реальных жеста, допуски и бюджет. Новый результат Pending. |
| **17 / `29adf6c398173faf830de8f6249702628b8a3f76`** | [Native 43870504379](https://github.com/alexgazin/la-grilla/actions/runs/43870504379): **5 PASS / 2 execution-allowance timeouts по 120 s**. Все строгие PCM/CAF, input retirement и Splash прошли. Два целых метода — granted Speech/Assistant и AI availability — не прошли; xcodebuild завершился 65, отдельный 600 s watchdog не сработал. Реальная Speech-цепь получила **842 752 frames** после настоящих разрешений, затем сообщила NoSpeech 1110; timeout наступил позднее при Review. Это не подтверждение транскрипции человеческого голоса и не PASS всего Speech-метода. |
| **17 / `9fb52e01340d060f3424ae5ea3d38a90b0893b83`** | [Native 43864455841](https://github.com/alexgazin/la-grilla/actions/runs/43864455841): **6 PASS / 1 granted-Speech timeout по 120 s**, затем сработал общий watchdog. Сценарий и run не объявляются принятыми. Эта версия исправила первоначальную ошибку компиляции splash `bde2caa`; исходная ошибка и неисполненные тесты сохранены в журнале. |
| **16 / точный main `9dfec7e`** | [Полная проверка 43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785): все три jobs SUCCESS; 51 functional native PASS, 0 FAIL, 1 diagnostic SKIP. Старый результат ветки `01fb8b7` с 49 PASS / 2 FAIL / 1 SKIP остаётся отдельной историей, а не текущим результатом main 16. |

У первого запуска `5adbadb` focused job и archive были отменены **до исполнения**: GitHub сообщил “The job was not acquired by Runner of type hosted even after multiple attempts”. Это проблема доступности hosted ARM runner, без результатов native-методов. Повторены только эти задания; успешные Debug и compatibility сохраняют собственные подтверждения. Состояние очереди не является ни PASS, ни выявленным app assertion.

## Что изменено в кандидате 17

- Разрешённый захват подготавливает duplex I/O до первого доступа к ленивому input node; проверяет реальные разрешения, маршруты и hardware/engine formats. В конфигурации разрешён Bluetooth HFP для входа, A2DP — для выхода; реальные Bluetooth-маршруты остаются аппаратной проверкой.
- После захвата input-использующий граф может быть заменён на input-free граф. DSP/kernel, музыкальное состояние и MIDI сохраняются; одновременно работает один граф. Native retirement проверил новую identity графа, отсутствие input и продолжающийся clock. Переходы могут давать паузу звука; zero-gap и поведение индикатора микрофона на физическом iPhone пока не приняты.
- AI и диктовка имеют отдельные явно выбранные языки. Есть Recheck и пояснения причин недоступности. Переключатели Siri для отдельного приложения не показывают глобальную готовность FoundationModels. Локальные Commands остаются отдельным рабочим механизмом.
- Помощник показывает ввод идеи первым, а AI setup — компактно. Музыкальный review использует такты, доли и ноты без служебных ticks. Это не новый генератор ударных, баса и мелодии: существующая модель управляет формой/гармонией и переиспользует музыкальный материал.
- Добавлены статичный системный Launch Screen и анимация сетки/курсора во время настоящего bootstrap, без искусственного минимального ожидания и процентов.

## Splash и медиа

OS Launch Screen следует системной Light/Dark-теме; сохранённая тема самого приложения может отличаться от неё. Статичная и SwiftUI-композиции согласованы, но универсальный pixel-perfect переход между разными темами не заявляется.

`--uitesting --splash-preview` показывает **тот же компонент** после настоящего bootstrap, удерживая только представление для воспроизводимого кадра. QA receipt отдельно записывает `qaPreview`, `bootstrapReady`, системный Reduce Motion и явный preview override. Три preview-кадра и реальный normal launch / Welcome Skip / relaunch проверяются отдельно. PASS preview не измеряет cold-launch latency.

Ранее принятые [DeviceRepair PNG](../../Screenshots/DeviceRepair), [ProfessionalShell PNG](../../Screenshots/ProfessionalShell) и [рабочая запись](../../Media/WorkingDemo/README.md) сохраняют собственные версии/source/hash. Новые кадры кандидата 17 публикуются только после индивидуального просмотра и манифеста; прошлые изображения не переименовываются в evidence нового source.

CI supervisor дополнительно сохраняет полный исходный logfile при заполненном console pipe: console mirror стал неблокирующим, пропущенные только в консоли байты считаются в receipt. Два реальных subprocess regression checks прошли. Это воспроизведённый локальный дефект; без native receipt причина зависания Mac-run не установлена. Вторичный runner timeout 65/31 min сохраняет процессные бюджеты 60/30 min и 120 s на метод.

## Что ещё требуется

1. Завершить 16 focused и все 64 functional native, SDK/archive/compatibility кандидата 19 и полный exact-main run после интеграции. Scope 17 остаётся отдельной успешной recovery-проверкой.
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
