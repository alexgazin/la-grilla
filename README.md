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

**La Grilla 1.0.0 (23), schema 11 — функциональная альфа.** Main интегрирует продуктовый код `c9b2623` и обновлённые проверки. Четыре SDK/archive/compatibility jobs исходного `c9b2623` прошли, его предварительная IPA статически проверена. Последний focused3 завершился **0 PASS / 1 assertion FAIL / 2 allowance**; свежая полная проверка main (73 метода) и новый main-архив — **Pending**, приёмка не объявлена. [Статус и установка](Builds/Testing/README.md) · [Фактические результаты](docs/release/CURRENT.md).

## Что исправлено в 23

- **Perform:** Replay и статус закреплены рядом с транспортом; Reset находится под фильтром. Крупный текст не прячет эти действия, а landscape использует компактную панель.
- **Навигация:** случайный жест вниз не закрывает идущее исполнение; Done и возврат к редактированию доступны явно. Tilt сворачивается отдельно и выключается при закрытии.
- **Проект:** полные настройки доступны во время воспроизведения; компактный выбор темпа/тональности сохранён отдельно.
- **Аккорды и нотация:** Preview/Apply закреплены у нижней границы редактора. На `c9b2623` центральное касание переключателя уже изменило нотацию, и Flats дошёл до Apply и повторного открытия сохранённого проекта. Два длинных сценария всё ещё достигли своих исходных 120s, поэтому завершённая приёмка остаётся открытой.

## Экраны сборки 23

Оригинальные **iPhone 16 Pro Max Simulator PNG**, ночная тема; Perform показан с крупным системным текстом.

<table><tr>
<td align="center"><strong>Фильтр и доступный Reset</strong><br><br><a href="Screenshots/Build23Layout/perform-large-type.png"><img src="Screenshots/Build23Layout/perform-large-type.png" width="220" alt="Perform23: крупный текст, регулятор и Reset под ним, закреплённый транспорт"></a></td>
<td align="center"><strong>Секции и транспорт</strong><br><br><a href="Screenshots/Build23Layout/perform-sections-large-type.png"><img src="Screenshots/Build23Layout/perform-sections-large-type.png" width="220" alt="Perform23: доступные секции Verse и Chorus при крупном тексте"></a></td>
<td align="center"><strong>Review транспонирования</strong><br><br><a href="Screenshots/Build23Layout/transpose-preview.png"><img src="Screenshots/Build23Layout/transpose-preview.png" width="220" alt="Transpose23: +2 полутона, изменения диапазона и тональности, Apply"></a></td>
</tr></table>

Кадры имеют source `8f7cd0e`, run `44059775230`; их методы прошли. **Весь targeted-запуск: 4 PASS / 1 allowance**, exit 65; это не полная приёмка. Кадры сохраняют свой источник и не подтверждают последующие изменения `c9b2623` или завершённый Flats-сценарий. [Оригиналы и provenance](Screenshots/Build23Layout/README.md).

## Что изменилось в 22

- **Пэды:** звук запускается при начале контакта. Пальцы независимы; удержание и скольжение не добавляют случайных ударов. Квантование меняет записанный ритм, а не откладывает живой удар.
- **Ноты:** длина и положение видны во время движения; конец отмечен линией и подсказкой выше пальца. Рукоятка 44×44 pt, привязка к сетке и одно Undo на завершённый жест.
- **Звуки:** кнопка «Звук» в Jam и Mixer открывает встроенные Classic/Warm/Bright с прослушиванием. Apply сохраняет выбранный тембр одной операцией Undo.
- **Наклон:** в Perform можно вручную включить управление фильтром или общей громкостью проекта и запомнить нейтральное положение. Настоящие датчики и удобство на iPhone ещё требуют проверки.

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

## Попробовать на iPhone

