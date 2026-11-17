# La Grilla для ручного тестирования

**Доступна проверенная IPA La Grilla1.0.0 (23), schema11, exact main [`82e4dfb`](https://github.com/alexgazin/la-grilla/commit/82e4dfb02d2016dcbe31e7b34af6cd09b0f0457a).** Четыре SDK jobs PASS на исходной attempt1; полный native73 завершён на attempt2: **71 PASS / 2 FAIL / 0 allowance**, все73 наблюдались, exit65, 3227.618s, без общего timeout. Software gate не принят. Это unsigned manual alpha; hardware/Store-приёмка открыты.

**[Скачать свежую exact-main IPA23 / `82e4dfb`](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/artifacts/14346460625)**. Извлечённая `LaGrilla-unsigned.ipa`: **3 693 136 байт**, SHA-256 `93de06cf30a23acf186dd9a2427e98c2097136a0f53c671789cb8612662245a8`. Original artifact14346460625/run44120318741/attempt1 независимо проверен по новому source: CRC, все16 original app files, app-архив, arm64/minimum iOS18/SDK26.2 и dSYM. Bytes равны7564/db8, но пакет скачан и проверен отдельно; подписи тестировщика всё равно требуется. Новые main receipts сохраняются отдельно от прежних: [исходный package](candidate23-main-82e4dfb-original-package.json) · [независимая проверка](candidate23-main-82e4dfb-verification.json) · [SHA-256](LaGrilla-1.0.0-23-main-82e4dfb-unsigned.sha256).

**[Историческая candidate IPA23 / `7564fe7` · focused4 PASS](https://github.com/alexgazin/la-grilla/actions/runs/44112860068/artifacts/14342868829)**. Извлечённая `LaGrilla-unsigned.ipa`: **3 693 136 байт**, SHA-256 `93de06cf30a23acf186dd9a2427e98c2097136a0f53c671789cb8612662245a8`. Это новый независимо проверенный original artifact14342868829, archive attempt2 run44112860068; package/source/bytes проверены отдельно, не перенесены из db8. Файл unsigned, требует подписи тестировщика; ниже инструкция Personal Team. [Оригинальный package](candidate23-7564fe7-original-package.json) · [Независимая проверка](candidate23-7564fe7-verification.json) · [SHA-256](LaGrilla-1.0.0-23-7564fe7-unsigned.sha256).

**Историческая preview23 / `0cfd12e` до исправлений помощника:** [оригинальный Actions ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44083683395/artifacts/14329580396), внутри `LaGrilla-unsigned.ipa`. **3 691 269 байт**, SHA-256 `f73de389392d9680c3263f2825c61e98feb07f11a17cb7895494941a8950a5e5`. Сверены новый API digest/CRC, исходный receipt с source `0cfd12e3e1a821d50c7a1502f627329b7d60ff02`, все 16 файлов с этим app-архивом, arm64/iPhoneOS18/SDK26.2, matching dSYM,78 weak FoundationModels imports, CoreMotion,758 EN/RU ключей и отсутствие подписи. Пакет можно передавать для ручного теста с собственной подписью, при результате полного native73 70 PASS / 2 FAIL / 1 allowance; это не accepted beta или Store release. [SHA-256](LaGrilla-1.0.0-23-main-0cfd12e-unsigned.sha256) · [Независимая проверка](candidate23-main-0cfd12e-verification.json) · [Исходный receipt](candidate23-main-0cfd12e-original-package.json).

**Исторический preview23 / `c9b2623`, на hold:** [его исходный ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44077041006/artifacts/14325104339), внутри `LaGrilla-unsigned.ipa`, **3 691 269 байт**, SHA-256 `f73de389392d9680c3263f2825c61e98feb07f11a17cb7895494941a8950a5e5`. Фактические IPA bytes этого c9 совпадают с историческим `0cfd12e`, поскольку app-код между ними не менялся. Пакет0cfd отдельно скачан и проверен по своему artifact/receipt/source; это не равенство с текущей интеграцией, native-результат c9 не переносится. Сам c9 focused3 завершился0 PASS / 1 assertion FAIL / 2 исходных 120s allowance. [Исходная проверка c9](candidate23-c9b2623-verification.json) · [Терминальный native outcome](candidate23-c9b2623-native-outcome.json).

**Историческая IPA 23 / `66effd2`, на hold:** [его исходный ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44073353758/artifacts/14323827791), внутри `LaGrilla-unsigned.ipa`: **3 690 932 байт**, SHA-256 `55bdaf1129f66239eb028da1512142e50427937934c28f26e252d559f4ddf580`. Независимая статическая проверка прошла; focused3 этого source не принят, пакет не переименовывается в `c9b2623` или main.

**Проверенный прежний пакет23 / `e2ec475`, superseded и на hold:** [оригинальный Actions ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44064471466/artifacts/14320675762) содержит `LaGrilla-unsigned.ipa` и исходный `LaGrilla-unsigned.json`. IPA — **3 689 425 байт**, SHA-256 `162595fc9b8804670d6550fa2db7f4791707608c5703d147ac318f83e4dc6923`. API digest/CRC, все 16 файлов против исходного app-архива, arm64/iPhoneOS18/SDK 26.2, dSYM, слабая FoundationModels, CoreMotion, 758 EN/RU ключей и отсутствие подписи проверены. Пакет не переименовывается в новый source и пока не рекомендуется как исправленная текущая23.

## Установка с Mac или Windows

1. Скачать точно обозначенный проверенный ZIP и извлечь `LaGrilla-unsigned.ipa`; сверить SHA-256 с его receipt. Наличие нового workflow не означает готовый файл.
2. Установить [Sideloadly](https://sideloadly.io/), подключить iPhone по USB, выбрать его и IPA, указать свой Apple ID и нажать Start.
3. На iPhone включить Developer Mode и доверить разработчику, если iOS попросит. Бесплатная Personal Team подходит; подпись обычно действует 7 дней.

Apple ID, пароль, 2FA и provisioning остаются у тестировщика. Перед обновлением экспортировать важные проекты в portable bundle: 23 читает схемы 1…11 и сохраняет 11; старые приложения не откроют сохранённую 11.

## Приёмка кандидата 23

| Source / scope | Фактический статус |
| --- | --- |
| **Последний полный exact main `82e4dfb02d2016dcbe31e7b34af6cd09b0f0457a`** | [44120318741/attempt2](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/attempts/2): **73 наблюдались / 71 PASS / 2 FAIL / 0 allowance**, exit65, 3227.618s, без общего timeout. Debug/archive/16.4/26.0.1 PASS на исходной attempt1; точная IPA статически PASS и доступна для ручной альфы. Не приняты ожидание PLAYING после перестановки секции и запуск следующего Pad-case при завершении прежнего процесса. Следующий полный73 после test-only наблюдения свежего состояния Pending. |
| **Main23 / `0cfd12e3e1a821d50c7a1502f627329b7d60ff02`** | [iPhone/archive/full73 44083683395](https://github.com/alexgazin/la-grilla/actions/runs/44083683395) и [compatibility44083683721](https://github.com/alexgazin/la-grilla/actions/runs/44083683721): четыре SDK jobs PASS; **73 наблюдались / 70 PASS / 2 FAIL / 1 allowance**, exit65, без supervisor timeout. Все пять прежних регрессий и десять touch/sound/recording/landscape сценариев PASS; весь native gate ещё не принят. |
| **Candidate `7564fe7eff86cf6fbec1caab02d152fb1741c7d2`** | [Strict4 attempt1](https://github.com/alexgazin/la-grilla/actions/runs/44112860068/attempts/1): **4 PASS / 0 allowance**, exit0/subprocess0, timedOut=false, 261.479s. Jazz46.884s, setup43.305s, Composition36.929s, Speech74.992s. Scope input-diagnostic/fullAcceptance=false, не full73. SDK4 PASS: Debug/16.4 исходные; archive/26.0.1 повторены только после отмен до получения runner, native не повторялся. Свежая IPA проверена отдельно. Результат scoped4 не переносится на последующий main82e4: у него собственные проверенный архив и full73 71/2/0. |
| **`6504ccb` / [Assistant3 44107005380](https://github.com/alexgazin/la-grilla/actions/runs/44107005380)** | **2 PASS / 1 FAIL**, без allowance: Composition84.779s и Granted Speech94.857s PASS; Jazz48.698s FAIL до ввода/генерации на фактическом `unsupportedLanguage` для AI request locale `ru-RU`. Последующий7564 strict4 прошёл; исходный6504 FAIL остаётся историческим. |
| `c9b262334ad435310c2d80701dfce6fe6fbaddd5` | [Focused3 44077041024](https://github.com/alexgazin/la-grilla/actions/runs/44077041024): **0 PASS / 1 assertion FAIL / 2 allowance**, exit 65, без wrapper timeout. Bass FAIL, 104.540s, без allowance: restored1 присутствует в исходных кадрах до окна predicate, позже в свежем AX есть1/Register/Gate/PLAYING; тестовое наблюдение не подтвердилось. Flats: центр сработал, B♭/degree, Apply 101.03s, relaunch 104.57s, затем исходный 120s при чтении reopened notes. Full transpose: реальные Apply/Undo и Redo 117.68s, затем исходный 120s. Terminal duration для двух interrupted cases не выдавался и не выдумывается. [Debug/archive44077041006](https://github.com/alexgazin/la-grilla/actions/runs/44077041006) и [compatibility44077040988](https://github.com/alexgazin/la-grilla/actions/runs/44077040988): все четыре jobs PASS. Preview-IPA статически проверена, на hold. |
| `66effd2aa17974f169f5cc78dab4747435fad855` | [Focused3 44073353862](https://github.com/alexgazin/la-grilla/actions/runs/44073353862) завершился неуспешно: full transpose PASS, 100.510s; Flats FAIL, 90.890s, центральное значение0; Bass→Melody padded on/off PASS, далее missing `notes.count` assertion 116.49s и исходный 120s allowance при завершении. [Debug/archive44073353758](https://github.com/alexgazin/la-grilla/actions/runs/44073353758) и [compatibility44073353829](https://github.com/alexgazin/la-grilla/actions/runs/44073353829): все четыре jobs PASS. Своя IPA статически проверена, историческая и на hold. |
| `57609025fc43741909c7204ec870cf839e2a58a6` | [Focused2 44069245545](https://github.com/alexgazin/la-grilla/actions/runs/44069245545): **1 PASS / 1 FAIL / 0 allowance**, exit 65. Full transpose PASS, 115.086s; Flats FAIL, 111.366s — после касания и нового AX-чтения значение switch осталось0. [Debug/archive 44069245450](https://github.com/alexgazin/la-grilla/actions/runs/44069245450) и [compatibility 44069245579](https://github.com/alexgazin/la-grilla/actions/runs/44069245579): все четыре jobs PASS; они не заменяют native. |
| `e2ec475e23167073cc02a08f30d3b5d413326b2a` | [Focused2 44064471496](https://github.com/alexgazin/la-grilla/actions/runs/44064471496): **1 PASS / 1 FAIL / 0 allowance**, exit 65. Full transpose PASS, 118.102s; Flats FAIL, 81.171s. [Debug/archive 44064471466](https://github.com/alexgazin/la-grilla/actions/runs/44064471466) и [compatibility 44064471511](https://github.com/alexgazin/la-grilla/actions/runs/44064471511): все четыре jobs PASS. Точная IPA независимо проверена, но focused/full gate не принят; файл указан выше как прежний пакет на hold. |
| `8f7cd0e`, [44059775230](https://github.com/alexgazin/la-grilla/actions/runs/44059775230) | 4 PASS / 1 allowance, exit 65: все три Perform и полный transpose Preview/Cancel/Apply/live/Undo/Redo/reopen прошли; Flats достиг 120 s. Весь targeted и полный gate не приняты. [Оригинальные прошедшие кадры](../../Screenshots/Build23Layout/README.md). |
| main22 `807c735`, [44046471258](https://github.com/alexgazin/la-grilla/actions/runs/44046471258) | Все 73 исполнились: 68 PASS / 4 assertion FAIL / 1 allowance. Это исходная полная регрессия до исправлений 23. |

В этой интеграции только helper `playing(_:)` читает свежий snapshot с прежним требованием PLAYING; оба5s и все действия/лимиты сохранены. Исходные кадры47.057s/49.257s внутри неудачного ожидания уже показывают PLAYING и правильный порядок, AX60.91s это подтверждает. Следующий Pad-case не выполнил касаний из-за невозможности завершить тот же предыдущий PID49770. Продуктовая остановка и zero-gap PCM на этом основании не заявляются. Следующий единый полный73 Pending, без дополнительного focused-run. [Разбор SECTION23](../../docs/review/2026-11-17/SECTION23.md).

На доступной main82 IPA вручную проверить Start → естественное окончание → поздний Stop без нового capture; Start → обычный Stop → повтор; смену языка/режима во время preview и закрытие помощника с реальным открытием исходного аккорда. Прежняя preview0cfd не содержит новые Stop-действия и сохранена отдельно.

На телефоне проверить два пальца/ритм с speaker/wired/Bluetooth; живой resize/Undo и отмену жеста при zoom; Sound Preview/Cancel/Apply во время лупа; Perform Replay/Reset, крупный текст, landscape и Tilt Filter/Volume; полные настройки проекта и chord Preview/Apply; save/kill/reopen/export. [Подробная аппаратная матрица — все поля Pending](../../docs/release/DEVICE_ACCEPTANCE.md#build-23-touch-sound-and-tilt-retest).

Микрофон/Speech, реальная FoundationModels, человеческий напев, USB/BLE MIDI, две DAW и 30-минутные нагрузочные сессии принимаются отдельно на установленном точном source. Новое видео отменено; передаются приложение и оригинальные PNG.

## Историческая IPA 22 из main b478021

- Точный source: [`b478021ca4281527b0b1cbfbcae38eb80ba51392`](https://github.com/alexgazin/la-grilla/commit/b478021ca4281527b0b1cbfbcae38eb80ba51392), build **22**, schema **11**, **758 EN/RU ключей**.
- IPA: **3,678,397 bytes**, SHA-256 `66de218921b4d3aa6effc1259b04a07c5adf78e8af47819edeb168e040b1d53b`. Контрольную сумму сверять с извлечённым `LaGrilla-unsigned.ipa`: [SHA-256](LaGrilla-1.0.0-22-main.sha256).
- Оригинальный artifact **14307869946**, **13,389,589 bytes**, SHA-256 `49b861e2f12922b284f0f858408cc4ad9a8be60f31a0ebc688c1ac622459b766`. [Исходные package-метаданные](candidate22-main-original-package.json) · [Независимая проверка](candidate22-main-verification.json).
- ZIP CRC и все 16 файлов IPA сверены с исходным архивом; arm64/iPhoneOS, minimum iOS 18, SDK 26.2, weak FoundationModels и UUID бинарника/dSYM проверены. Подписи нет.

**Статус — тестовая альфа.** [Debug/archive точного main](https://github.com/alexgazin/la-grilla/actions/runs/44038751086) прошли; [compatibility 16.4 / 26.0.1](https://github.com/alexgazin/la-grilla/actions/runs/44038751177) прошла. Изменения касаний имеют раздельные 9 PASS на `60c24ce` и 1 PASS на `aded2ff` с тем же product-кодом; это не свежий полный набор 10 или 73. Этот b478021-запуск остановился до functional-тестов; позднее main807c735 исполнил 73 с 68 PASS / 4 assertion FAIL / 1 allowance. Результаты не переносятся между source. Аппаратная и Store-приёмка открыты.

Что проверить в 22:

1. Два пальца на пэдах, удержание и скольжение; звук начинает контакт, квантование относится к записи. Сравнить speaker/wired/Bluetooth.
2. Piano roll: двигать и растягивать ноту, смотреть линию/позицию конца, отпускать и делать один Undo.
3. «Звук» в Jam/Mixer: Classic/Warm/Bright → Preview → Cancel либо Apply; проверить Undo, save/reopen и звучание во время лупа.
4. Perform: включить Tilt control, выбрать Filter или Volume, установить нейтраль; проверить ручное управление, Stop, фон и поворот телефона. Датчики и реальная громкость на устройстве ещё не приняты.

Затем — диктовка/Stop/повтор, Empty → скетч → save/reopen/export, MIDI и перенос в DAW. Локальные Commands и SketchComposer работают без Apple Intelligence; настоящие Speech, FoundationModels и человеческий напев требуют отдельного физического сеанса.

**Перед обновлением экспортировать важные проекты в portable bundle.** Сборка 22 читает схемы 1…10 и сохраняет schema 11; старые приложения не открывают сохранённую 11. IPA17/19/20 и их контрольные суммы сохранены.

## Предыдущая IPA 20

Source [`6bb06b5c1f05e0b937e2c4aba670efc72f629c41`](https://github.com/alexgazin/la-grilla/commit/6bb06b5c1f05e0b937e2c4aba670efc72f629c41), schema 10, 703 EN/RU ключа. В 20 есть локальные редактируемые скетчи, A/B, Apply/Undo, транспонирование и сохранённое написание аккордов; импортированный проект на 8/16 тактов получает полный диапазон воспроизведения. Commands и локальный композитор работают без Apple Intelligence.

**Статус: неподписанный тестовый кандидат. Полная программная и аппаратная приёмка не завершена.** Это исторический кандидат 20 из [PR #21](https://github.com/alexgazin/la-grilla/pull/21); его частичные результаты не принимают сборку 22.

- [iPhone Debug и Release archive](https://github.com/alexgazin/la-grilla/actions/runs/43957824077) точного source прошли; native job в этом диагностическом запуске был пропущен, поэтому он не подтверждает полный функциональный набор.
- [Диагностика 6bb](https://github.com/alexgazin/la-grilla/actions/runs/43957824262): нотация достигла 120-секундного лимита до нового жеста переключателя; перетаскивание не исполнялось. Полный предыдущий source `f6cea328` дал [64/66 PASS](https://github.com/alexgazin/la-grilla/actions/runs/43934434713); это не приёмка данного бинарника.
- IPA: **3,564,207 bytes**, SHA-256 `b85ef6b7c81082a63bb861cd2d72fadd9fa822596dfa8efbbf7617af622d15d2`. Оригинальные байты архива, ZIP CRC и все 16 файлов приложения проверены; Mach-O — arm64/iPhoneOS, minimum iOS 18, weak FoundationModels, без подписи. [Оригинальный архив и отчёты](https://github.com/alexgazin/la-grilla/actions/runs/43957824077/artifacts/14273365913).
- Настоящие диктовка, FoundationModels, человеческий напев, аппаратные аудиомаршруты, контроллеры и App Store этим файлом не приняты. В первую очередь проверить первый звук, диктовку/Stop/повтор, Empty → скетч → save/reopen/export, перетаскивание клипа и переключатель ступеней.

**Перед обновлением экспортировать важные проекты в portable bundle.** Кандидаты 19/20 используют schema 10 и читают проекты 1…9; старые приложения не откроют сохранённую schema 10.

## Предыдущая IPA 19

[Скачать 1.0.0 (19), 3.4 MiB](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Builds/Testing/LaGrilla-1.0.0-19-unsigned.ipa). Файл и его контрольная сумма сохранены без изменений.

### Что внутри сборки 19

Новые редактируемые House/Hip-hop/Jazz скетчи — аккорды, ударные, бас и мелодия — с A/B, Apply/Undo и MIDI; первый звук в пустом проекте и Starter; транспонирование, сохранённое написание аккордов; исправления документов, голосовых таймингов и производительности. Скетчи создаёт локальный музыкальный композитор; доступная системная модель может интерпретировать параметры. Доступность настоящей FoundationModels и человеческая диктовка требуют отдельной проверки телефона.

**Статус: тестовый кандидат, не завершённая релизная приёмка.** Бинарник из [`4e85930acf006376f3861d4209bf07ea8bcdcaf0`](https://github.com/alexgazin/la-grilla/commit/4e85930acf006376f3861d4209bf07ea8bcdcaf0), [PR #21](https://github.com/alexgazin/la-grilla/pull/21). На момент публикации IPA 19 её исходный код находился в PR, а основной код `main` был 17; это исторический статус того кандидата.

- [iPhone Debug и Release archive](https://github.com/alexgazin/la-grilla/actions/runs/43906210319) прошли. Оба полных native jobs не получили hosted runner до исполнения, включая один адресный повтор; полный прогон 64 методов этим source не принят.
- [Focused 16](https://github.com/alexgazin/la-grilla/actions/runs/43906210190) завершён: **14 PASS / 1 assertion FAIL / 1 execution-allowance timeout**, exit 65. Исторический результат сохраняется отдельно от последующих кандидатов.
- Архив 14246785600: **12,833,883 bytes**, SHA-256 `1fb996f68536f4cdf4d84776a8312aaaf575eaca92dec03bde5288b9955dde09`.
- IPA: **3,549,483 bytes**, SHA-256 `a98ba44b037c2bddefc9217f07d7441e6cc57f9d7c1a09b7f1f4f4864e48771e`. ZIP CRC и SHA всех 16 оригинальных файлов приложения проверены; Mach-O — arm64/iPhoneOS, minimum iOS 18, weak FoundationModels, без подписи.
- [Receipt и все файлы](LaGrilla-1.0.0-19-unsigned.json), [контрольная сумма](LaGrilla-1.0.0-19-unsigned.sha256), [независимая проверка](candidate19-independent-verification.json), [исходные метаданные артефакта](candidate19-artifact-metadata.json).

**Перед обновлением экспортировать важные проекты в portable bundle.** Сборка 19 использует schema 10 и читает проекты 1…9; старые версии приложения не откроют сохранённую schema 10. Физический запуск, аудиомаршруты, живой напев и App Store не приняты этим архивом.

## Предыдущая IPA 17

[Скачать 1.0.0 (17), 3.2 MiB](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Builds/Testing/LaGrilla-1.0.0-17-unsigned.ipa). Source `5adbadb37c39911c4acc2c2ef511198867098040`; [focused 7](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2) — **7 PASS / 0 FAIL / 0 SKIP**; Debug/archive и обе compatibility сборки PASS. Это отдельный проверенный recovery scope, не полный regression и не физическая приёмка. [Receipt](LaGrilla-1.0.0-17-unsigned.json), [SHA-256](LaGrilla-1.0.0-17-unsigned.sha256).

Начать ручную проверку со звука, затем Assistant → диктовка → Stop → команда «Темп 110» → Review/Apply/Undo; повторная запись, Empty/Starter, генерация скетча, сохранение/reopen/MIDI. Для Commands и локального композитора Apple Intelligence не требуется.
