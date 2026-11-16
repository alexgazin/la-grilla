<p align="center">
  <img src="Design/2026/openart-icon.png" width="88" alt="Иконка La Grilla — музыкальная сетка и курсор">
</p>

<h1 align="center">La Grilla</h1>

<p align="center"><strong>Идея → грув → трек.</strong><br>Карманная студия для iPhone: сочиняйте гармонию, играйте бит, собирайте аранжировку и забирайте музыку в свою DAW.</p>

<p align="center">
  <a href="https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml?query=branch%3Amain"><img src="https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml/badge.svg?branch=main" alt="Проверки iOS на main"></a><br>
  iOS 18+ · SwiftUI · нативный звук · RU / EN · без аккаунта
</p>

<p align="center"><a href="#возможности-текущей-реализации">Возможности</a> · <a href="docs/release/CURRENT.md">Статус кандидата</a> · <a href="#установить-на-свой-iphone">На свой iPhone</a> · <a href="ROADMAP.md">Роадмап</a> · <a href="docs/IMPLEMENTATION_LOG.md">Журнал разработки</a></p>

## IPA для тестировщика

**[Скачать La Grilla 1.0.0 (17) · IPA, 3.2 MiB](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Builds/Testing/LaGrilla-1.0.0-17-unsigned.ipa)** — iPhone / iOS 18+, подпись своим Apple ID через Sideloadly на Mac или Windows. Платная команда не нужна; бесплатная подпись действует 7 дней. [Установка и проверенный исходник](Builds/Testing/README.md).

## Независимый разбор и план доведения до релиза

[**Сводный план: 34 замечания, 10 направлений и критерии приёмки**](docs/review/2026-11-16/PLAN.md) · [Аналитик](docs/review/2026-11-16/analyst.md) · [Продакт-менеджер](docs/review/2026-11-16/product-manager.md) · [Тестировщик](docs/review/2026-11-16/qa.md) · [Архитектор](docs/review/2026-11-16/architecture.md).

Честный статус — функциональная альфа. Сильные стороны: редактируемая гармония, общий музыкальный транспорт, A/B, Undo и переносимый проект. Основные незакрытые проверки — первый сеанс со звуком на физическом iPhone, живые Speech/Apple Intelligence, задержки записи поверх лупа и работа с настоящими контроллерами и DAW.

