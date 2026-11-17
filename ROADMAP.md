# La Grilla — roadmap до App Store


> Текущий этап — Nocturne 24: новая система и пять основных экранов реализованы; Night owner PASS 103.043 s, оригиналы в Screenshots/Design26. Focused исходника 207fc2b:9 PASS/один case allowance/один not-observed, полный gate не принят. iPhone Debug/Release PASS; main dfa7 SDK4 PASS. Fixture оптимизирован без изменения проверок и лимитов; следующий полный75 Pending. Аппаратная и Store-приёмка открыты.
Обновлено: 17 ноября 2026. Источник требований: [исходная спецификация](docs/PRODUCT_SPECIFICATION.md), [дизайн](DESIGN_PROMPT.txt). Текущее приложение — в [README](README.md). Это рабочий план реализации, а не обещание готовности неизмеренных функций.

**Правило работы:** реализовать законченный сценарий → поведенческие тесты → native build/UI QA → реальные скриншоты в `Screenshots/<этап>/` → PR и merge в `main` → обновить этот файл и журнал проверок. По запросу владельца проверенные этапы интегрируются в `main`; проверки физического устройства остаются обязательным условием выпуска. Изменения дизайна и графику при необходимости делать через OpenArt. Скриншоты продукта — только из работающего приложения.

Подробная инженерная передача по этапам 0–5: [технический план стабилизации](docs/STABILIZATION_PLAN.md) — области кода, задачи, зависимости, проверки и артефакты приёмки.

## Nocturne 24 — текущий этап

1. Исследование 14 источников и [дизайн-контракт](DESIGN.md) — выполнено. Snapblocks недоступен, остальные выводы привязаны к первичным материалам.
2. Theme, shell/транспорт, Grid, Jam, Piano/Sound и Mixer — реализованы. Музыкальная геометрия, native touch, аудио и Undo сохранены.
3. Компиляция и IPA — PASS; пять Night PNG осмотрены и сохранены с provenance. Нового видео нет.
4. Focused11 — не принят:9 PASS, Light timeout в финальных проверках, PadContact startup interruption. Удалены дубли frame и лишние captures из нового fixture, без расширения120 s/15 s/6 s или удаления assertions.
5. Следующий единый полный75, включая оба design-кейса, — Pending. Исторические результаты не суммировать.
6. После software gate: реальный iPhone, аудиомаршруты и задержка, Voice/MIDI/модель/DAW, затем подпись и Store.

## Куда идём

**La Grilla — карманная студия для превращения музыкальной идеи в редактируемый скетч:** идея → аккорды → грув → мелодия/бас → исполнение → MIDI/WAV или продолжение в DAW. Основной пользователь — музыкант, битмейкер или продюсер, которому нужно быстро зафиксировать идею и развить её руками на iPhone. Гармония, сетка и живое исполнение должны работать как один инструмент.

Продуктовая ставка — быстрый рабочий процесс вокруг гармонии: увидеть и изменить аккорды, услышать A/B, записать ритм поверх цикла, применить понятное предложение помощника и сохранить переносимый результат. Помощник поддерживает структуру/гармонию и локальные команды. SketchComposer уже создаёт новые редактируемые аккорды, ударные, бас и мелодию в House/Hip-hop/Jazz на4/8/16 тактов с seed, A/B, Apply/Undo и MIDI. Музыку создаёт локальный композитор; доступная FoundationModels может интерпретировать параметры. Это bounded MIDI-скетч, не генерация вокальной аудиопесни.

Продуктовая цель для проверки на пользователях: музыкант, знакомый с базовыми аккордами, сохраняет первый восьмитактовый скетч за 5–10 минут без внешнего обучения. Это целевой сценарий, его скорость и понятность ещё предстоит измерить.

## Конкуренты и ориентиры

Ближайший ориентир по общему сценарию карманной студии — **Ableton Note**; в работе с гармонией прямые соседи — **Chordbot** и **Suggester 2**, а по широте мобильной музыкальной среды рядом **KORG Gadget**. Карта ниже сравнивает назначение продуктов; перед решениями о цене и продвижении нужен отдельный актуальный анализ версий и пользовательских отзывов.