**Предварительная IPA 23 / `c9b2623` статически проверена и остаётся на hold.** [Оригинальный ZIP](https://github.com/alexgazin/la-grilla/actions/runs/44077041006/artifacts/14325104339) содержит `LaGrilla-unsigned.ipa` — **3 691 269 байт**, SHA-256 `f73de389392d9680c3263f2825c61e98feb07f11a17cb7895494941a8950a5e5`. Это unsigned preview исходного `c9b2623`, требующий своей подписи; он не является новым main-архивом или принятой сборкой. Свежая IPA точного main — **Pending**. [Статус, установка и исторические IPA](Builds/Testing/README.md).

Для локальной сборки нужны Mac, iPhone с iOS 18+ и Xcode, поддерживающий установленную на телефоне iOS; рекомендуется актуальный Xcode 26.x. Открыть `LaGrilla.xcodeproj` из `main` (23/schema 11), выбрать свою Personal Team в Signing & Capabilities, подключить телефон и нажать Run. Полные приложения продуктового source `c9b2623` прошли compiler-compatibility на Xcode 16.4 и 26.0.1; это не гарантия поддержки этими версиями новой iOS телефона и не результат свежего main73. Native-приёмка пока открыта. Требование release-архива Xcode 26 / iOS 26 SDK сохраняется.

Перед обновлением экспортируйте важные проекты в portable bundle. Сборка 23 читает схемы 1…11 и сохраняет **schema 11**; старые приложения не открывают сохранённую schema 11. Полная exact-source и аппаратная приёмка открыты. [Результаты и ограничения](docs/release/CURRENT.md).

## Настоящее видео работы · сборка 15

[![La Grilla: реальные нажатия, жесты и звук приложения, сборка 15](Media/WorkingDemo/teaser.gif)](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)

**[▶ Смотреть запись — 2:12, Full HD, со звуком](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)** · [Полная исходная запись](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-session-original.mp4)

Историческая запись **iOS Simulator, 1.0.0 (15)**: Play, аккорды, жесты, пэды, overdub, микшер, Harmony A/B, Commands, Perform и WAV share. Звук снят с выхода тех же сессий; три сессии смонтированы с сокращением ожиданий, действия идут в обычном темпе. Voice показан на подготовке записи. [Источники, монтаж и проверки](Media/WorkingDemo/README.md) сохраняют исходный результат capture-workflow и границы принятой записи.

По просьбе владельца новое видео отменено. Историческое видео 15 сохранено со своим source и результатом; оно не представляет сборку 23.

## Готовность и дальнейшая работа

Полный main `807c735` (22) исполнил все 73 метода: **68 PASS / 4 assertion FAIL / 1 allowance**. Последующие `e2ec475` и `5760902` дали transpose **PASS, 118.102s / PASS, 115.086s**, Flats **FAIL, 81.171s / FAIL, 111.366s**, в обоих **0 allowance**. На `66effd2` transpose прошёл за 100.510s, Flats завершился FAIL за 90.890s, а Bass→Melody не завершился успешно. Последний `c9b2623` focused3: **0 PASS / 1 assertion FAIL / 2 исходных 120s allowance**, exit 65, без wrapper timeout. Центральное касание нотации уже сработало; Bass был визуально восстановлен, но тестовое наблюдение не подтвердилось в своём окне: FAIL, 104.540s, без allowance. Предыдущие failures сохраняются; следующий обязательный результат — полный73 и SDK/archive на свежем точном main, без ещё одного дублирующего focused3.

Следующие шаги — завершить одну свежую полную проверку main (73 метода) и новый main-архив, затем повторить на установленной23 плотный ритм, два пальца, изменение нот возле краёв и наклон. Физическая задержка, speaker/wired/USB/Bluetooth, голос/Apple Intelligence, USB/BLE MIDI, две DAW и 30-минутные сессии остаются открытыми. Приложение пока не опубликовано в App Store; signing для distribution, TestFlight и App Review впереди.

[Текущие доказательства](docs/release/CURRENT.md) · [Изменения контакта и звука](docs/review/2026-11-17/TOUCH21.md) · [Роадмап](ROADMAP.md) · [34 замечания аудита](docs/review/2026-11-16/PLAN.md) · [Журнал разработки](docs/IMPLEMENTATION_LOG.md).

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
