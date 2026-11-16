<p align="center">
  <img src="Design/2026/openart-icon.png" width="88" alt="Иконка La Grilla — музыкальная сетка и курсор">
</p>

<h1 align="center">La Grilla</h1>

<p align="center"><strong>Идея → грув → трек.</strong><br>Карманная студия для iPhone: сочиняйте гармонию, играйте бит, собирайте аранжировку и продолжайте работу в своей DAW.</p>

<p align="center">
  <a href="https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml?query=branch%3Amain"><img src="https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml/badge.svg?branch=main" alt="Проверки iOS на main"></a><br>
  iOS 18+ · SwiftUI · нативный звук · RU / EN · без аккаунта
</p>

<p align="center"><a href="#кандидат-19-в-работе">Экраны</a> · <a href="#возможности-кандидата-19">Возможности</a> · <a href="#попробовать-на-iphone">На iPhone</a> · <a href="docs/release/CURRENT.md">Текущий статус</a> · <a href="ROADMAP.md">Роадмап</a></p>

**Статус — функциональная альфа.** Кандидат **1.0.0 (19), schema 10** добавляет редактируемые локальные скетчи, нотацию, транспонирование и доработку первого музыкального результата. **[Скачать тестовую IPA 19](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Builds/Testing/LaGrilla-1.0.0-19-unsigned.ipa)** — свежая native-приёмка остаётся открытой. Исходники 19 находятся в [PR #21](https://github.com/alexgazin/la-grilla/pull/21); основной код `main` пока остаётся 17. Точные версии, CI и ограничения собраны в [CURRENT](docs/release/CURRENT.md).

## Кандидат 19 в работе

Шесть оригинальных кадров работающего **iPhone 16 Pro Max Simulator**. Нажмите на экран, чтобы открыть полный PNG.

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

## Возможности кандидата 19

| Часть студии | Текущая реализация |
| --- | --- |
| **Grid и редакторы** | До 8 дорожек, 8 секций и 64 тактов. Перенос, копирование, изменение длины, pinch-to-zoom, piano roll, Undo/Redo. |
| **Гармония** | 65 типов аккордов, свои интервальные формулы и voicing. A/B, стилизация, slash chords, буквенная запись, ступени и транспонирование. |
| **Локальный SketchComposer** | Скетч из аккордов, ударных, баса и мелодии по стилю и seed. Проверка, прослушивание, Apply одной операцией и дальнейшее редактирование. |
| **Jam и Perform** | Пэды 4×4, шаги, квантование, overdub; запуск секций, круговой фильтр, delay, repeat, запись и replay исполнения. |
| **Помощник и голос** | RU/EN Commands; необязательный адаптер FoundationModels для музыкальных запросов на совместимом устройстве. Диктовка отдельно от монофонического Voice-to-MIDI beta с сохранением исходника и ручной коррекцией. |
| **Микшер и MIDI** | Вертикальные фейдеры, pan, mute/solo, Master; CoreMIDI input/output, CC Learn, Panic и интерфейс BLE MIDI. |
| **Проекты и экспорт** | Автосохранение, восстановление и переносимый `.grillapack`; MIDI Type 1, WAV mixdown и выровненные stems, 44.1/48 kHz, 16/24 bit. |
| **Интерфейс** | RU/EN, Light/Dark/System, Dynamic Type и VoiceOver. Статичный Launch Screen и анимация реальной загрузки без искусственной задержки. |

Локальные Commands и SketchComposer работают без Apple Intelligence. Скетчи создаёт локальный музыкальный алгоритм; показанные кадры не демонстрируют генерацию реальной моделью. Доступность FoundationModels зависит от устройства, iOS 26+, готовности Apple Intelligence и языка запроса. Языки AI и диктовки выбираются независимо.

## Попробовать на iPhone

**[Скачать последнюю IPA · La Grilla 1.0.0 (19), 3.4 MiB](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Builds/Testing/LaGrilla-1.0.0-19-unsigned.ipa)** — тестовый кандидат из source `4e85930`: Debug и Release archive прошли, полная native-приёмка ещё открыта. Это неподписанная IPA для подписи своим Apple ID через [Sideloadly](https://sideloadly.io/) на Mac или Windows. Бесплатная Personal Team подходит; подпись обычно обновляется раз в семь дней. [Инструкция, receipt, хеши и предыдущая IPA 17](Builds/Testing/README.md).

Для сборки **19** из исходников нужны Mac, iPhone с iOS 18+ и Xcode 26.3+:

1. Открыть ветку кандидата из [PR #21](https://github.com/alexgazin/la-grilla/pull/21) и [`LaGrilla.xcodeproj`](LaGrilla.xcodeproj).
2. Выбрать свою **Personal Team** в **Signing & Capabilities**, включив automatic signing.
3. Подключить iPhone, подтвердить Trust/Developer Mode и нажать **Run**.

Перед обновлением экспортируйте важные проекты в portable bundle. Проекты кандидата 19 используют **schema 10**: он читает 1…9, а старые приложения не откроют сохранённую schema 10. Версия скачиваемой IPA указана выше; код кандидата и его приёмка — в [CURRENT](docs/release/CURRENT.md). [Подробно про Xcode и установку](docs/DEVELOPMENT.md#run-on-your-own-iphone).

## Настоящее видео работы · сборка 15

[![La Grilla: реальные нажатия, жесты и звук приложения, сборка 15](Media/WorkingDemo/teaser.gif)](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)

**[▶ Смотреть запись — 2:12, Full HD, со звуком](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-working-demo.mp4)** · [Полная исходная запись](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Media/WorkingDemo/la-grilla-session-original.mp4)

Историческая запись **iOS Simulator, 1.0.0 (15)**: Play, аккорды, жесты, пэды, overdub, микшер, Harmony A/B, Commands, Perform и WAV share. Звук снят с выхода тех же сессий; три сессии смонтированы с сокращением ожиданий, действия идут в обычном темпе. Voice показан на подготовке записи. [Источники, монтаж и проверки](Media/WorkingDemo/README.md) сохраняют исходный результат capture-workflow и границы принятой записи.

## Готовность и дальнейшая работа

Ближайший рубеж — закрыть software gate кандидата 19 и повторить пользовательский сценарий на установленном iPhone: звук, разрешённая диктовка, повторная запись/Stop, сохранение, открытие и экспорт. Реальные аудиомаршруты, USB/BLE MIDI, 30-минутные сессии, человеческий напев, FoundationModels и импорт в две DAW остаются отдельной аппаратной приёмкой. Приложение пока не опубликовано в App Store; distribution signing, TestFlight и App Review впереди.

[Текущие доказательства и ограничения](docs/release/CURRENT.md) · [Роадмап](ROADMAP.md) · [34 замечания и план аудитов](docs/review/2026-11-16/PLAN.md) · [Отчёт по реализации](docs/review/2026-11-16/IMPLEMENTATION.md) · [Журнал разработки](docs/IMPLEMENTATION_LOG.md).

<details>
<summary>Исторические экраны, дизайн и промо</summary>

- [73 оригинальных экрана сборки 14](Screenshots/OriginalVision), [EN/RU Store-копии](Screenshots/AppStore).
- [Welcome и Settings сборки 15](Screenshots/ProfessionalShell), [дизайн и OpenArt-происхождение](Design/2026).
- [QA-превью splash сборки 17](Screenshots/LaunchPreview), [разрешённый input и Assistant 17](Screenshots/AuthorizedInput), [восстановление после ошибок сборки 16](Screenshots/DeviceRepair).
- [Историческое промо из скриншотов с отдельным offline-саундтреком](Media/Promo/README.md).

У каждой коллекции собственные source, run и хеши. Splash-превью показывает тот же компонент при явно удержанном QA-представлении и не измеряет время холодного запуска. Исторические медиа не переименовываются в доказательства кандидата 19.

</details>
