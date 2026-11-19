# La Grilla для ручного тестирования

**[Скачать IPA 39 для iPhone](https://raw.githubusercontent.com/alexgazin/la-grilla/c289752bbf597dcd9ffde4e42840a982261d4a1e/Builds/Testing/LaGrilla-39-unsigned.ipa)**. Офлайн-конструктор теперь понимает описание частей A и B с разными аккордами, длительностью и передышкой, а также возврат к A. Размер IPA — 7 666 366 байт. Подпишите файл своим Apple ID через Sideloadly. [Контрольная сумма и состав IPA](candidate39-package.json) · [Сборки Debug и Release](https://github.com/alexgazin/la-grilla/actions/runs/44517422175) · [Музыкальный пример](../../Media/Grooves/Workout-39.mp3)

**[Скачать IPA 38 для iPhone](https://raw.githubusercontent.com/alexgazin/la-grilla/86df35639cdd20813d40987dea033c9bbc50c79f/Builds/Testing/LaGrilla-38-unsigned.ipa)**. В Automatic запрос «Create jazz hip hop old school» при недоступной системной модели открывает автономный конструктор с готовыми параметрами. Подпишите скачанный IPA своим Apple ID через Sideloadly. SHA-256 файла — `a513a7d9035b0eabe9450b6f4b3fb0c0aecd40b300d1e5abc22162719fedb9e8`.

**[Скачать IPA 37 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44375324030/artifacts/14461599286)**. Автономный генератор инструментальных аранжировок, раздельные вариации баса и ударных, вступление и пауза перед повтором. Из ZIP извлеките LaGrilla-unsigned.ipa и подпишите своим Apple ID через Sideloadly. SHA-256 файла IPA — `d28f3f92d41bbb8ed974743fb8f09c1d5cbfdb27f41b11872aeac8c1134fcc33`. [Проверка создания проекта на симуляторе](https://github.com/alexgazin/la-grilla/actions/runs/44376030143).

**[Скачать IPA 36 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44325351752/artifacts/14437696953)**. Четыре синтезированных саксофона, четырёхполосный эквалайзер на дорожках и мастере, 27 EQ-пресетов и 18 музыкальных заготовок. В ZIP лежит неподписанная IPA для Personal Team. [Проверка пакета и экспорта](candidate36-verification.json) · [Послушать тембры](../../Media/Audio/saxophone-voices.mp3)

**[Скачать IPA 35 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44319624212/artifacts/14433869024)**. Конструктор создаёт отдельный проект по описанию или по заданным параметрам. Из ZIP извлеките IPA и подпишите через Personal Team. Собраны Debug и Release для iPhone. [Проверка пакета и музыкального примера](candidate35-verification.json)

**[Скачать IPA 34 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44316742468/artifacts/14433691380)**. Исправлена громкость экранных клавиш, добавлен выбор английского запроса при неподдерживаемом языке системной модели. В ZIP лежит неподписанная IPA для установки через Personal Team. Замерены шесть инструментов и штатный синтезатор, собраны Debug и Release для iPhone. Полный прогон отложен. [Проверка пакета и уровни звука](candidate34-verification.json)

**[Скачать IPA 33 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44309761379/artifacts/14431130364)**. Шесть инструментов с иллюстрациями, мультитач-клавиатура и запись фраз. В ZIP лежит `LaGrilla-unsigned.ipa`, которую можно подписать через Personal Team. Пакет для iOS 18+ занимает 7 451 773 байта. SHA-256 `33a18a73d18aeab468652942baf2f053a2208ee670f3747ef0c0966e3121646e`. [Проверка архива](candidate33-verification.json) · [Инструкция по клавиатуре](../../docs/SONG_FORM_AND_SOUND_BANKS.md)

### Сборка 32

**[Скачать IPA 32 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44303173892/artifacts/14427263161)**. В нотном редакторе два пальца меняют горизонтальный масштаб, один палец прокручивает сетку. Распакуйте ZIP и подпишите IPA своей Personal Team. Размер 7 205 154 байта, SHA-256 `fba236db930bb370e79aa6f77c8b20ec8df3101f084c21c9751019ff5d57ec66`. [Проверка пакета](candidate32-verification.json)

### Сборка 31

**[Скачать IPA 31 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44289170060/artifacts/14421860271)**. Распакуйте ZIP и подпишите `LaGrilla-unsigned.ipa` своей Personal Team на ноутбуке. Пакет 1.0.0 (31), arm64, iOS 18+. В нём есть записанное пианино и нейлоновая гитара. Размер 7 198 875 байт, SHA-256 `62007167db2acb797bf8cd7c94cf4f947ef05e66729acf3a7e579ed9e0a794a1`. [Проверка исходника и пакета](candidate31-verification.json)

На исходнике пакета прошли сборки iPhone Debug и Release, все 80 нативных сценариев Simulator и 207 Swift-тестов. Установка и работа на физическом iPhone проверяются отдельно. [Итоговый прогон](https://github.com/alexgazin/la-grilla/actions/runs/44289170060/attempts/1) · [Кадр сборки 31](../../Screenshots/Release31/README.md)

### Сценарий для ручной проверки

1. Откройте демо, включите Play и назначьте акустическое пианино или гитару в меню звуков дорожки.
2. В Джеме откройте «Звук → Сэмплы пэдов». Загрузите Pocket Kit, импортируйте один короткий WAV и назначьте его во втором проекте из общей библиотеки.
3. Добавьте куплет и припев, переместите карточку за ручку и продолжите играть. Откройте «Исполнение», запишите и остановите дубль, затем нажмите «Создать редактируемую песню».
4. Сохраните WAV, stems, MIDI и `.grillapack`. Откройте копию проекта и проверьте, что тембры и порядок секций сохранились.

[Руководство по звуку и исполнению](../../docs/SONG_FORM_AND_SOUND_BANKS.md) · [Физическая приёмка](../../docs/release/DEVICE_ACCEPTANCE.md) · [Роадмап](../../ROADMAP.md)

### Предыдущая сборка 28

**[Скачать IPA 28 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44255310833/artifacts/14406207053)**. Из архива извлеките `LaGrilla-unsigned.ipa` и подпишите своей Personal Team. Пакет 1.0.0 (28), arm64, iOS 18+. Размер 3 954 385 байт, SHA-256 `e64b2a878d8c170f8514483eaa729b96a7a56bd4c96e3e43dc12076a95e0bcde`. [Проверка исходника и пакета](candidate28-samples-verification.json).

### Что проверить в сборке 28

- В микшере откройте «Звук» у гармонии или мелодии, загрузите `.sf2`, прослушайте и назначьте инструмент. Включите Play и экспортируйте WAV.
- В Джеме откройте «Звук → Сэмплы пэдов», загрузите Pocket Kit и сыграйте. Импортируйте короткий WAV или AIFF на один пэд. Проверьте запись на петлю, Undo/Redo и открытие проекта после перезапуска.
- Экспортируйте `.grillapack`, откройте его копию в сборке 28 и сравните звук. Для слепка исполненного микса используйте WAV, для дальнейшего редактирования партий в DAW доступны stems и MIDI.

[Конструктор и руководство по звуку](../../docs/SONG_FORM_AND_SOUND_BANKS.md) · [Протокол проверки физического iPhone](../../docs/release/DEVICE_ACCEPTANCE.md)

### Предыдущая сборка 27

**[Сборка 27 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44248325062/artifacts/14403425905)**. Из ZIP извлеките `LaGrilla-unsigned.ipa` и подпишите своей Personal Team. Файл: 3 863 194 байта, SHA-256 `c85ae78fbcfea98f9d2ec1de0fda65352e1d46854070b7914b116e133ec1e163`. [Исходник и проверка пакета](candidate27-song-form-verification.json).

Три сценария конструктора прошли на iPhone Simulator. Импорт и предпрослушивание SoundFont прошли проверку на macOS с настоящим банком. [Оригиналы скриншотов](../../Screenshots/SongForm27/README.md).

**[Сборка 26 для iPhone](https://github.com/alexgazin/la-grilla/actions/runs/44245693209/artifacts/14401667073)**. Из ZIP извлеките `LaGrilla-unsigned.ipa` и подпишите своей Personal Team. Файл: 3 853 310 байт, SHA-256 `77ee66ff3f4d1518884fbf43014bba50a4778b82f1af6bcbd92fcd80a393c3f7`. [Исходник, хэш и проверка пакета](candidate26-song-form-soundfont-verification.json).

В сборке есть конструктор песни и импорт SoundFont для прослушивания. [Где открыть и что запланировано](../../docs/SONG_FORM_AND_SOUND_BANKS.md).

**Nocturne 24 — новая тестовая сборка.** Пять реальных ночных экранов сохранены в [Design26](../../Screenshots/Design26/README.md); их общий сценарий прошёл за 103.043 с. Нативный focused-прогон исходника 207fc2b: 9 PASS, Light превысил120 с на заключительных проверках, PadContact оборвался при запуске до UI. Gate не принят. Повторные запросы геометрии и неиспользуемые снимки в новом тесте удалены; все проверки и лимиты сохранены. Следующий полный inventory 75 — Pending.

**[Скачать IPA 24 Nocturne](https://github.com/alexgazin/la-grilla/actions/runs/44173635688/artifacts/14368802814)** · [Исходный package](candidate24-nocturne-207fc2b-original-package.json) · [Независимая проверка](candidate24-nocturne-207fc2b-verification.json) · [SHA-256](LaGrilla-1.0.0-24-nocturne-207fc2b-unsigned.sha256). Ниже сохранены исторические сборки23.

**Доступна проверенная IPA La Grilla1.0.0 (23), schema11, exact main [`8bc7866`](https://github.com/alexgazin/la-grilla/commit/8bc7866c0da5ecf330deaafeaf107ac2b881ec79).** SDK4 PASS; последний полный native73, [run44140208148/attempt1](https://github.com/alexgazin/la-grilla/actions/runs/44140208148/attempts/1): **71 PASS / 2 FAIL / 0 case allowance**, все 73 наблюдались. Общий3600s supervisor timeout: elapsed3621.266 s, exit124/subprocess−15; xcresult не финализирован, software gate не принят. Это unsigned manual alpha; hardware/Store-приёмка открыты.

**[Скачать свежую exact-main IPA23 / `8bc7866`](https://github.com/alexgazin/la-grilla/actions/runs/44140208148/artifacts/14355166108)**. Извлечённая `LaGrilla-unsigned.ipa`: **3 693 136 байт**, SHA-256 `3836ee877d766d3fa5288997e3e76e3788b4a59a62ba83c689ca1efa8893e748`. Original artifact14355166108/run44140208148/attempt1 независимо проверен по точному source: ZIP/IPA CRC, все 16 original app files против app-архива, arm64/minimum iOS18/SDK26.2 и matching dSYM. Это новый исходный пакет с другим hash, чем82e4/7564/db8; требуется подпись тестировщика. [Исходный package](candidate23-main-8bc7866-original-package.json) · [Независимая проверка и native outcome](candidate23-main-8bc7866-verification.json) · [SHA-256](LaGrilla-1.0.0-23-main-8bc7866-unsigned.sha256).

**Историческая exact-main IPA23 / `82e4dfb`:** [оригинальный ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/artifacts/14346460625), `LaGrilla-unsigned.ipa` — **3 693 136 байт**, SHA-256 `93de06cf30a23acf186dd9a2427e98c2097136a0f53c671789cb8612662245a8`. Её artifact/source/CRC/все 16 app files/app-архив/dSYM проверены отдельно; bytes совпадают с7564/db8. Полный run44120318741/attempt2 сохраняет71/2/0, exit65,3227.618s без общего timeout и старые KVC/Pad-startup FAIL. [Исходный package82e4](candidate23-main-82e4dfb-original-package.json) · [Проверка82e4](candidate23-main-82e4dfb-verification.json) · [SHA-256](LaGrilla-1.0.0-23-main-82e4dfb-unsigned.sha256).

**[Историческая candidate IPA23 / `7564fe7` · focused4 PASS](https://github.com/alexgazin/la-grilla/actions/runs/44112860068/artifacts/14342868829)**. Извлечённая `LaGrilla-unsigned.ipa`: **3 693 136 байт**, SHA-256 `93de06cf30a23acf186dd9a2427e98c2097136a0f53c671789cb8612662245a8`. Это новый независимо проверенный original artifact14342868829, archive attempt2 run44112860068; package/source/bytes проверены отдельно, не перенесены из db8. Файл unsigned, требует подписи тестировщика; ниже инструкция Personal Team. [Оригинальный package](candidate23-7564fe7-original-package.json) · [Независимая проверка](candidate23-7564fe7-verification.json) · [SHA-256](LaGrilla-1.0.0-23-7564fe7-unsigned.sha256).

**Историческая preview23 / `0cfd12e` до исправлений помощника:** [оригинальный Actions ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44083683395/artifacts/14329580396), внутри `LaGrilla-unsigned.ipa`. **3 691 269 байт**, SHA-256 `f73de389392d9680c3263f2825c61e98feb07f11a17cb7895494941a8950a5e5`. Сверены новый API digest/CRC, исходный receipt с source `0cfd12e3e1a821d50c7a1502f627329b7d60ff02`, все 16 файлов с этим app-архивом, arm64/iPhoneOS18/SDK26.2, matching dSYM,78 weak FoundationModels imports, CoreMotion,758 EN/RU ключей и отсутствие подписи. Пакет можно передавать для ручного теста с собственной подписью, при результате полного native73 70 PASS / 2 FAIL / 1 allowance; это не accepted beta или Store release. [SHA-256](LaGrilla-1.0.0-23-main-0cfd12e-unsigned.sha256) · [Независимая проверка](candidate23-main-0cfd12e-verification.json) · [Исходный receipt](candidate23-main-0cfd12e-original-package.json).

**Исторический preview23 / `c9b2623`, на hold:** [его исходный ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44077041006/artifacts/14325104339), внутри `LaGrilla-unsigned.ipa`, **3 691 269 байт**, SHA-256 `f73de389392d9680c3263f2825c61e98feb07f11a17cb7895494941a8950a5e5`. Фактические IPA bytes этого c9 совпадают с историческим `0cfd12e`, поскольку app-код между ними не менялся. Пакет0cfd отдельно скачан и проверен по своему artifact/receipt/source; это не равенство с текущей интеграцией, native-результат c9 не переносится. Сам c9 focused3 завершился0 PASS / 1 assertion FAIL / 2 исходных 120 s allowance. [Исходная проверка c9](candidate23-c9b2623-verification.json) · [Терминальный native outcome](candidate23-c9b2623-native-outcome.json).

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
| **Последний полный exact main `8bc7866c0da5ecf330deaafeaf107ac2b881ec79`** | [44140208148/attempt1](https://github.com/alexgazin/la-grilla/actions/runs/44140208148/attempts/1): **73 наблюдались / 71 PASS / 2 FAIL / 0 case allowance**, общий3600s timeout, elapsed3621.266 s, exit124/subprocess−15; xcresult не финализирован. Pinch-case не дошёл до жестов из-за readiness query, WideClip получил правильные x155/`4.00 bars` внутри6 s до прерывания лишнего query. LiveEditing→Pad полностью PASS83.255s/13.483s. SDK4 и fresh IPA static PASS, manual alpha. Следующий единый full73 после двух observer corrections и запаса на завершение Pending. |
| **Предыдущий полный exact main `82e4dfb02d2016dcbe31e7b34af6cd09b0f0457a`** | [44120318741/attempt2](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/attempts/2): **73 наблюдались / 71 PASS / 2 FAIL / 0 allowance**, exit65,3227.618s, без общего timeout. SDK4 и отдельная IPA static PASS. Legacy PLAYING-наблюдение после перестановки и запуск следующего Pad-case при завершении PID49770 не прошли; оба FAIL остаются историческими. |
| **Main23 / `0cfd12e3e1a821d50c7a1502f627329b7d60ff02`** | [iPhone/archive/full73 44083683395](https://github.com/alexgazin/la-grilla/actions/runs/44083683395) и [compatibility44083683721](https://github.com/alexgazin/la-grilla/actions/runs/44083683721): четыре SDK jobs PASS; **73 наблюдались / 70 PASS / 2 FAIL / 1 allowance**, exit65, без supervisor timeout. Все пять прежних регрессий и десять touch/sound/recording/landscape сценариев PASS; весь native gate ещё не принят. |
| **Candidate `7564fe7eff86cf6fbec1caab02d152fb1741c7d2`** | [Strict4 attempt1](https://github.com/alexgazin/la-grilla/actions/runs/44112860068/attempts/1): **4 PASS / 0 allowance**, exit0/subprocess0, timedOut=false, 261.479s. Jazz46.884s, setup43.305s, Composition36.929s, Speech74.992s. Scope input-diagnostic/fullAcceptance=false, не full73. SDK4 PASS: Debug/16.4 исходные; archive/26.0.1 повторены только после отмен до получения runner, native не повторялся. Свежая IPA проверена отдельно. Результат scoped4 не переносится на последующий main82e4: у него собственные проверенный архив и full73 71/2/0. |
| **`6504ccb` / [Assistant3 44107005380](https://github.com/alexgazin/la-grilla/actions/runs/44107005380)** | **2 PASS / 1 FAIL**, без allowance: Composition84.779s и Granted Speech94.857s PASS; Jazz48.698s FAIL до ввода/генерации на фактическом `unsupportedLanguage` для AI request locale `ru-RU`. Последующий7564 strict4 прошёл; исходный6504 FAIL остаётся историческим. |
| `c9b262334ad435310c2d80701dfce6fe6fbaddd5` | [Focused3 44077041024](https://github.com/alexgazin/la-grilla/actions/runs/44077041024): **0 PASS / 1 assertion FAIL / 2 allowance**, exit 65, без wrapper timeout. Bass FAIL, 104.540s, без allowance: restored1 присутствует в исходных кадрах до окна predicate, позже в свежем AX есть1/Register/Gate/PLAYING; тестовое наблюдение не подтвердилось. Flats: центр сработал, B♭/degree, Apply 101.03s, relaunch 104.57s, затем исходный 120 s при чтении reopened notes. Full transpose: реальные Apply/Undo и Redo 117.68s, затем исходный 120 s. Terminal duration для двух interrupted cases не выдавался и не выдумывается. [Debug/archive44077041006](https://github.com/alexgazin/la-grilla/actions/runs/44077041006) и [compatibility44077040988](https://github.com/alexgazin/la-grilla/actions/runs/44077040988): все четыре jobs PASS. Preview-IPA статически проверена, на hold. |
| `66effd2aa17974f169f5cc78dab4747435fad855` | [Focused3 44073353862](https://github.com/alexgazin/la-grilla/actions/runs/44073353862) завершился неуспешно: full transpose PASS, 100.510s; Flats FAIL, 90.890s, центральное значение0; Bass→Melody padded on/off PASS, далее missing `notes.count` assertion 116.49s и исходный 120 s allowance при завершении. [Debug/archive44073353758](https://github.com/alexgazin/la-grilla/actions/runs/44073353758) и [compatibility44073353829](https://github.com/alexgazin/la-grilla/actions/runs/44073353829): все четыре jobs PASS. Своя IPA статически проверена, историческая и на hold. |
| `57609025fc43741909c7204ec870cf839e2a58a6` | [Focused2 44069245545](https://github.com/alexgazin/la-grilla/actions/runs/44069245545): **1 PASS / 1 FAIL / 0 allowance**, exit 65. Full transpose PASS, 115.086 s; Flats FAIL, 111.366 s — после касания и нового AX-чтения значение switch осталось0. [Debug/archive 44069245450](https://github.com/alexgazin/la-grilla/actions/runs/44069245450) и [compatibility 44069245579](https://github.com/alexgazin/la-grilla/actions/runs/44069245579): все четыре jobs PASS; они не заменяют native. |
| `e2ec475e23167073cc02a08f30d3b5d413326b2a` | [Focused2 44064471496](https://github.com/alexgazin/la-grilla/actions/runs/44064471496): **1 PASS / 1 FAIL / 0 allowance**, exit 65. Full transpose PASS, 118.102s; Flats FAIL, 81.171s. [Debug/archive 44064471466](https://github.com/alexgazin/la-grilla/actions/runs/44064471466) и [compatibility 44064471511](https://github.com/alexgazin/la-grilla/actions/runs/44064471511): все четыре jobs PASS. Точная IPA независимо проверена, но focused/full gate не принят; файл указан выше как прежний пакет на hold. |
| `8f7cd0e`, [44059775230](https://github.com/alexgazin/la-grilla/actions/runs/44059775230) | 4 PASS / 1 allowance, exit 65: все три Perform и полный transpose Preview/Cancel/Apply/live/Undo/Redo/reopen прошли; Flats достиг 120 s. Весь targeted и полный gate не приняты. [Оригинальные прошедшие кадры](../../Screenshots/Build23Layout/README.md). |
| main22 `807c735`, [44046471258](https://github.com/alexgazin/la-grilla/actions/runs/44046471258) | Все 73 исполнились: 68 PASS / 4 assertion FAIL / 1 allowance. Это исходная полная регрессия до исправлений 23. |

В этой интеграции два Arrangement-helper читают по одному свежему полному `app.snapshot()` на poll с настоящими type/id/value/frame. Прежние6 s/3pt/точная длина/120 s и все тела, жесты, assertions сохранены; App/Pad/gesture-код не меняется. В последнем8bc Pinch-readiness прервался до Play/pan/pinch, хотя Clips уже виден в исходных AX/видео внутри6 s; после настоящего WideClip drag правильные x155/`4.00 bars` вернулись внутри6 s, затем лишний query прервался, inspector/Undo tail не исполнился. Общий command3900s/step70min/shared80min/job90min оставляет10min диагностике; все case budgets/600s/focused1500s сохранены. Все73 завершились лишь за0.385s до прежнего deadline, xcresult не успел финализироваться. Следующий единый полный73 Pending, без дополнительного focused-прогона. [Разбор GRID23](../../docs/review/2026-11-17/GRID23.md). Исторический82e4 KVC/Pad-startup [SECTION23](../../docs/review/2026-11-17/SECTION23.md) и все прежние failures сохраняются; новый полный PASS LiveEditing83.255s→Pad13.483s, включая Stop/hold/timing/counter, не суммируется с другими sources и не доказывает физический zero-gap PCM.

На доступной main8bc IPA вручную проверить Start → естественное окончание → поздний Stop без нового capture; Start → обычный Stop → повтор; смену языка/режима во время preview и закрытие помощника с реальным открытием исходного аккорда. Прежняя preview0cfd не содержит новые Stop-действия и сохранена отдельно.

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
