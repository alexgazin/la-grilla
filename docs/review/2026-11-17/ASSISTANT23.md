# Помощник23 — оставшиеся проверки после полного main

Исходный main `0cfd12e3e1a821d50c7a1502f627329b7d60ff02`, [run44083683395](https://github.com/alexgazin/la-grilla/actions/runs/44083683395): все73 метода наблюдались,70PASS /2assertionFAIL /1allowance, child/supervisor65, без общего timeout (3455.09s). Четыре SDK-сборки прошли. Все прежние5 проблем Perform/Bass/Transpose и10 сценариев пэдов/нот/тембров/записи/landscape прошли. Это не полный PASS.

## Холодный запуск typed AI fallback

`AIAvailabilityTests/testActualUnavailableModelLocallyReviewsJazzAppliesAndUndoesOnce` исчерпал120s до открытия Assistant. Запрос транспорта шёл через долгие nativeAX обращения; assistant.open появился только на143.66s. Команда, разбор, Review/Apply/Undo до лимита не выполнялись. Причина задержки AX против bootstrap/HAL не установлена; исходная запись и spindump здесь не дают пригодного доказательства внутренней причины.

Фикстура typed AI и typed composition теперь выбирает production output-only startup вместо исторического shared-input priming UI-тестов. Реальная доступность модели не подменяется. AI-тест использует уже читаемый полный transport.value для проверки настоящих inputPriming=outputOnly, inputConfigured=false и error=none и сохраняет bootstrap trace. Лимит120s,15s ожидание старта и вся проверка локального Jazz/Apply/одного Undo/неизменности Review сохранены. Изменение пути не объявляется доказанным исправлением внутренней причины задержки; новый холодный запуск обязан завершиться.

## Возврат из Assistant в Grid

`AssistantCompositionTests/testIdleProposalEndsOnLanguageChangeWithoutEditing` подтвердил EN, STOPPED/Original, отсутствие proposal, закрытие листа,120BPM и отсутствие Undo. Затем ожидание exists&&isHittable остановилось до попытки нажатия аккорда. Оригинальные кадры показывают полностью видимый C без листа, клавиатуры или перекрытия. Точное post-dismiss AX/hit-test состояние не было сохранено; app-bug этим не доказан.

Фикстура проверяет свежий настоящий button snapshot и полное дерево: уникальный identifier, type/label/frame/enabled, отсутствие Assistant, конечные полные границы внутри окна и всех scroll-ancestor viewport. Только затем выполняется один физический контакт измеренного центра. Неверная геометрия останавливает тест до контакта. Исходные editor/chord.symbol=C assertions остаются обязательными. Нет повторов, fallback координат или инъекции состояния;120s и остальные ожидания сохранены.

## Разделение намерений Dictate и Stop

`AuthorizedMicrophoneTests/testGrantedSpeechCallbackAndOutputOnlyAssistantRemainUsable` прошёл настоящее разрешение Speech/микрофона и приём PCM. Затем отложенный Stop-контакт попал в уже изменившийся toggle:90s LISTENING/Stop,93–95s готовый микрофон/No speech detected,96.20s касание,100–103s снова LISTENING. Исходный5s stopped-state wait закономерно завершился ошибкой; последующий recovery хвост не принимался.

В UI теперь два стабильных44pt действия. Start имеет постоянный assistant.dictate и реальную diagnostic JSON; он выключен при recording/requesting/finalizing. Stop имеет assistant.dictation-stop, всегда остаётся на месте, выключен при idle/finalizing и может остановить запись либо отменить ожидание разрешения. Stop идемпотентно вызывает stop/restore lease и не содержит start-пути. Крупный текст переносит Examples на отдельную строку. Используются прежние локализованные ключи.

Тест выполняет один50ms физический контакт настоящего видимого Stop; он безопасен и после автоостановки. Capture30s, finalization2s,5s проверка остановленного состояния, реальные разрешения/PCM, Stop metrics, сохранение ядра/проекта/clock, typed108/Apply/Undo остаются. DictationController, Session и аудиодвижок не меняются; fake grants/PCM/transcript не создаются.

## Проверка следующего source

Отдельный assistant3 использует тот же ios workflow с настоящим host microphone и DragUI setup. Ровно три исходных метода перечислены в selection receipt и обязательны через --require-test. Scope=input-diagnostic, expectedCount=3, fullAcceptance=false;1500s только для этого режима. Полный main сохраняет полный inventory73,3600s supervisor и прежний600s верхний Xcode ceiling; эти три метода сохраняют свои исходные120s. Остальные режимы не меняются. Дополнительный touch10 job в assistant3 не запускается.

Кандидат требует свежих SDK и реального targeted3. После них — интеграция и новый coherent full73 для окончательной software-приёмки. Все прежние failures сохраняются. Аппаратная задержка, датчики, человеческий Voice-to-MIDI, настоящая модель, USB/BLE MIDI/DAW и Store остаются отдельными Pending. Новое промовидео отменено.
