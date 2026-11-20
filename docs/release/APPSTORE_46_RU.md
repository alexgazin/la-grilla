# App Store · кандидат 1.0.0 (46) и передача владельцу

| Пункт | Значение |
| --- | --- |
| Версия / сборка | 1.0.0 (46), `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` совпадают в `project.yml`, генераторе и проекте Xcode |
| Устройства | iPhone (`TARGETED_DEVICE_FAMILY = 1`), iOS 18.0 и новее, портрет и альбомная ориентация |
| Схема проекта | 15, формат не менялся; проекты сборки 43 открываются без миграции |
| Исходный SHA | `d298c17` (main, сборка 43) |
| Финальный SHA | последний коммит PR; результаты CI на нём — в [CURRENT](CURRENT.md) |

## Статусы выпуска

| Этап | Состояние |
| --- | --- |
| Кандидат собран (unsigned Release‑архив и Debug‑сборки в CI) | см. CURRENT: выставляется по факту прохождения CI на финальном SHA |
| Установлен из TestFlight | **нет** — нужна подпись владельца |
| Отправлен в App Review | **нет** |
| Одобрен Apple | **нет** |

## Что подготовлено

- **Архив и dSYM.** Задание `release-archive` в [iOS build and verification](../../.github/workflows/ios.yml) собирает оптимизированный arm64‑архив без подписи и проверяет бинарь (`scripts/release/audit_binary.py`): deployment target, SDK, UUID, слабую привязку FoundationModels. dSYM сохраняется в артефакте. Unsigned IPA для личного тестера по‑прежнему собирается отдельным каналом (`scripts/release/package_sideload_ipa.py`) и требует переподписи своим Apple ID.
- **Тексты магазина RU/EN** (`docs/store/*`). Обновлены описание («Правки словами и палитры») и «Что нового». Лимиты App Store Connect проверяются `scripts/release/audit_release.py`.
- **Приватность.** Повторный аудит сборки 46 записан в [PRIVACY_AUDIT](PRIVACY_AUDIT.md). Новых разрешений, сетевых запросов и SDK нет. Ответ App Privacy — «Data Not Collected». Privacy manifest не менялся.
- **Лицензии звуков.** Новые звуки палитр — собственные генераторы приложения (`FactoryDrumKit`) и встроенные синтезированные тембры. Скачанных сэмплов нет.
- **Скриншоты.** Нативные снимки сценариев 45 и 46 снимаются UI‑тестами `SongEditUITests` и `PaletteUITests`. Копии для магазина нужных размеров готовит `scripts/release/prepare_store_screenshots.py` из нативных PNG конкретного прогона.

## Короткий путь для ревьюера

1. Запустите приложение и закройте экран «Getting started» (Skip или Start creating). Откроется студия с текущим проектом.
2. Jam: сыграйте на пэдах с включённым метрономом, Record → четыре такта → Record.
3. Assistant: введите «Remove the kick in the first two bars» (или «Убери бочку в первых двух тактах»). Нажмите Review command, прослушайте A и B и нажмите Apply. Undo вернёт исходник.
4. Mixer → Palettes: выберите Boom bap, дождитесь выравнивания громкости, прослушайте A/B и нажмите Apply.
5. Export → WAV или MIDI.

**Apple Intelligence.** Необязателен. Правки словами, палитры и команды работают локально без модели и в авиарежиме. Свободные описания через Foundation Models доступны только на iPhone с поддержкой Apple Intelligence, iOS 26 и при готовой системной модели выбранного языка. В остальных случаях приложение явно показывает режим «Команды».

## Что остаётся владельцу

1. Выбрать команду Apple Developer, подписать архив своим сертификатом distribution и профилем (`scripts/release/sign_and_export.sh`, ключи и профили в репозиторий не добавляются).
2. Загрузить проверенный билд в TestFlight (`distribution.yml`, требует доступа App Store Connect), установить его и повторить основной путь на подписанной сборке.
3. Проверить актуальные требования App Store Connect, заполнить App Privacy («Data Not Collected») и выбрать версию для App Review.
4. Отмечать в таблице статусов только фактические состояния: «установлен из TestFlight», «отправлен в App Review», «одобрен Apple».
