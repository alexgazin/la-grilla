# Сборка23 — согласованное наблюдение режима и позиции клипа

## Оригинальный полный результат8bc

Exact source `8bc7866c0da5ecf330deaafeaf107ac2b881ec79`, [run44140208148,attempt1](https://github.com/alexgazin/la-grilla/actions/runs/44140208148), native job134240633137. Все73 обязательных метода наблюдались: **71PASS / 2FAIL / 0case-allowance**. Native supervisor достиг общего3600s: elapsed3621.266s,exit124,subprocess−15,timedOut=true. Полная приёмка корректно отклонена. SDK4 и source-bound IPA прошли; файл остаётся ручной альфой.

Прежние проблемные методы теперь действительно прошли целиком: LiveEditing duplicate→earlier→later→delete→восстановленный count→четыре PLAYING→Done→настоящий Stop — **PASS83.255s**. Сразу следующий PadContact успешно запустился, выполнил настоящий1.2s контакт, accepted1/held0/timing>0.8, следующий tapaccepted2 и terminate — **PASS13.483s**. Эти два PASS не заменяют неуспешный полный набор.

Оригинальный итоговый ZIP14360221600:329852369bytes,SHA-256 `dcdc3c20663a34fafedbdd17a78ce0be36547d29699793d10e6ce1027065513a`,CRC1126PASS. Tiny/full scope совпадают побайтно, raw и decoded logs подтверждают один и тот же inventory73. Actual DragUI-preflight ready=true,21.362s,druid12600,fresh listener17:54:44.503;17hostcontrolsPASS11.315s. Приписывать failures недоступному Druid оснований нет.

## Pinch: выполнение остановилось до жестов

`ArrangementUITests/testPinchRetainsScrolledMusicalCenterWithoutEditingOrStopping` не дошёл до pan,pinch или Play. В launch ожидался KVC value `Clips` у `grid.mode.clips` в прежнем6s окне. Оригинальные AX snapshots на case13.352s и14.327s уже содержат настоящую Button `grid.mode.clips`,label Edit chords,value Clips. Оригинальные кадры case12.045667s и16.062333s внутри окна также показывают Clips UI.

Runner начал remote query, затем прервал его watchdog ожидания: `XCTFuture Code1001,Interrupted by waiter`. Ответ приложения пришёл позже уже подтверждённого правильного состояния. Это ошибка наблюдения launch readiness; wrong mode или ошибка anchor этим прогоном не доказаны. Concurrent Apple Intelligence banner виден в одном кадре, но его причинность не установлена. Сбой остаётся FAIL, pinch-body не принят.

Точные оригинальные SHA/member IDs и временная шкала сохранены в `pinch-original-audit/pinch-failure-classification.json` внутри локального evidence-набора этого run. Сохранены исходные video/session/app stdout, decoded metadata и происхождение каждого извлечённого кадра; новое видео не создавалось.

## Wide clip: правильные frame/value уже получены внутри6s

`testWideClipNativeDragRetainsTouchOffset` выполнил реальный drag. Native trace: grabOffset3026,raw3840.666→bounded/snapped3840,operation2(move),applied=true,revision1. Оригинальный recording показывает2:1→6:1. Для того же PID22345/AXnode4393081952.98 frame x155 поступил18:03:18.449,value4.00bars —18.526, до номинальногоdeadline19.115.

Predicate последовательно запрашивал clip.exists,clip.frame иclip.value. После уже полученных правильных полей18.598 начался ещё один Find; watchdog19.452 прервал его, результат ожидания timedOut. Правильные координаты и длина существовали внутри исходного окна, а лишний remote query исчерпал его. Это не доказанная ошибка placement или потери grab offset. Inspector и Undo tail не исполнились, поэтому исходный метод остаётся FAIL. Полная сохранённая шкала — `wide-drag-forensics/analysis-report.json` в evidence-наборе run.

## Узкие изменения наблюдения

Launch readiness и waitForClipPosition читают один свежий immutable app.snapshot на poll. Каждый наблюдатель ищет настоящий Button с ожидаемым реальным identifier; проверяет actual value, а для клипа также конечную непустую геометрию и прежний допуск3pt. Недоступный, неправильный или отсутствующий узел остаётся ошибкой. Значения берутся из одного согласованного snapshot; повторных live Find внутри predicate нет.

Оба исходных6s окна, case120s, все тела/действия, сам native drag/pinch, lift/dwell, transport/nonmutation/inspector/Undo и остальные утверждения сохраняются. App,DSP,Pad и жесты продукта не меняются. Новые expected values, инъекции состояния, повторные жесты и skip не добавляются. Новая runtime-приёмка ещё Pending.

## Бюджет завершения полного отчёта

Последний из73 методов завершился18:54:45.262; общий supervisor deadline был18:54:45.647 — запас всего0.385s. Команда ещё работала; interrupt18:54:47.206 оборвал XCTest finalization. В исходном bundle сохранились Data/Staging, но отсутствует xcresult Info.plist; стандартный export0frames/exit1. Выдавать такой исход за успешный нельзя.

Для следующего полного source общий command budget становится65min(3900s), отдельный runner step70min; shared job-clock deadline80min внутри прежнего90min job оставляет10min на evidence. Per-case budgets, Xcode600 ceiling, focused1500 и весь обязательный inventory73 не меняются. Это запас для реального завершения полного процесса и отчёта; он не снимает assertions и не переписывает71/73 failures.

Следующий обязательный результат — один свежий coherent full73 и SDK4 на новом exact source. Старые71/73 и timeout сохранены. Hardware, человеческий голос/модель, MIDI/DAW и Store остаются отдельными Pending. Новое промовидео отменено.
