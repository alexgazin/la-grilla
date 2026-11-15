# La Grilla support / Поддержка

[Create an issue / Создать обращение](https://github.com/alexgazin/la-grilla/issues)

Include the app version/build, iPhone model, iOS version, audio route and steps to reproduce. Attach a small example only if it contains no private recordings. Portable projects include their original voice assets. Never post credentials, signing keys or personal recordings in a public issue.

Укажите версию приложения, модель iPhone, версию iOS, аудиовыход и шаги воспроизведения проблемы. Прикладывайте пример только без личных записей. Переносимые проекты содержат исходные записи голоса. Не публикуйте ключи, пароли и личные записи в открытых обращениях.

- **No sound:** check track mute/solo, master level, selected output and the iPhone's volume. Retry the audio engine if an error is visible. Bluetooth audio can add latency; wired/USB monitoring is preferable for recording.
- **Нет звука:** проверьте mute/solo, мастер, выбранный выход и громкость iPhone. При ошибке нажмите повторный запуск аудио. Bluetooth-аудио добавляет задержку; для записи предпочтительны проводные/USB-наушники.
- **Voice or dictation unavailable:** check iOS microphone/speech permissions. Dictation needs an available on-device language model. You can always type commands or edit notes manually.
- **Недоступны запись или диктовка:** проверьте разрешения iOS. Для диктовки нужна локальная языковая модель. Команды можно вводить текстом, ноты — вручную.
- **On-device AI unavailable:** it needs iOS 26, an eligible iPhone, enabled Apple Intelligence, a ready model and a supported selected language. Check the Assistant availability message and iOS Settings; use Commands while the model is unavailable. Commands and speech recognition have separate language support.
- **Недоступен локальный ИИ:** нужны iOS 26, совместимый iPhone, включённая Apple Intelligence, готовая модель и поддержка выбранного языка. Проверьте сообщение Ассистента и настройки iOS; пока модель недоступна, пользуйтесь режимом «Команды». Поддержка языков команд, распознавания речи и ИИ различается.
- **Voice draft needs review:** live project edits can change the melody's context. Use Review against current project to preserve the recording and manual corrections, review its placement, then apply. Restore a deleted or shortened target section, or record a new take.
- **Нужно проверить голосовой черновик:** живая правка проекта меняет контекст мелодии. Нажмите «Проверить с текущим проектом», проверьте положение нот и примените результат; исходная запись и ручные исправления сохраняются. Если секция удалена или стала слишком короткой, восстановите её или запишите новый напев.
- **A save failed:** keep the app open, free storage, then use Retry or Save copy. An invalid project can be recovered from its backup as a separate copy in Projects.
- **Ошибка сохранения:** оставьте приложение открытым, освободите место и нажмите «Повторить» или «Сохранить копию». Повреждённый проект можно восстановить отдельной копией из резервного файла в разделе «Проекты».
- **MIDI notes stick:** use Panic, reconnect the device and refresh endpoints. Check the input channel and selected destination. External instruments control their own sound and effects.
- **Зависли MIDI-ноты:** нажмите Panic, переподключите устройство и обновите список. Проверьте входной канал и выбранный выход. Звук и эффекты внешнего инструмента настраиваются в нём.

[Privacy EN](../privacy/en.md) · [Конфиденциальность](../privacy/ru.md)