| Продукт | Где пересекаются пользовательские задачи | Что проверяем у La Grilla |
| --- | --- | --- |
| [Chordbot](https://www.chordbot.com/) | Аккордовые последовательности, стили аккомпанемента и перенос MIDI/WAV в DAW | Понятность гармонии, звучание аранжировки и скорость получения полезного скетча |
| [Suggester 2](https://apps.apple.com/us/app/suggester-2-chords-scales/id6448964737) | Подбор аккордов по гармонической функции и развитие последовательности | Полезность подсказок, ручное редактирование и переход от гармонии к ритму |
| [Ableton Note](https://www.ableton.com/en/note/) | Быстро зафиксировать музыкальную идею на телефоне и развить её в студии | Скорость первого грува, понятный переход между гармонией и ритмом, перенос результата в DAW |
| [KORG Gadget](https://www.korg.com/us/products/software/korg_gadget/) | Создание композиции в мобильной инструментальной среде | Согласованность инструментов, секций, микшера и общего транспорта |
| [GarageBand](https://www.apple.com/ios/garageband/) | Знакомая широкая точка входа в музыку на iPhone | Простота первого запуска, предсказуемость записи и сохранения; заметная польза гармонической сетки |
| [Koala Sampler](https://koalasampler.com/) | Быстрое создание ритмической идеи и игра пальцами | Отзывчивость пэдов, минимум действий до слышимого результата, удобство overdub |
| [Loopy Pro](https://loopypro.com/) | Работа с циклами и управление исполнением в реальном времени | Непрерывность звука, понятные состояния записи/лупа, надёжность управления руками |
| [Cubasis](https://www.steinberg.net/cubasis/) | Детальное редактирование и развитие мобильного проекта | Качество редакторов и экспорта при сохранении простого основного сценария |
| [BandLab](https://www.bandlab.com/) | Доступное создание и развитие музыкальных идей | Понятность помощника и завершение музыкального результата; наш текущий приоритет — локальный рабочий процесс |

Преимущество пока является гипотезой позиционирования. Его должны подтвердить скорость работы, качество музыкального результата и реальные пользователи. Само количество экранов или наличие кнопки ИИ этого не доказывает.

## Где мы сейчас

**Последний полный main23/schema11 — `8bc7866`.** Четыре SDK jobs PASS; свежая exact-main IPA независимо проверена. [Run44140208148/attempt1](https://github.com/alexgazin/la-grilla/actions/runs/44140208148/attempts/1): **73 наблюдались / 71 PASS / 2 FAIL / 0 case allowance**, supervisor timedOut=true, exit124/subprocess−15, elapsed3621.266 s. Все методы завершились лишь за0.385s до общего3600s deadline; xcresult не успел финализироваться. Pinch-case остановился на readiness до жестов, хотя исходные AX/видео внутри6 s показывают Clips. В WideClip live AX внутри6 s вернул правильные x155 и `4.00 bars`, затем прервался лишний query. Оба метода остаются FAIL. Прежние LiveEditing→Pad полностью PASS83.255s/13.483s с Stop/hold/timing/counter, без суммирования исходов. Интегрируются два наблюдателя с одним свежим app.snapshot на poll, прежними6 s/3pt/точной длиной/120 s и всеми действиями; command3900s/step70min/shared deadline80min в job90min оставляет10min диагностике. Все case budgets, потолок600s и focused1500s сохранены. Следующий единый full73 Pending. [Разбор GRID23](docs/review/2026-11-17/GRID23.md). Исторические82e4 —71/2/0 с KVC→Pad-startup failures,7564 strict4 и0cfd70/2/1 сохраняются отдельно; результаты не суммируются.

Прогоны `e2ec475` и `5760902` завершены: полный transpose **PASS, 118.102s / PASS, 115.086 s**, Flats **FAIL, 81.171s / FAIL, 111.366 s**, в обоих **0 allowance**. На `5760902` новое AX-чтение после касания показало0. Все четыре SDK/archive/compatibility jobs обоих источников прошли; их outcomes и прежние IPA сохраняются как история.

На `66effd2` полный transpose **PASS, 100.510s**, Flats **FAIL, 90.890s** с центральным значением0; Bass→Melody прошёл padded on/off, затем assertion о `notes.count` не подтвердился и исходный 120 s allowance сработал при завершении. На `c9b2623` центральное касание уже изменило нотацию: Flats дошёл до B♭/degree, Apply и реального store/relaunch, но достиг исходного 120 s при чтении повторно открытых нот. Full transpose выполнил Apply/Undo и дошёл до Redo 117.68s, затем также достиг исходного 120 s. Bass завершился assertion FAIL, 104.540s без allowance; исходные кадры подтвердили восстановленное1 до окна predicate, а свежий AX — Register/Gate и PLAYING. Это дефект наблюдения тестом, а не доказательство потери касания. Ни один из трёх исходов не переименовывается в PASS.

Адресный `6504ccb` прошёл Composition84.779s и Granted Speech94.857s; Jazz48.698s остановился до ввода на реальном `unsupportedLanguage` для AI locale `ru-RU`. Новый fixture учитывает язык запроса, а не объявляет глобальную недоступность или генерацию модели. Strict4 source7564 прошёл отдельно; main82e4 и последний8bc7866 имеют каждый свой полный73 71/2/0 и проверенный архив с разными SHA-256. [Точный статус](docs/release/CURRENT.md) · [Альфа и установка](Builds/Testing/README.md).

Ночная тема, пэды, live resize, Sound Classic/Warm/Bright и opt-in Tilt Filter/Volume реализованы. Их эргономика и задержка на реальном телефоне, Mic/Speech, человеческий Voice-to-MIDI, реальная модель, маршруты и контроллеры остаются аппаратными проверками. Все34 замечания четырёх ролей сохраняются в [плане](docs/review/2026-11-16/PLAN.md); код и Simulator не заменяют критерии приёмки.

## Следующие этапы и критерии перехода

| Этап и приоритет | Конкретная работа | Условие завершения |
| --- | --- | --- |
| **0. Подтвердить установленную 23 — P0** | Повторить исправленные output/input startup и восстановление реального аудиомаршрута, разрешения/callback Speech, независимость ProjectStore от аудио-ошибки и создание проекта. Доступность модели должна оставлять рабочие локальные Commands. Ошибка получает понятный Retry и диагностику без записанного звука. Повторить захват с уже разрешёнными Mic/Speech, проверить реальные input formats и измерить паузу при переходе output-only → capture. | На установленном кандидате работают Play, пэды, открытие/создание/сохранение проекта и диктовка с разрешением либо отказом. Запуск/Play не запрашивают микрофон. Нет вылетов, потери проекта и дублирующего блокирующего сообщения об аудио. Остаточные ограничения подтверждены и явно записаны. |
| **1. Стабильный основной сценарий — P0/P1, после этапа 0** | Пройти единый музыкальный маршрут ниже, исправить Undo/Redo, переходы между экранами, save/reopen, import/export и пустые состояния. Проверить RU/EN, Light/Dark, большие шрифты, VoiceOver, компактный и горизонтальный экран. Повторять на одной точной сборке; учитывать ошибки и повторные попытки. | Сценарий повторяем на реальных телефонах; открытых P0/P1 нет. Сохранённый и экспортированный результат совпадает с редактором. Доступность и новые состояния просмотрены в оригинальных кадрах, полный CI относится к этому source. |
| **2. Надёжный голос и помощник — P1, зависит от стабильного ядра** | Разделить диктовку текста и Voice-to-MIDI. Проверить Speech denial/unavailable/interruption; живой mono-напев на корпусе с эталонными нотами/ритмом, confidence и ручную коррекцию. Для FoundationModels измерить реальные proposals, время ожидания, язык, Cancel, Apply/Undo на eligible iPhone; выключенная/неподдерживаемая модель объясняется корректно. | Известны измеренные ошибки голосового преобразования и границы beta; исходник сохранён. Поддерживаемые Commands работают без Apple Intelligence. Реальная модель проверена отдельно от parser/fixtures, состояние подготовки/недоступности не выдаётся за генерацию. |
| **3. Музыкальная глубина и удобство исполнения — после стабильного скетча** | Довести существующие Harmony A/B, note/clip editing, Live Jam, секции, фильтр/FX, запись и replay исполнения по реальным музыкальным сессиям. Уменьшить число действий до полезного результата. Завершить native-приёмку уже реализованного редактируемого SketchComposer, transpose/writing и корректного portable-import на8/16 тактов; не оставлять выполненный код в статусе будущего прототипа. | Живое исполнение, replay и экспорт согласованы. Расширение генерации принимается по фактическим нотам/ритму, возможности редактирования и одной Undo-транзакции. Готовность версии 1.0 определяется стабильностью обязательного сценария; экспериментальные генераторы получают отдельный статус. |
| **4. Закрытая beta и аппаратная приёмка — P1, после этапов 0–2** | Подписанный установленный кандидат, затем TestFlight. Выполнить 30-минутные P1/P2/P3 сессии, измерить задержку/нагрев/память и слышимый output. Проверить speaker/wired/USB/Bluetooth, звонок/lock/background, MIDI reconnect/Panic, импорт MIDI/WAV/stems в две реальные DAW. Собрать повторяемые отзывы первых музыкантов и устранить найденные блокеры. | Заполнен [протокол устройства](docs/release/DEVICE_ACCEPTANCE.md) для точного source/build, есть фактические результаты маршрутов и DAW. Нет P0/P1; beta-результаты подтверждены установленным бинарником. Для локального запуска достаточно Personal Team; платное членство требуется на этапе TestFlight/App Store. |
| **5. App Store release — после принятой beta** | Заморозить объём 1.0, собрать signed Release, сверить privacy/support/age rating/metadata с бинарником, обновить Store-скриншоты EN/RU. Новое видео отменено владельцем. Пройти App Review и проверить production-установку. | Точные release source/version связаны с успешным обязательным CI, подписанным и установленным build. Карточка соответствует работающим функциям и ограничениям. Приложение доступно пользователю в Store; пройден production smoke. |

### Конкретный остаток сборки 23

1. Исполнить один новый единый exact-main full73 после двух исправлений Arrangement-наблюдения и запаса на финализацию: по одному свежему snapshot на poll, прежние6 s/3pt/точная длина/120 s и все действия. Общий command3900s, step70min/shared80min в job90min; остальные case budgets/600s/focused1500s сохранены. Результат Pending. Последний8bc остаётся71/2/0 с общим timeout; предыдущий82e4 остаётся71/2/0 с KVC/Pad-startup failures. Прошедшие в8bc LiveEditing→Pad и отдельные7564 scoped4/0cfd70/2/1 не складываются в full acceptance. [GRID23](docs/review/2026-11-17/GRID23.md).
2. На установленной 23 проверить два пальца/плотный ритм/удержание/cancel, speaker/wired/Bluetooth, перенос/resize у краёв, одно Undo, выбор тембра и Tilt Filter/Volume с повторной калибровкой/фоном/ориентациями. Фиксировать конкретные задержки и неудобные жесты.
3. Повторить полный музыкальный маршрут: Empty/скетч/8–16 тактов/save/reopen/MIDI/WAV/portable. Затем — реальные Mic/Speech, доступная FoundationModels, human Voice-to-MIDI и ручное review исходника.
4. Выполнить C8: USB/BLE, две DAW, minimum-iOS18 installed launch,30мин P1/P2/P3, latency/thermal/memory и слышимая непрерывность. Неподтверждённые измерения остаются открытыми.
5. После программной и аппаратной приёмки подготовить distribution signing/TestFlight/Store metadata/EN-RU screenshots/App Review. Personal Team подходит для нынешней ручной IPA; платное членство отложено до distribution.

Новые прошедшие оригиналы 23 хранятся в [Build23Layout](Screenshots/Build23Layout/README.md), исходные доработки22 — в [Build22Touch](Screenshots/Build22Touch/README.md), каждый со своим source/run/hash. Новое видео отменено владельцем; исторические19/20 PNG и видео15 сохраняются без переименования.

### Основной музыкальный маршрут

Создать проект → поставить аккорды в четыре такта → записать и поправить бит → добавить бас/мелодию → собрать куплет и припев → изменить баланс → сыграть и сохранить исполнение → закрыть и открыть проект → экспортировать MIDI и WAV → открыть результат в DAW. Отдельная ветка проходит весь путь без доступной модели ИИ; состояние аудио-ошибки отдельно проверяет сохранение и экспорт без потери работы.

### Дизайн и качество сопровождают каждый этап

Понятные loading/empty/error состояния, минимальная цель нажатия 44 pt, читабельные RU/EN тексты, контраст, Light/Dark, Dynamic Type, VoiceOver и Reduce Motion входят в критерии изменений. Новая графика при необходимости создаётся через OpenArt; продуктовые скриншоты и записи берутся из принятого работающего приложения. Улучшение оформления не заменяет проверку звука, данных и жестов на телефоне.

UX-доводка этапа 1 начата в кандидате 17: музыкальный review показывает такты, доли и ноты без служебных ticks. Проверить, что пустой проект подсказывает следующий слышимый шаг, недоступный ИИ оставляет рабочие команды, а ошибки не перекрывают сохранение. Эти пункты принимаются по работающему сценарию и кадрам, а не только по наличию элементов.

### После первого релиза

Сначала — стабильность, короткий путь к первому сохранённому скетчу и устранение повторяющихся проблем по отзывам. Затем — ранжирование расширений по спросу: более глубокие музыкальные генераторы, дополнительные способы исполнения/управления, форматы обмена и профессиональные рабочие процессы. Цены, платная модель и дополнительные сервисы требуют отдельного решения на основе проверенной пользы и затрат. Новые функции проходят тот же цикл: реализация → проверка → оригинальные кадры → merge → актуальный журнал.

Ближайшая цель — завершить полный main73 и подтвердить **этап 0 на установленной 23**, затем принять **этап 1**. Готовность этапов определяется результатами, а не календарным обещанием. Технические контракты уже реализованных блоков и открытые внешние проверки сохранены ниже.

## История программного кандидата — 1.0.0 (15), schema 8

[Профессиональный стартовый пакет](docs/PRODUCT_FINISHING.md): нативный launch screen, сохранённая брендовая иконка, первое знакомство с повторным входом из Settings, разделённые настройки приложения/проекта и защита восстановленного проекта от преждевременного save. Полная программная регрессия source `838b4847`, [run 43812214574](https://github.com/alexgazin/la-grilla/actions/runs/43812214574), прошла: три jobs, 118 Swift tests / 19 suites, 15 C++ suites, 623 EN/RU keys, 46 функциональных native methods и один намеренный diagnostic SKIP; bulk capture не запускался.

Последующая правка appearance presented Form — source `014a00b9`, [focused run 43819149979](https://github.com/alexgazin/la-grilla/actions/runs/43819149979): **два метода Theme/Welcome PASS**, а не повтор всех 46 сценариев. В [ProfessionalShell](Screenshots/ProfessionalShell/README.md) сохранены три EN оригинала с собственным source/run: welcome `838b4847`, Light/Dark Settings `014a00b9`. Историческая [рабочая видеодемонстрация — 132,2с](Media/WorkingDemo/README.md) показывает настоящие действия и звук тех же сессий; исходный capture-workflow сохраняет задокументированный post-roll FAILURE, отдельные проверенные интервалы не выдаются за успешный полный release run.

Это не утверждение о полном прогоне финального `main`: exact-main CI обязателен перед distribution. **C8 остаётся открытым**; новые guide кадры RU/compact/large type и аппаратные проверки не объявлены выполненными. Историческая C1–C7 приёмка кандидата 14 сохранена ниже без смены источника.

## Завершение исходного видения — C0–C8

Программная реализация **C1–C7 принята для 1.0.0 (14), schema 8**: [полный run 43771988471](https://github.com/alexgazin/la-grilla/actions/runs/43771988471), source `77fb72ab82cd800eb8131136628c416ad83c9046`. Прошли 118 Swift tests / 19 suites, 15 C++ suites, 603 EN/RU keys, все 44 функциональных native сценария и три capture methods. [73 оригинала](Screenshots/OriginalVision) просмотрены индивидуально; Store 12 и четыре превью сохраняют их bytes. Интеграция — [PR #13](https://github.com/alexgazin/la-grilla/pull/13); [текущий main CI](https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml?query=branch%3Amain) проверяет точный merge commit перед distribution.

Контракты каждого этапа — [план C0–C8](docs/ORIGINAL_VISION_COMPLETION.md), подробная история ошибок и исправлений — [журнал](docs/IMPLEMENTATION_LOG.md), измерения и пределы — [приёмка C7](docs/release/C7_ACCEPTANCE.md).

| Этап | Результат | Статус |
| --- | --- | --- |
| C0 | Сверка исходных идей, зависимости, контракты и журнал | Выполнено |
| C1 | 65 качеств аккордов, aliases, custom formulas/voicings, schema 8 | Host/native/export/migration приёмка пройдена |
| C2 | Круговой DJ filter, Reset, AX, запись/replay | Принят ранее через PR #14; общая регрессия пройдена |
| C3 | Move/copy/resize клипов, совместимые дорожки, section drag, anchored pinch | Все шесть native Arrangement cases прошли; шесть original synthesized touch events независимо подтверждают anchor |
| C4 | Atomic music/mix/preset/FX snapshots и live edits без Stop | Native snapshot/MIDI/live editing/drum overdub прошли вместе |
| C5 | Общий duplex input, original CAF и voice review/Apply/store/Undo | Две настоящие production CAF цепи прошли; timestamp spacing и физическая непрерывность остаются отдельно в C8 |
| C6 | Typed on-device AI adapter, RU/EN Commands, Jazz/whole-song review | Adapter и native Commands/review/Apply/Undo приняты; реальная модель/язык/качество — C8 |
| C7 | Общая QA, совместимость, новые кадры и кандидат 14 | Полный software/native run и визуальная приёмка пройдены; exact-main CI обязателен перед distribution |
| C8 | Устройства, реальные модели/голоса, signing, TestFlight, App Review | Внешняя приёмка открыта |

Предыдущий принятый базовый этап C2 — `912dc483`, версия 13, exact-main run `43719321757` — сохранён как история. Семь [progress PNG](Screenshots/OriginalVision-progress) имеют собственные источники и не переименованы в финальную коллекцию. Исторические failures, включая CoreMIDI −304 и неправильные QA expectations, не скрыты. Отсутствие физических dropouts, minimum-iOS-18 installed launch, реальная модель/живой напев, подпись и публикация не объявлены проверенными.

## История выполненных базовых этапов

| Этап | Объём | Приёмка / артефакт | Статус |
| --- | --- | --- | --- |
| R0. База v0.1 | Grid, Harmony/Drums/Bass, Jam, takes, Mixer, projects, Undo, autosave/recovery, MIDI | 14 domain/storage tests + C++ + 4 native UI tests, обе SDK-сборки, 4 скриншота. [QA](docs/QA.md), [PR #1](https://github.com/alexgazin/la-grilla/pull/1) | **Слито в main** |
| R1. Переносимый результат | WAV mixdown, stems, 44.1/48 kHz, 16/24 bit, tail, диапазон; export progress/cancel; переносимый `.grillapack`, импорт копией | Файлы открываются независимым WAV/ZIP reader; mix/stem alignment, deterministic render, finite duration, cancel cleanup, project round-trip. Live transport не переключается в offline mode | **Слито в main** |
| R2. Полный нотный редактор | Melody/piano roll, до 8 дорожек, add/move/resize/delete notes, velocity, selection, copy/paste, clip/section operations, zoom/drag arbitration | Создать мелодию, изменить ноты, Undo, сохранить/открыть и услышать/экспортировать ровно те же ноты. Нет потери v1-проектов | **Слито в main** |
| R3. Гармоническая лаборатория | 9/11/13, alterations/slash bass, voicing/range/voice leading; мягкая/выразительная стилизация и reharm | Объяснимое предложение с исходными/новыми аккордами, A/B, Apply/Cancel, одна Undo-транзакция. Хроматика и ограничения видны | **Слито в main** |
| R4. Assistant | RU/EN локальные команды tempo/key/sections/progressions; dictation отдельно от напева; typed proposals, scope, assumptions, stale/double-apply guards | Команда → preview → Apply или Cancel. Нет скрытого редактирования, неподтверждённых сетевых обещаний или ключей в клиенте. Cloud provider только через защищённый backend, если понадобится | **Слито в main** |
| R5. Voice-to-MIDI | Microphone permission, headphones guidance, count-in, запись исходного mono audio, monophonic pitch/onset/confidence, quantize/scale snap, piano-roll correction/A-B | Синус/напев/пауза/шум/octave-jump набор; сомнительные ноты видны, тишина остаётся тишиной, Apply/Cancel сохраняют исходник до решения | **Слито в main** |
| R6. Perform | Quantized section launch/cancel, repeat/jump, filter/repeat FX, bounded smoothing, finite performance-take с replay/export | Отрепетировать секции → записать исполнение → воспроизвести и экспортировать тот же порядок/автоматизацию без stuck notes | **Слито в main** |
| R7. MIDI devices | Core MIDI USB/BLE, endpoint selection, MIDI in/out, learn/map, channel filtering, disconnect/panic | Реальный input/output и проверка unplug/sustain на USB и BLE. Bluetooth audio latency не смешивается с BLE MIDI | **Слито в main; аппаратная проверка открыта** |
| R8. Продуктовая полировка | Профессиональная иконка/графика через OpenArt, тёмная/светлая темы, RU/EN, Dynamic Type/VoiceOver, touch ≥44 pt, 375 pt/landscape, empty/error/recovery states | Реальные screenshots всех сценариев и размеров; audit доступности и состояния ошибок; ни одной декоративной неработающей кнопки | **Слито в main** |
| R8.1. Дизайн 2026 | Самостоятельное направление через OpenArt; узнаваемая музыкальная сетка, типографика и цвет; упрощённые Harmony/Perform, компактные основные действия и единые компоненты во всех режимах | Реализованный SwiftUI-интерфейс; реальные EN/RU, light/dark, 375 pt и landscape кадры; 44 pt targets, AA, Dynamic Type/VoiceOver, рабочие сценарии и обновлённый Store-набор | **Программная реализация и QA готовы; [PR #12](https://github.com/alexgazin/la-grilla/pull/12). Физическая доступность остаётся открытой** |
| R9. Стабилизация | Schema migrations/import safety, bounded queues/voices, gain/pan/voice-steal fades, clipping/meter reset, interruptions/routes/background/media reset, P1/P2/P3 load fixtures | Автотесты и 30 min физический load/latency/CPU/memory отчёт, audio route/device matrix, MIDI round-trip в 2 DAW, восстановление после kill/save failure | **Слито в main; software QA пройдена, физическая часть открыта** |
| R10. Release candidate | Версии/build numbers, Release/archive CI, privacy manifest и RU/EN policy/support, licenses/provenance, store metadata, screenshots, export compliance, signing/TestFlight scripts | Воспроизводимый архив, checklist без выдуманных выполненных пунктов, установленный TestFlight build, закрытые blocker/critical defects | **Кандидат 1.0.0 (12) и software QA готовы; signing/TestFlight и device QA открыты** |
| R11. App Store | Проверка установленного RC, App Store Connect listing/age rating/privacy, upload, review, production smoke | Доступная пользователю production-сборка и проверка установленного build | Ожидает установленный проверенный RC и Apple Developer/App Store Connect |

## Состояние и зависимости

R1 → R2 → R3 → R4; R2 и аудиосессия → R5; transport/compiler → R6 → R7. R8 и R9 сопровождают каждый этап, R10/R11 завершают выпуск. Аппаратные и внешние проверки не блокируют независимую разработку, но не могут быть отмечены выполненными по результату симулятора.

### Завершено: R1–R5

- [x] Offline renderer использует тот же compiler и DSP kernel, отдельный экземпляр, без изменения live engine.
- [x] WAV PCM stereo 44.1/48 kHz, 16/24 bit, range, release tail, progress/cancel.
- [x] Stems с общей стартовой точкой, контролируемой семантикой mute/solo/master и manifest.
- [x] Переносимый project pack, проверки schema/size/path, импорт независимой копией.
- [x] Native export/import flow, работающие кнопки, локализация, UI regression и новые screenshots.
- [x] Документированные проверки и merge R1 в `main`.

## Журнал

- **14.11.2026 — R0:** PR #1 слит в `main` (`947a177`). Подтверждены 14 Swift tests, kernel regressions/sanitizers, 4 native UI flows и SDK builds. Физический iPhone, DAW и подпись не объявляются проверенными.
- **14.11.2026 — R1:** WAV/stems/project pack реализованы; 21 Swift test, независимые WAV/ZIP readers, C++ regressions, обе SDK-сборки и 6 native UI tests проходят. Реальные изображения — `Screenshots/R1`. Следующий этап R2 уже разрабатывается отдельно.

## Условия, которые нельзя заменить кодом или макетом

Физический iPhone/наушники/USB и BLE MIDI нужны для аппаратных измерений; DAW — для фактического импорта; Apple Developer signing/App Store Connect — для TestFlight и публикации. В среде пока нет этих устройств/учётных данных. Все независимые программные этапы продолжаются; доступ запрашивается только когда соответствующий конкретный результат готов к этой внешней проверке/публикации.

- **15.11.2026 — R2:** piano roll, melody, 8 каналов и schema migration реализованы; 28 Swift tests, C++ routing, обе SDK-сборки и 8 native UI tests проходят. Реальные экраны — `Screenshots/R2`.

- **15.11.2026 — R3:** 9/11/13, altered/slash chords, bounded voicings, voice leading, scoped reharm и A/B реализованы. 35 Swift tests, C++ restart regression, обе SDK-сборки и 9 native UI tests проходят. Экраны — `Screenshots/R3`.

- **15.11.2026 — R4:** RU/EN local Assistant, проверяемые предложения, выбор длительностей, A/B и одна Undo-транзакция реализованы. 42 Swift tests, обе SDK-сборки и 11 native UI tests проходят; `Screenshots/R4`. On-device Speech adapter собран, реальная диктовка требует физического устройства/доступной модели.

- **15.11.2026 — R5:** mono recording/count-in, original/instrument review, YIN/autocorrelation comparison, confidence/correction, quantize/scale, source-preserving packages и schema v4 реализованы. 54 Swift tests, независимый CAF/SHA-256/ZIP reader, обе SDK-сборки и 12 native UI tests проходят. 15 экранов — `Screenshots/R5`; реальный напев остаётся beta/device gate.

- **15.11.2026 — R6:** quantized launch/cancel, beat jump/repeat, filter/delay, runtime mixer, finite frozen-source take, replay и WAV/MIDI export реализованы. 60 Swift tests, 3 C++ suites, независимый PCM/SMF reader, обе SDK-сборки и все 14 native UI flows проходят. 18 реальных экранов — `Screenshots/R6`. MIDI-устройства и продуктовая полировка разрабатываются отдельно.

- **15.11.2026 — R7:** Core MIDI input/output, endpoint/channel selection, sustain, CC Learn, finite input capture и emergency Panic реализованы. 62 Swift tests, 6 C++ suites, обе SDK-сборки, 15 native UI flows и захват 20 экранов проходят: run `43680458783`, app source `223615f`. Физические USB/BLE и DAW остаются релизными воротами.

- **15.11.2026 — R8:** светлая/тёмная темы, OpenArt icon/provenance, RU/EN и доступные/компактные/landscape layouts реализованы. Source `595d4a3`, run `43682961615`: 62 Swift, 6 C++ suites, обе SDK-сборки и 18 native UI flows проходят. Три новых QA-кадра — `Screenshots/R8`.

- **15.11.2026 — R9:** schema 7/versioned instruments, atomic mixer, incremental repeat, voice tails, microphone ownership, background/system transport и recovery hardening реализованы. Source `cd2ae56`, run `43681942977`: 64 Swift, 11 C++ suites, обе SDK-сборки, 19 Studio flows и два capture tests проходят. 36 original PNGs — `Screenshots/R9`; импортируемые P1/P2/P3 — `docs/release/fixtures`.

- **15.11.2026 — R10:** технический кандидат 1.0.0 (11), текущая цепочка Xcode 26.3 / iOS 26.2, privacy/store/support и signing/TestFlight automation подготовлены. Source `ecfc9b9`, run `43689852307`: 64 Swift, 11 C++ suites, обе SDK-сборки, 19 Studio flows, RU Pro Max/SE captures и Release-архив проходят. Исправлены MIDI boundary routing/Off-before-On, 13 пропущенных переводов и Master/quantize labels. Сохранены 51 native PNG с source/hash и 12 Store-копий. Подпись, физические измерения и публикация не выполнены.

- **15.11.2026 — R8.1:** новый дизайн реализован во всех режимах: сетка и курсор как фирменный мотив, графит/лайм и цветовые роли партий, единые поверхности/типографика, компактный транспорт, Harmony A/B/Apply, живой Perform, Jam и адаптивный Mixer. OpenArt-направление и иконка сохранены с provenance. Исправлены пустая область нажатия строки подсказки и настоящие 44 pt кнопки Pads/Steps. Source `d63be9e`, [run 43699657512](https://github.com/alexgazin/la-grilla/actions/runs/43699657512): 64 Swift, 11 C++ suites, обе SDK-сборки, архив и все 19 Studio flows проходят. [Run 43700109621](https://github.com/alexgazin/la-grilla/actions/runs/43700109621) повторно подтверждает 19 сценариев и шесть EN/RU compact-кадров. Полная визуальная приёмка и источники кадров — [Design QA](docs/DESIGN_QA.md); интеграция — [PR #12](https://github.com/alexgazin/la-grilla/pull/12). Подпись, физические измерения, TestFlight и App Review остаются открытыми воротами.

  **Финальная визуальная приёмка R8.1:** source `72d81cb`, [run 43700372709](https://github.com/alexgazin/la-grilla/actions/runs/43700372709) полностью проходит: 64 Swift, 11 C++ suites, обе SDK-сборки/архив и 22 native tests (19 сценариев + три захвата). Сохранены [54 оригинальных кадра](Screenshots/Design2026) и [12 неизменённых Store-копий](Screenshots/AppStore) с source/run/размерами/SHA-256. Корневые превью обновлены; прежние четыре кадра сохранены в R0.

### 16 ноября · восстановление записи и новый аудит

Кандидат 17 `5adbadb`: все 7 focused native methods PASS, 379.622 s; Debug/archive/16.4+26.0.1 compatibility PASS. Полная exact-main регрессия и физический повтор открыты. Все 34 замечания четырёх ролей учтены в [плане](docs/review/2026-11-16/PLAN.md); развивающий пакет PR #21 проходит отдельную приёмку. Текущие доказательства — [CURRENT](docs/release/CURRENT.md).
