<p align="center">
  <img src="Design/2026/openart-icon.png" width="88" alt="Иконка La Grilla — музыкальная сетка и курсор">
</p>

<h1 align="center">La Grilla</h1>

<p align="center"><strong>Идея → грув → трек.</strong><br>Карманная студия для iPhone: сочиняйте гармонию, играйте бит, собирайте аранжировку и продолжайте работу в своей DAW.</p>

<p align="center">
  <a href="https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml?query=branch%3Amain"><img src="https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml/badge.svg?branch=main" alt="Проверки iOS на main"></a><br>
  iOS 18+ · SwiftUI · нативный звук · RU / EN · без аккаунта
</p>

<p align="center"><a href="#экраны-сборки-23">Экраны</a> · <a href="#возможности-сборки-23">Возможности</a> · <a href="#попробовать-на-iphone">На iPhone</a> · <a href="docs/release/CURRENT.md">Текущий статус</a> · <a href="ROADMAP.md">Роадмап</a></p>


**Nocturne 24 — предыдущая тестовая сборка.** Пять реальных ночных экранов сохранены в [Design26](Screenshots/Design26/README.md); их общий сценарий прошёл за 103.043 с. Нативный focused-прогон исходника 207fc2b: 9 PASS, Light превысил120 с на заключительных проверках, PadContact оборвался при запуске до UI. Gate не принят. Повторные запросы геометрии и неиспользуемые снимки в новом тесте удалены; все проверки и лимиты сохранены. Следующий полный inventory 75 — Pending.

## Форма песни и SoundFont в сборке 27

«Форма песни» над сеткой показывает всю композицию. Перемещайте карточки за ручку, добавляйте секции нужной длины, дублируйте и удаляйте их. Assistant показывает исходную и предложенную форму перед применением. В меню «Звук» можно загрузить `.sf2` из «Файлов» и послушать программы банка.

<table><tr><td><a href="Screenshots/SongForm27/song-form.png"><img src="Screenshots/SongForm27/song-form.png" width="220" alt="Монтажная лента после перестановки бриджа"></a></td><td><a href="Screenshots/SongForm27/assistant-form.png"><img src="Screenshots/SongForm27/assistant-form.png" width="220" alt="Исходная и предложенная форма песни в Assistant"></a></td></tr></table>

[Оригиналы и нативная проверка](Screenshots/SongForm27/README.md) · [Применение и этапы звука](docs/SONG_FORM_AND_SOUND_BANKS.md)

## Nocturne 24 — новые экраны

Реальные экраны Night: пять PNG, owner PASS 103.043 с. Весь focused-прогон: 9 PASS / 2 FAIL; Light и запуск одного теста пэдов ещё не приняты. [Оригиналы и источник](Screenshots/Design26/README.md). Общий gate 75 и устройство остаются отдельной проверкой.

<table><tr><td><a href="Screenshots/Design26/night-grid.png"><img src="Screenshots/Design26/night-grid.png" width="180" alt="Nocturne 24 grid"></a></td><td><a href="Screenshots/Design26/night-jam.png"><img src="Screenshots/Design26/night-jam.png" width="180" alt="Nocturne 24 jam"></a></td><td><a href="Screenshots/Design26/night-mixer.png"><img src="Screenshots/Design26/night-mixer.png" width="180" alt="Nocturne 24 mixer"></a></td></tr><tr><td><a href="Screenshots/Design26/night-piano.png"><img src="Screenshots/Design26/night-piano.png" width="180" alt="Nocturne 24 piano"></a></td><td><a href="Screenshots/Design26/night-sound.png"><img src="Screenshots/Design26/night-sound.png" width="180" alt="Nocturne 24 sound"></a></td></tr></table>

