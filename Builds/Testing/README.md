# La Grilla для ручного тестирования

**[Скачать IPA · 1.0.0 (17), 3.2 MiB](https://github.com/alexgazin/la-grilla/raw/refs/heads/main/Builds/Testing/LaGrilla-1.0.0-17-unsigned.ipa)**

Настоящее приложение для **физического iPhone с iOS 18+**, arm64. Это **неподписанная IPA для самостоятельной подписи** на ноутбуке, а не App Store/TestFlight-сборка. Простая пересылка файла на телефон её не установит.

## Установка с Mac или Windows

1. Установить [Sideloadly](https://sideloadly.io/) на ноутбук и подключить iPhone по USB.
2. Выбрать iPhone в Sideloadly, перетащить IPA, указать **свой Apple ID** и нажать Start. Программа подпишет приложение для этого телефона; платная команда Apple Developer не нужна.
3. На iPhone включить Developer Mode, если iOS попросит. При необходимости доверить разработчику: Настройки → Основные → VPN и управление устройством.
4. Открыть La Grilla. Бесплатная Personal Team обычно даёт подпись на **7 дней**; затем приложение нужно переподписать.

Apple ID, пароль, 2FA и профиль остаются у тестировщика. В приложенной IPA нет персонального provisioning profile или чужой подписи.

## Что именно проверено

Бинарник из source `5adbadb37c39911c4acc2c2ef511198867098040`: Debug, unsigned Release archive и Xcode 16.4 / 26.0.1 compatibility PASS; [семь focused native methods](https://github.com/alexgazin/la-grilla/actions/runs/43876565702/attempts/2) — **7 PASS / 0 FAIL / 0 SKIP**. Упаковка повторно проверяет настоящий iPhone Mach-O, weak FoundationModels, CRC, SHA-256 и неизменность каждого файла приложения. Это не принятие физического телефона или App Store.

- [SHA-256](LaGrilla-1.0.0-17-unsigned.sha256).
- [Версия, исходник, архитектура и хеши всех файлов](LaGrilla-1.0.0-17-unsigned.json).
- [Текущий статус и открытая аппаратная приёмка](../../docs/release/CURRENT.md).

Начать проверку со звука демо, затем Assistant → диктовка → Stop → команда «Темп 110» → Review/Apply/Undo; проверить повторную запись, создание пустого проекта, добавление аккорда, сохранение и повторный запуск. Для локальных Commands Apple Intelligence не требуется. Доступность реальной модели, человеческая транскрипция, маршруты и индикатор микрофона проверяются отдельно на установленном приложении.