[PR #21](https://github.com/alexgazin/la-grilla/pull/21) доводит первый результат в новом проекте, помощника, транспонирование, безопасность документов, производительность и CI. В первом прогоне кандидата 18 прошли 7 из 11 сценариев; найдены два дефекта названий нот и два таймаута тестов транспонирования. Исправления и новые редактируемые скетчи готовятся в кандидате 19; его нативная приёмка ещё впереди. **Последняя полная принятая программная база — 16**: [полный запуск](https://github.com/alexgazin/la-grilla/actions/runs/43858734785), 51 PASS / 0 FAIL / 1 diagnostic SKIP. Это отдельные источники и статусы.

## La Grilla в работе · настоящее видео со звуком

[![La Grilla в работе — настоящие нажатия, жесты и звук приложения](Media/WorkingDemo/teaser.gif)](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)

**[▶ Смотреть рабочую демонстрацию — 2:12, Full HD, со звуком](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)** · [Полная запись без монтажных сокращений](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-session-original.mp4)

Запись **iOS Simulator, сборка 1.0.0 (15)**: настоящий Play, редактирование аккорда, pinch-to-zoom, пэды и overdub, шаги, микшер, ноты, Harmony A/B, Commands, Perform и WAV в системном меню экспорта. Звук записан с аудиовыхода тех же сессий; слышны pan, mute и фильтр. Три сессии смонтированы с сокращением ожиданий, действия идут в обычном темпе. Voice показан на этапе подготовки записи, beta/mono. [Происхождение, монтаж и проверки](Media/WorkingDemo/README.md).

<details>
<summary>Презентация возможностей на настоящих скриншотах · 1:36</summary>

[![La Grilla — анимированное превью промо: идея, грув, трек](Media/Promo/teaser.gif)](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/Promo/la-grilla-promo.mp4)

**[▶ Смотреть / скачать полное видео — 1:36, Full HD, со звуком](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/Promo/la-grilla-promo.mp4)**

11 глав: Grid → Arrange → Jam → Notes → Harmony → Assistant → Voice → Perform → Mixer → MIDI → Export. Анимация собрана из настоящих экранов приложения; оригинальная музыка создана штатным синтезатором и offline-рендерером La Grilla. GIF без звука; полный саундтрек — в MP4. [Главы, исходники и музыкальный проект](Media/Promo/README.md).

</details>

## Студия в девяти экранах

Настоящие экраны **1.0.0 (14)** из работающего приложения в iOS Simulator. Нажмите на изображение, чтобы открыть оригинал.

<table>
  <tr>
    <td align="center" valign="top" width="33%">
      <strong>Grid · форма трека</strong><br><sub>Аккорды, дорожки, такты и секции</sub><br><br>
      <a href="Screenshots/OriginalVision/grid.png"><img src="Screenshots/OriginalVision/grid.png" width="220" alt="Grid: аккорды C, Am, F, G, барабаны и бас на мультитрековой сетке"></a>
    </td>
    <td align="center" valign="top" width="33%">
      <strong>Jam · сыграть грув</strong><br><sub>16 пэдов, квантование и overdub</sub><br><br>
      <a href="Screenshots/OriginalVision/jam.png"><img src="Screenshots/OriginalVision/jam.png" width="220" alt="Jam: шестнадцать барабанных пэдов и запись в четырёхтактовую петлю"></a>
    </td>
    <td align="center" valign="top" width="33%">
      <strong>Mixer · найти баланс</strong><br><sub>Вертикальные фейдеры, pan, mute / solo</sub><br><br>
      <a href="Screenshots/OriginalVision/mixer.png"><img src="Screenshots/OriginalVision/mixer.png" width="220" alt="Mixer: вертикальные фейдеры Harmony, Drums, Bass и Master"></a>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top" width="33%">
      <strong>Harmony · новый цвет</strong><br><sub>Voicing, стилизация и сравнение A/B</sub><br><br>
      <a href="Screenshots/OriginalVision/harmony.png"><img src="Screenshots/OriginalVision/harmony.png" width="220" alt="Harmony Lab: выбор voice leading, gentle, expressive и reharmonize"></a>
    </td>
    <td align="center" valign="top" width="33%">
      <strong>Notes · своя мелодия</strong><br><sub>Piano roll, перенос и длина нот</sub><br><br>
      <a href="Screenshots/OriginalVision/notes.png"><img src="Screenshots/OriginalVision/notes.png" width="220" alt="Piano roll: редактируемые ноты мелодии на сетке 1/16"></a>
    </td>
    <td align="center" valign="top" width="33%">
      <strong>Assistant · идея словами</strong><br><sub>Локальные Commands и review формы</sub><br><br>
      <a href="Screenshots/OriginalVision/assistant-song-proposal.png"><img src="Screenshots/OriginalVision/assistant-song-proposal.png" width="220" alt="Assistant: локальная команда с темпом, тональностью, Intro и Chorus; модель AI недоступна, Commands работают"></a>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top" width="33%">
      <strong>Voice · напеть идею</strong><br><sub>Монофонический Voice-to-MIDI · beta</sub><br><br>
      <a href="Screenshots/OriginalVision/voice.png"><img src="Screenshots/OriginalVision/voice.png" width="220" alt="Voice-to-MIDI beta: запись одной мелодии в наушниках поверх играющего бита"></a>
    </td>
    <td align="center" valign="top" width="33%">
      <strong>Perform · сыграть трек</strong><br><sub>Секции, круговой фильтр, FX и live take</sub><br><br>
      <a href="Screenshots/OriginalVision/perform-take.png"><img src="Screenshots/OriginalVision/perform-take.png" width="220" alt="Perform: запуск секций, круговой Low/High Pass, delay, repeat и сохранённое исполнение"></a>
    </td>
    <td align="center" valign="top" width="33%">
      <strong>Export · продолжить в DAW</strong><br><sub>MIDI, WAV, stems и переносимый проект</sub><br><br>
      <a href="Screenshots/OriginalVision/export-wav.png"><img src="Screenshots/OriginalVision/export-wav.png" width="220" alt="Export: MIDI, Stereo WAV, aligned stems и portable project; WAV 48 kHz / 24 bit"></a>
    </td>
  </tr>
</table>

[Все 73 оригинальных скриншота](Screenshots/OriginalVision) · [Русский интерфейс](Screenshots/OriginalVision/grid-ru.png) · [Светлая тема](Screenshots/OriginalVision/grid-light.png) · [Компактный iPhone](Screenshots/OriginalVision/compact-grid.png) · [12 кадров для App Store EN/RU](Screenshots/AppStore)

PNG сохранены без изменений; [манифест](Screenshots/OriginalVision/manifest.json) содержит источник, запуск тестов, размеры и SHA-256 каждого кадра. У Assistant на показанном экране работает локальный режим Commands; это не демонстрация генерации реальной моделью.

## Сплеш загрузки · кандидат 17

<p align="center"><a href="Screenshots/LaunchPreview/dark-en.png"><img src="Screenshots/LaunchPreview/dark-en.png" width="210" alt="Тёмный сплеш La Grilla с музыкальной сеткой и курсором"></a> <a href="Screenshots/LaunchPreview/light-en.png"><img src="Screenshots/LaunchPreview/light-en.png" width="210" alt="Светлый сплеш La Grilla"></a> <a href="Screenshots/LaunchPreview/dark-ru-large-reduced-motion.png"><img src="Screenshots/LaunchPreview/dark-ru-large-reduced-motion.png" width="210" alt="Русский сплеш с крупным текстом и уменьшенным движением"></a></p>

Настоящее **QA-превью** того же нативного компонента после bootstrap, source `5adbadb`; PNG без изменений. Все семь focused методов этого исходника прошли. Превью не измеряет холодную загрузку и не подтверждает физическую приёмку. [Исходники кадров и границы проверки](Screenshots/LaunchPreview/README.md).

## Первый запуск и настройки · сборка 15

<table>
  <tr>
    <td align="center" valign="top" width="33%"><strong>Быстрый старт</strong><br><sub>Можно сразу пропустить</sub><br><br><a href="Screenshots/ProfessionalShell/welcome.png"><img src="Screenshots/ProfessionalShell/welcome.png" width="220" alt="Getting started: Grid, Jam, Export, Skip и Start creating"></a></td>
    <td align="center" valign="top" width="33%"><strong>Settings · Light</strong><br><sub>Тема сохраняется при перезапуске</sub><br><br><a href="Screenshots/ProfessionalShell/settings-light.png"><img src="Screenshots/ProfessionalShell/settings-light.png" width="220" alt="Settings: Light выбрана, форма настроек отрисована в светлой теме"></a></td>
    <td align="center" valign="top" width="33%"><strong>Settings · Dark</strong><br><sub>Настройки приложения и проекта</sub><br><br><a href="Screenshots/ProfessionalShell/settings-dark.png"><img src="Screenshots/ProfessionalShell/settings-dark.png" width="220" alt="Settings: Dark выбрана, форма настроек отрисована в тёмной теме"></a></td>
  </tr>
</table>

Оригиналы из iOS Simulator: welcome — source `838b484`, Settings — `014a00b`. [Источники и проверки каждого PNG](Screenshots/ProfessionalShell/README.md) · [20 технических критериев доводки](docs/PRODUCT_FINISHING.md).

## Возможности текущей реализации

| Часть студии | Возможности текущей сборки |
| --- | --- |
| **Аранжировка** | До 8 дорожек, 8 секций и 64 тактов; 4/4, 40–240 BPM. Перенос, копирование и изменение длины клипов, перестановка секций, pinch-to-zoom с сохранением точки под пальцами. |
| **Гармония** | 65 типов аккордов, свои интервальные формулы, обращения и slash chords. Voice leading, усложнение и reharmonize с A/B, Apply и Undo. |
| **Бит и мелодия** | Пэды 4×4, step editor, count-in, квантование, overdub / replace; бас и независимые мелодические дорожки с piano roll. |
| **Живой звук** | Общий транспорт между экранами, циклы и правки во время воспроизведения. Ноты, структура, тембры, микшер и FX принимаются согласованно на музыкальной границе. |
| **Assistant** | Текстовые RU/EN Commands для темпа, тональности, секций, аккордов и формы целой песни. Предложения можно проверить, прослушать, применить или отменить одной операцией. Диктовка использует Apple Speech при наличии локальной языковой модели. |
| **Voice-to-MIDI · beta** | Запись одной мелодической линии поверх бита, сохранение исходного аудио, определение высоты, прослушивание, ручная коррекция нот и ритма, Apply / Undo. Нужны наушники и проверка результата. |
| **DJ Performance** | Квантованный запуск секций, beat jumps, repeat, круговой Low/High Pass и delay. Запись, воспроизведение и экспорт live take. |
| **Микшер и MIDI** | Вертикальные фейдеры, pan, mute / solo, Master и индикаторы. CoreMIDI input / output, выбор каналов, CC Learn, Panic и интерфейс подключения BLE MIDI. |
| **Экспорт и проекты** | MIDI Type 1, WAV mixdown и выровненные stems: 44.1 / 48 kHz, 16 / 24 bit. Переносимый `.grillapack` сохраняет исходные записи. Автосохранение, восстановление, Undo / Redo. |
| **Интерфейс** | Русский и английский, светлая и тёмная темы, Dynamic Type, VoiceOver и Reduce Motion; компактные и горизонтальные экраны. [Дизайн и OpenArt-источники](Design/2026). |
| **Первый запуск и настройки** | Адаптивный системный Launch Screen и брендированная анимация сетки/курсора во время фактической загрузки проекта, без искусственной задержки и процентов. Необязательное знакомство и повторная справка. Последний открытый проект, System / Light / Dark с сохранением, ссылка на системные язык и разрешения, версия, privacy и support. [Исторические welcome/Settings 15](Screenshots/ProfessionalShell) · [Границы новых splash-превью](docs/release/CURRENT.md#splash-и-медиа) · [20 пунктов доводки](docs/PRODUCT_FINISHING.md). |

**On-device AI:** адаптер Apple FoundationModels включается на совместимом устройстве с iOS 26+, Apple Intelligence, готовой моделью и поддерживаемым языком запроса. Для AI отдельно выбирается язык и доступна повторная проверка готовности; настройки Siri конкретного приложения не подтверждают глобальное состояние модели. Локальные RU/EN Commands доступны отдельно. Качество и задержка генерации реальной моделью ещё требуют проверки на устройстве.

Основная студия работает локально, без аккаунта и облачного API. Все инструментальные звуки синтезируются приложением.

## Установить на свой iPhone

Нужны Mac и iPhone с **iOS 18+**. Для полного набора функций и выпуска используйте Xcode **26.3+**. Полная локальная сборка дополнительно проверена на **16.4 / 26.0.1**; [границы совместимости старых SDK](docs/DEVELOPMENT.md#xcode-compatibility).

1. Склонируйте репозиторий или подтяните свежий `main`; откройте [`LaGrilla.xcodeproj`](LaGrilla.xcodeproj).
2. В Xcode добавьте свой Apple ID: **Settings → Accounts**. В app target → **Signing & Capabilities** включите **Automatically manage signing** и выберите свою **Team**.
3. Подключите iPhone по USB, подтвердите **Trust / Доверять** и включите **Developer Mode / Режим разработчика**, если Xcode попросит.
4. Выберите схему **LaGrilla**, свой iPhone и нажмите **Run**.

Бесплатная Personal Team подходит для локального запуска; такую подпись обычно нужно обновлять раз в семь дней через Xcode. Если bundle identifier занят, задайте уникальный для своей локальной сборки. [Подробная инструкция и команды сборки](docs/DEVELOPMENT.md#run-on-your-own-iphone).

Приложение пока не опубликовано в App Store. CI-архив собран без distribution-подписи и не является устанавливаемым IPA.

## Проверки и готовность

Текущий пакет исправлений — **1.0.0 (17), schema 8**, [PR #20](https://github.com/alexgazin/la-grilla/pull/20). **Функциональная альфа: software gate 17 и физический P0-retest открыты.** Единый актуальный source, результаты CI и границы доказанного — в [CURRENT](docs/release/CURRENT.md). На базовом `main` 16 полный программный прогон прошёл; это не подтверждает исправление на телефоне или новые изменения 17. Снимки владельца показывают выданные Mic/Speech-разрешения и ошибку захвата; точные iPhone, iOS и установленный build ещё не записаны.

| Подтверждение | Результат и источник |
| --- | --- |
| Текущий кандидат 17 | Код `5adbadb`, **651 EN/RU ключ**. Debug Xcode 26.3 и полные resource-сборки 16.4 / 26.0.1 PASS. Текущие native/archive/full-regression результаты учитываются отдельно в CURRENT; отмена задания в очереди не является результатом UI-теста. Предыдущие `9fb52e0` — 6 PASS / 1 Speech timeout и `29adf6c` — 5 PASS / 2 UI timeout не выданы за полную приёмку. [Точный текущий статус и ссылки](docs/release/CURRENT.md). |
| Полная проверка main 16 | Точный `9dfec7e`, [run 43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785): все три jobs SUCCESS, **51 functional native PASS / 0 FAIL / 1 opt-in diagnostic SKIP**. Это принятая программная база до изменений 17; аппаратная C8 остаётся открытой. |
| Восстановление после первого отчёта | Source `27cbf09`: [8/8 целевых native PASS, 0 failures, 0 skips](https://github.com/alexgazin/la-grilla/actions/runs/43845748716). Проверены настоящий отказ Speech-разрешению без вылета и typed Apply/Undo, output-only граф, strict PCM/CAF, проекты при явно внедрённой аудио-ошибке и Commands при недоступной модели. [Пять новых оригинальных скриншотов](Screenshots/DeviceRepair). Физический iPhone этим не проверен. |
| Историческая ветка 16 до merge | Source `01fb8b7`, **634 EN/RU ключа**. [iPhone Debug / Release archive](https://github.com/alexgazin/la-grilla/actions/runs/43851740287) прошли; [полные сборки Xcode 16.4 / 26.0.1](https://github.com/alexgazin/la-grilla/actions/runs/43851747604) прошли. [10 focused native](https://github.com/alexgazin/la-grilla/actions/runs/43851740283) отменён по лимиту workflow 35 минут; логи и артефакты недоступны, исходы отдельных методов неизвестны. Полный native-прогон завершился **49 PASS / 2 FAIL / 1 diagnostic SKIP**: все шесть Arrangement и пять DeviceRecovery прошли; не прошли AssistantComposition idle и Light theme. Это исторический результат до последующего успешного exact-main `9dfec7e`; физическая перепроверка остаётся открытой. |
| Последующие проверки `main` 224e248 | [Native run 43836782494](https://github.com/alexgazin/la-grilla/actions/runs/43836782494) — FAILURE двух Arrangement cases при прошедших iPhone/archive; [compatibility 43836782541](https://github.com/alexgazin/la-grilla/actions/runs/43836782541) — инфраструктурный FAILURE 16.2, полные app на 16.4 / 26.0.1 прошли. Эти результаты сохраняются в [журнале](docs/IMPLEMENTATION_LOG.md) и не заменены проверками кандидата 16. |
| Полная программная приёмка | [Run 43771988471](https://github.com/alexgazin/la-grilla/actions/runs/43771988471), исходники `77fb72ab82cd800eb8131136628c416ad83c9046`: **118 Swift tests / 19 suites**, **15 C++ suites**, **44/44 функциональных native-сценария** и **3/3 метода захвата**. Один отдельный opt-in diagnostic пропущен намеренно. |
| Интеграция в `main` | [Run 43777618996](https://github.com/alexgazin/la-grilla/actions/runs/43777618996) для merge commit `8e5b1f7`: все три CI jobs и **44/44 функциональных native-сценария** прошли; повторный массовый захват кадров не запускался. Актуальные проверки ветки — в badge наверху. |
| Дополнительная совместимость | [Run 43777646531](https://github.com/alexgazin/la-grilla/actions/runs/43777646531): неизменные исходники приложения `77fb72a`, **iOS 18.5 Simulator**, **3/3 сценария** — whole-song Commands Apply / Undo, custom chord save / Undo, переходы между экранами при воспроизведении. Это отдельная ограниченная проверка, не полный прогон и не физический iPhone. |
| Визуальная приёмка | 73 индивидуально просмотренных оригинала; 12 Store-копий EN/RU и четыре корневых превью сохраняют исходные байты. 603 локализованных ключа EN/RU. [Сводка и ограничения C7](docs/release/C7_ACCEPTANCE.md). |
| Доводка сборки 15 | [Run 43812214574](https://github.com/alexgazin/la-grilla/actions/runs/43812214574), source `838b484`: все три jobs, **46 функциональных native-сценариев**, 118 Swift / 19 suites, 15 C++ suites и **623 EN/RU ключа** прошли. Один отдельный diagnostic пропущен; массовый захват кадров не запускался. |
| Видимые темы и первый запуск | После локальной правки темы открытой формы [run 43819149979](https://github.com/alexgazin/la-grilla/actions/runs/43819149979), source `014a00b`: **2/2 native-сценария** с проверкой отрисованных пикселей Light / Dark, сохранения темы, Skip / relaunch / Help. Три оригинала сохранены в [ProfessionalShell](Screenshots/ProfessionalShell). Это focused-проверка, а не повтор всех 46 сценариев. |
| Локальная сборка и закрытие Assistant | Source `4d5ff47`: [iPhone SDK / Release archive](https://github.com/alexgazin/la-grilla/actions/runs/43829522207) прошли; [6/6 focused native](https://github.com/alexgazin/la-grilla/actions/runs/43829522128) подтвердили Cancel после смены режима/языка, Apply/Undo, темы и знакомство. Предыдущий точный run `aa91404` имел один сбой закрытия Assistant; он сохранён в [журнале](docs/IMPLEMENTATION_LOG.md). Новый результат относится к исправлению, а не полному повтору 46 функций. Для собственного iPhone достаточно бесплатной [Personal Team](docs/DEVELOPMENT.md#run-on-your-own-iphone). |
| Полная регрессия после исправления Assistant | [Run 43832035629](https://github.com/alexgazin/la-grilla/actions/runs/43832035629), точный `main` source `778885b`: все три jobs SUCCESS, **46 функциональных native PASS / 1 diagnostic SKIP / 0 failures**. Это источник до последующей правки компиляции `ChordTile`; его результаты не подменяют [отдельную матрицу Xcode](docs/DEVELOPMENT.md#xcode-compatibility). |

**До выпуска нужно закрыть software gate кандидата 17 и C8:** повторная установка кандидата исправлений и приёмка на физических iPhone, включая минимальную ОС; 30-минутные проверки задержки, нагрева и непрерывности звука; speaker / wired / USB / Bluetooth-маршруты; настоящие USB/BLE MIDI-контроллеры и импорт в две DAW; живой напев и реальная FoundationModels; distribution signing, TestFlight и App Review. Первый пользовательский запуск выявил дефекты и не закрывает эти пункты. [Чек-лист устройства](docs/release/DEVICE_ACCEPTANCE.md) и [процедура выпуска](docs/release/RELEASE.md).

Voice-to-MIDI остаётся монофонической beta с ручной проверкой. В аудио-QA зафиксированы разрывы временных меток рендера; отсутствие слышимых выпадений на телефоне ещё не измерено. Границы подтверждённых результатов подробно сохранены в [приёмке C7](docs/release/C7_ACCEPTANCE.md).

## Документация и дальнейшая работа

[Текущий кандидат и четыре независимых аудита](docs/release/CURRENT.md) · [Продуктовый роадмап и конкуренты](ROADMAP.md) · [Подробный технический план этапов 0–5](docs/STABILIZATION_PLAN.md) · [Новые скриншоты сборки 16](Screenshots/DeviceRepair).

README описывает текущую сборку и обновляется вместе с проверенными этапами. Первоначальные формулировки «после MVP» сохранены отдельно, чтобы история требований не смешивалась с фактическими возможностями.

- [ROADMAP](ROADMAP.md) — выполненные этапы и оставшаяся работа до App Store.
- [План C0–C8](docs/ORIGINAL_VISION_COMPLETION.md) — подробные задачи, технические контракты и критерии приёмки.
- [Журнал реализации](docs/IMPLEMENTATION_LOG.md) — исправления, проверки и ссылки на результаты.
- [Development](docs/DEVELOPMENT.md) — архитектура, структура репозитория, сборка и установка.
- [Принятая QA](docs/release/C7_ACCEPTANCE.md) · [Release QA](docs/RELEASE_QA.md) · [Физическая приёмка](docs/release/DEVICE_ACCEPTANCE.md).
- [Исходная продуктовая спецификация](docs/PRODUCT_SPECIFICATION.md) — все 25 первоначальных разделов, backlog и источники.
- [Дизайн-бриф](DESIGN_PROMPT.txt) · [Текущий дизайн](Design/2026/README.md) · [Privacy RU](docs/privacy/ru.md) / [EN](docs/privacy/en.md) · [Support](docs/release/SUPPORT.md).
