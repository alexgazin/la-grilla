# La Grilla для ручного тестирования

**[Скачать последнюю тестовую сборку · 1.0.0 (20), ZIP с IPA](https://github.com/alexgazin/la-grilla/actions/runs/43957824077/artifacts/14273365913)**

Для **физического iPhone с iOS 18+**, arm64. Неподписанная IPA: тестировщик подписывает её своим Apple ID на ноутбуке. Простая пересылка файла на телефон её не установит.

## Установка с Mac или Windows

1. Войти в GitHub, скачать [архив сборки 20](https://github.com/alexgazin/la-grilla/actions/runs/43957824077/artifacts/14273365913) и извлечь `LaGrilla-unsigned.ipa`. ZIP содержит также исходные отчёты сборки.
2. Установить [Sideloadly](https://sideloadly.io/) и подключить iPhone по USB.
3. Выбрать iPhone, перетащить IPA, указать **свой Apple ID**, нажать Start. Платная команда Apple Developer не нужна.
4. На iPhone включить Developer Mode, если iOS попросит. При необходимости доверить разработчику: Настройки → Основные → VPN и управление устройством.
5. Открыть La Grilla. Бесплатная Personal Team обычно даёт подпись на **7 дней**; затем приложение нужно переподписать.

Apple ID, пароль, 2FA и профиль остаются у тестировщика. В IPA нет персонального provisioning profile или чужой подписи.

## Тестовая IPA 20

Source [`6bb06b5c1f05e0b937e2c4aba670efc72f629c41`](https://github.com/alexgazin/la-grilla/commit/6bb06b5c1f05e0b937e2c4aba670efc72f629c41), schema 10, 703 EN/RU ключа. В 20 есть локальные редактируемые скетчи, A/B, Apply/Undo, транспонирование и сохранённое написание аккордов; импортированный проект на 8/16 тактов получает полный диапазон воспроизведения. Commands и локальный композитор работают без Apple Intelligence.

**Статус: неподписанный тестовый кандидат. Полная программная и аппаратная приёмка не завершена.** Код этой ветки — кандидат 20 из [PR #21](https://github.com/alexgazin/la-grilla/pull/21); его новый полный программный результат ещё требуется получить.

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
