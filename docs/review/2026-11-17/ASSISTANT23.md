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

## Фактический итог db8 и бюджет полного Speech-сценария

Source `db8a0229a685dadad1d5af700f7ff373ea1b30ba`, [run 44101612193](https://github.com/alexgazin/la-grilla/actions/runs/44101612193): наблюдались ровно три обязательных метода. AI local Jazz и idle language Composition прошли; Granted Speech достиг собственного исходного 120s allowance. Итог — **2 PASS / 1 allowance**, child/supervisor 65, без wrapper timeout, 393.298s. Это не принятый targeted3. Описанный выше исходный 120s бюджет относится к этому запуску и не меняется задним числом.

Стабильный Stop получил реальный контакт на 72.22s; завершённое состояние зафиксировано на 75.28s. Разрешения Speech/микрофона настоящие, on-device Speech доступен, принято 1 437 960 PCM frames. Диагностика содержит recording/requesting/finalizing=false и «No speech detected» (kAFAssistantErrorDomain 1110); успешная транскрипция не заявляется. Настоящие Stop metrics: tap removal 0.636292ms, worker drain 0.069042ms, output restoration 265.057041ms, total 265.7865ms; synchronous stop 267.766709ms. Эти измерения host Simulator не являются гарантией задержки телефона.

Output-only receipt на 75.78s подтвердил сохранённые kernel/project/revision, actualPlaying=1, error=none, один input transition и retirement, currentGraphHasInputNode=false, activeAudioGraphCount=1 и продвижение clock. Далее тест в том же Assistant набрал `tempo 108`, получил настоящий Review `108 BPM` на 113.98s и применил его на 115.78s. Assistant был закрыт на 118.16s. Запрос studio.tempo начался на 119.83s, когда общий 120s бюджет закончился. После allowance журнал ещё фиксирует Undo 120.63s, синтез касания 121.53s и чтение tempo 122.22s; эти поздние действия не превращаются в успешную приёмку.

Для следующего source в setUp назначается **180s только точному `testGrantedSpeechCallbackAndOutputOnlyAssistantRemainUsable`** по имени XCTest-case, до входа в метод. Все остальные AuthorizedMicrophoneTests сохраняют 120s. Это общий бюджет сценария с двумя настоящими процессами, TCC/PCM/Speech, Stop metrics, проверкой непрерывности output и typed Apply/Undo; все явные ожидания сохраняют прежние 5/8/15/20/35s; это не жёсткая граница длительности каждого XCTest-вызова или ожидания quiescence. Production capture 30s, finalization 2s, 5s stopped-state predicate, весь набор assertions и физический Stop-контакт не меняются. App-код, контроллер, workflow, flags, selection receipt и ровно три строгих обязательных метода остаются прежними.

Повторная проверка того же strict targeted3 на новом source — **Pending**. Старые main 0cfd (70/73) и db8 allowance сохраняются как реальные неуспешные результаты; нет скрытых повторов, пропуска recovery-хвоста или повышения лимитов других тестов. Новое промовидео отменено.