[Диагностические кадры Light](Screenshots/Design26/Diagnostics/light-grid.png) · [IPA 24](https://github.com/alexgazin/la-grilla/actions/runs/44173635688/artifacts/14368802814)

**Предыдущая сборка 23 — тестовая альфа.** Последний полный прогон exact main `e22f487`: **70 PASS / 3 FAIL / 0 case allowance**, все 73 метода наблюдались, общего timeout нет. Четыре SDK-сборки прошли. Полная software-приёмка пока не пройдена; исторические результаты не суммируются.

**[Архив IPA 23 · exact main e22f487](https://github.com/alexgazin/la-grilla/actions/runs/44156364284/artifacts/14361297972)** · [Установка](Builds/Testing/README.md) · [Роадмап](ROADMAP.md)

Сочиняйте аккорды, записывайте бит и добавляйте мелодию в одну сетку. Сохраните редактируемый проект или заберите MIDI/WAV для продолжения работы в DAW.

## Экраны сборки 23

Ночная тема на iPhone 16 Pro Max Simulator. Perform показан с крупным системным текстом; нажмите на кадр, чтобы открыть оригинальный PNG.

<table><tr>
<td align="center"><strong>Фильтр и доступный Reset</strong><br><br><a href="Screenshots/Build23Layout/perform-large-type.png"><img src="Screenshots/Build23Layout/perform-large-type.png" width="220" alt="Perform23: крупный текст, регулятор и Reset под ним, закреплённый транспорт"></a></td>
<td align="center"><strong>Секции и транспорт</strong><br><br><a href="Screenshots/Build23Layout/perform-sections-large-type.png"><img src="Screenshots/Build23Layout/perform-sections-large-type.png" width="220" alt="Perform23: доступные секции Verse и Chorus при крупном тексте"></a></td>
<td align="center"><strong>Review транспонирования</strong><br><br><a href="Screenshots/Build23Layout/transpose-preview.png"><img src="Screenshots/Build23Layout/transpose-preview.png" width="220" alt="Transpose23: +2 полутона, изменения диапазона и тональности, Apply"></a></td>
</tr></table>

Эти три кадра сохраняют source `8f7cd0e`: методы-владельцы прошли, весь тот targeted-запуск — 4 PASS / 1 allowance. [Неизменённые оригиналы и происхождение](Screenshots/Build23Layout/README.md).

**Ступени и бемоли после перезапуска · прежний main 0cfd12e**

<a href="Screenshots/Build23Main/flats-degrees-reopened.png"><img src="Screenshots/Build23Main/flats-degrees-reopened.png" width="220" alt="Main23: сохранённый B♭ и ступень IV после перезапуска проекта, закреплённые Preview и Apply"></a>

Оригинальный кадр `0cfd12e` принадлежит прошедшему Flats/scale-degrees методу. Весь main-run: 70 PASS / 2 FAIL / 1 allowance; один прошедший кадр не принимает весь релиз. [PNG, source/run и SHA-256](Screenshots/Build23Main/README.md).

**Помощник после исправлений · исходный кадр candidate 7564**

<a href="Screenshots/Build23Assistant/assistant-dictation-controls.png"><img src="Screenshots/Build23Assistant/assistant-dictation-controls.png" width="220" alt="Помощник23: отдельные действия начала и остановки диктовки и независимые языки"></a>

Неизменённый оригинал `7564fe7`, owner AI setup PASS; весь focused4 — **4 PASS / 0 allowance**, не полный73 и не генерация реальной моделью. На кадре показаны реальные элементы управления и исходная языковая подсказка. [Source/run и provenance](Screenshots/Build23Assistant/README.md).

**Пэды после contact/hold · main `8bc7866`**

<a href="Screenshots/Build23Pads/pads-contact.png"><img src="Screenshots/Build23Pads/pads-contact.png" width="220" alt="Jam23: оригинальный кадр прошедшего Pad contact/hold метода main8bc7866"></a>

Неизменённый оригинал source `8bc7866`: Pad-owner **PASS13.483s**, предшествующий LiveEditing полностью **PASS83.255s**, включая Stop/hold/timing/counter. Весь full73 остаётся **71 PASS / 2 FAIL / общий timeout**, без полной приёмки. [PNG, owner и provenance](Screenshots/Build23Pads/README.md).

## Возможности сборки 23

| Часть студии | Текущая реализация |
| --- | --- |
| **Grid и редакторы** | До 8 дорожек, 8 секций и 64 тактов. Перенос, копирование, изменение длины, pinch-to-zoom, piano roll, Undo/Redo. |
| **Гармония** | 65 типов аккордов, свои интервальные формулы и voicing. A/B, стилизация, slash chords, буквенная запись, ступени и транспонирование. |
| **Локальный SketchComposer** | Скетч из аккордов, ударных, баса и мелодии по стилю и seed. Проверка, прослушивание, Apply одной операцией и дальнейшее редактирование. |
| **Jam и Perform** | Multi-touch пэды 4×4, шаги, квантование записи, overdub; запуск секций, фильтр/delay/repeat, запись и replay. Наклон для фильтра или Master включается вручную. |
| **Помощник и голос** | RU/EN Commands; необязательный адаптер FoundationModels для музыкальных запросов на совместимом устройстве. Диктовка отдельно от монофонического Voice-to-MIDI beta с сохранением исходника и ручной коррекцией. |
| **Микшер и MIDI** | Вертикальные фейдеры, pan, mute/solo, Master и выбор встроенного тембра; CoreMIDI input/output, CC Learn, Panic и интерфейс BLE MIDI. |
| **Проекты и экспорт** | Автосохранение, восстановление и переносимый `.grillapack`; MIDI Type 1, WAV mixdown и выровненные stems, 44.1/48 kHz, 16/24 bit. |
| **Интерфейс** | RU/EN, Light/Dark/System, Dynamic Type и VoiceOver. Статичный Launch Screen и анимация реальной загрузки без искусственной задержки. |

Локальные Commands и SketchComposer работают без Apple Intelligence. Скетчи создаёт локальный музыкальный алгоритм; показанные кадры не демонстрируют генерацию реальной моделью. Доступность FoundationModels зависит от устройства, iOS 26+, готовности Apple Intelligence и языка запроса. Языки AI и диктовки выбираются независимо.

## Удобство работы руками

- **Пэды:** звук запускается при начале контакта; два пальца работают независимо. Квантование привязывает запись к сетке.
- **Ноты:** длина меняется прямо во время жеста; линия конца и подсказка помогают видеть результат над пальцем. Завершённый жест — одна операция Undo.
- **Звуки:** кнопка «Звук» в Jam и Mixer открывает встроенные Classic/Warm/Bright с прослушиванием перед Apply.
- **Исполнение:** Replay и Reset доступны возле транспорта и фильтра, секции остаются под рукой при крупном тексте и в landscape. Наклоном можно управлять фильтром или громкостью микса проекта после ручного включения и калибровки.
- **Редактирование:** полные настройки открываются из меню проекта, Preview/Apply аккорда закреплены у нижней границы редактора.
- **Помощник:** у диктовки раздельные Start/Stop; поздний Stop после естественного окончания не начинает новую запись.

Эти изменения реализованы в приложении. Точную задержку и удобство на реальном iPhone ещё предстоит измерить.

## Попробовать на iPhone

**[Скачать La Grilla 1.0.0 (27)](https://github.com/alexgazin/la-grilla/actions/runs/44248325062/artifacts/14403425905)**. Из ZIP извлеките `LaGrilla-unsigned.ipa` и подпишите своим Apple ID через Sideloadly. Бесплатная Personal Team подходит. [Установка и проверка пакета](Builds/Testing/README.md).

Перед обновлением экспортируйте важные проекты в portable bundle. Сборка 27 читает схемы **1…11** и сохраняет **schema 11**; старые приложения не открывают сохранённую schema 11.

## Следующие шаги

Закончить нативную проверку Nocturne 24: Night/Light, пэды и их onset, перемещение/длина нот и Undo, прослушивание/сохранение тембров, крупный текст и landscape. Затем сохранить реальные PNG с source/run, собрать новую IPA и пройти общий функциональный gate. [Подробный дизайн-контракт](DESIGN.md).

В исходнике `e22f487` пройдены 70 из 73 методов; остаются два Arrangement-сценария и выявленная гонка подготовки MIDI-теста. Для MIDI исправляется ожидание подтверждения seek до Play, без изменения проверок и production-аудио. Реальные аудиомаршруты, Voice-to-MIDI с человеком, FoundationModels на телефоне, MIDI-контроллеры и C8 остаются отдельной приёмкой перед beta/TestFlight/App Store.

[Точный статус, ограничения и история failures](docs/release/CURRENT.md) · [Протокол устройства](docs/release/DEVICE_ACCEPTANCE.md) · [Роадмап](ROADMAP.md) · [План аудита](docs/review/2026-11-16/PLAN.md).

Новое видео отменено по просьбе владельца. Исторические записи и кадры ниже сохраняют свои версии и источники.

<details>
<summary>Исходные экраны доработок 22: пэды, ноты и звук</summary>

## Исходные доработки сборки 22

Оригинальные кадры работающего **iPhone 16 Pro Max Simulator**, ночная тема. Нажмите, чтобы открыть полный PNG.

<table>
  <tr>
    <td align="center" valign="top"><strong>Пэды и доступный выбор звука</strong><br><br><a href="Screenshots/Build22Touch/pads.png"><img src="Screenshots/Build22Touch/pads.png" width="220" alt="Jam22: шестнадцать пэдов, видимая кнопка Звук и доли"></a></td>
    <td align="center" valign="top"><strong>Изменённая длина ноты</strong><br><br><a href="Screenshots/Build22Touch/piano-resized-note.png"><img src="Screenshots/Build22Touch/piano-resized-note.png" width="220" alt="Piano roll22: нота после растягивания до1440ticks и большая рукоятка конца"></a></td>
    <td align="center" valign="top"><strong>Прослушивание тембра</strong><br><br><a href="Screenshots/Build22Touch/sound-warm-preview.png"><img src="Screenshots/Build22Touch/sound-warm-preview.png" width="220" alt="Выбор звука22: Classic,Warm,Bright и реальное прослушивание Warm kit"></a></td>
  </tr>
</table>

Все выбранные PNG принадлежат прошедшим методам. Четыре кадра имеют source `60c24ce` (9 PASS / 1 ошибка ожидания форматирования), нотный кадр — `aded2ff` (1 PASS, resize и оба Undo). Product-код между этими исходниками и исходным `main` 22 совпадает. Это раздельные focused-проверки, не новый полный прогон 10 или 73 сценариев. [Пять оригиналов, source/run и контрольные суммы](Screenshots/Build22Touch/README.md).

</details>

<details>
<summary>Историческое видео работы · сборка 15</summary>

## Настоящее видео работы · сборка 15

[![La Grilla: реальные нажатия, жесты и звук приложения, сборка 15](Media/WorkingDemo/teaser.gif)](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)

**[▶ Смотреть запись — 2:12, Full HD, со звуком](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)** · [Полная исходная запись](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-session-original.mp4)

Историческая запись **iOS Simulator, 1.0.0 (15)**: Play, аккорды, жесты, пэды, overdub, микшер, Harmony A/B, Commands, Perform и WAV share. Звук снят с выхода тех же сессий; три сессии смонтированы с сокращением ожиданий, действия идут в обычном темпе. Voice показан на подготовке записи. [Источники, монтаж и проверки](Media/WorkingDemo/README.md) сохраняют исходный результат capture-workflow и границы принятой записи.

По просьбе владельца новое видео отменено. Историческое видео 15 сохранено со своим source и результатом; оно не представляет сборку 23.

</details>

<details>
<summary>Исторические оригиналы сборок 19 и 20</summary>

## Оригинальные экраны кандидата 20

Два оригинальных кадра работающей сборки 20: Harmony A/B и фильтр Perform. Эти экраны сняты с кандидата `deeb701` в iOS Simulator.

<p align="center">
  <a href="Screenshots/Build20Preview/harmony.png"><img src="Screenshots/Build20Preview/harmony.png" width="240" alt="Harmony Lab сборки 20: аккорды и прослушивание варианта B"></a>
  <a href="Screenshots/Build20Preview/perform.png"><img src="Screenshots/Build20Preview/perform.png" width="240" alt="Perform сборки 20: круговой фильтр и управление живым исполнением"></a>
</p>

Методы-владельцы обоих кадров прошли; [весь запуск](https://github.com/alexgazin/la-grilla/actions/runs/43966102437) завершился с **2 PASS / 1 allowance / 1 interrupted**. Это предпросмотр интерфейса, не полная приёмка и не готовый проморолик. Исходные пиксели сохранены без изменений; [происхождение, имена вложений и SHA-256](Screenshots/Build20Preview/manifest.json).


### Предыдущие оригиналы сборки 19

Шесть оригинальных кадров сборки19 на работающем **iPhone 16 Pro Max Simulator**; сборка20 сохраняет этот интерфейс и исправляет импортированный диапазон воспроизведения. Нажмите на экран, чтобы открыть полный PNG.

<table>
  <tr>
    <td align="center" valign="top"><strong>Скетч перед применением</strong><br><sub>Стиль, гармония и партии · A/B</sub><br><br><a href="Screenshots/AuditImprovements/01-local-sketch-review.png"><img src="Screenshots/AuditImprovements/01-local-sketch-review.png" width="210" alt="Проверка локального House-скетча: аккорды, ударные, бас и мелодия с A/B и Apply"></a></td>
    <td align="center" valign="top"><strong>Развить идею в сетке</strong><br><sub>Редактируемая аранжировка на 8 тактов</sub><br><br><a href="Screenshots/AuditImprovements/02-local-sketch-applied.png"><img src="Screenshots/AuditImprovements/02-local-sketch-applied.png" width="210" alt="Применённый скетч с четырьмя музыкальными партиями в мультитрековой сетке"></a></td>
    <td align="center" valign="top"><strong>Забрать MIDI</strong><br><sub>Настоящее системное меню экспорта</sub><br><br><a href="Screenshots/AuditImprovements/03-generated-sketch-midi-share.png"><img src="Screenshots/AuditImprovements/03-generated-sketch-midi-share.png" width="210" alt="Системное меню iOS с экспортированным MIDI после сохранения и открытия проекта"></a></td>
  </tr>
  <tr>
    <td align="center" valign="top"><strong>Сохранить нотацию</strong><br><sub>D♭maj7/F♯ после перезапуска</sub><br><br><a href="Screenshots/AuditImprovements/04-chord-writing-after-reopen.png"><img src="Screenshots/AuditImprovements/04-chord-writing-after-reopen.png" width="210" alt="Редактор аккорда с сохранённой записью D-flat major seventh over F-sharp"></a></td>
    <td align="center" valign="top"><strong>Свои формулы аккордов</strong><br><sub>Все тоны остаются в редакторе</sub><br><br><a href="Screenshots/AuditImprovements/05-custom-harmony-notes.png"><img src="Screenshots/AuditImprovements/05-custom-harmony-notes.png" width="210" alt="Пользовательская формула 0, 3, 7, 11, 14 и пять нот аккорда"></a></td>
    <td align="center" valign="top"><strong>Идея своими словами</strong><br><sub>Commands и понятная доступность AI</sub><br><br><a href="Screenshots/AuditImprovements/06-assistant-composer.png"><img src="Screenshots/AuditImprovements/06-assistant-composer.png" width="210" alt="Помощник с независимым языком диктовки и объяснением недоступности модели"></a></td>
  </tr>
</table>

Кадры — **source `f005854`, сборка 19, schema 10**, [run 43890521487](https://github.com/alexgazin/la-grilla/actions/runs/43890521487): **13 PASS / 2 assertion FAIL / 0 timeout**. Все шесть выбранных PNG относятся к прошедшим методам; весь прогон не принят, два падения транспонирования сохранены в отчёте. Оригинальные пиксели не изменены. [Происхождение и пределы каждого кадра](Screenshots/AuditImprovements/README.md) · [Манифест и SHA-256](Screenshots/AuditImprovements/manifest.json).

</details>

<details>
<summary>Исторические экраны, дизайн и промо</summary>

- [Предпросмотр и живое транспонирование сборки19](Screenshots/Transposition19) с собственным PASS-методом и раскрытым итогом всего запуска.
- [73 оригинальных экрана сборки 14](Screenshots/OriginalVision), [EN/RU Store-копии](Screenshots/AppStore).
- [Welcome и Settings сборки 15](Screenshots/ProfessionalShell), [дизайн и OpenArt-происхождение](Design/2026).
- [QA-превью splash сборки 17](Screenshots/LaunchPreview), [разрешённый input и Assistant 17](Screenshots/AuthorizedInput), [восстановление после ошибок сборки 16](Screenshots/DeviceRepair).
- [Историческое промо из скриншотов с отдельным offline-саундтреком](Media/Promo/README.md).

У каждой коллекции собственные source, run и хеши. Splash-превью показывает тот же компонент при явно удержанном QA-представлении и не измеряет время холодного запуска. Исторические медиа не переименовываются в доказательства текущей сборки 23.

</details>
